import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:rhttp/rhttp.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'package:namida/class/file_parts.dart';
import 'package:namida/class/subtitle_srt.dart';
import 'package:namida/controller/ai_subtitle/ai_asr_shared.dart';
import 'package:namida/controller/ai_subtitle/ai_subtitle_config.dart';
import 'package:namida/controller/ai_subtitle/ai_subtitle_models.dart';
import 'package:namida/core/extensions.dart';

/// sherpa-onnx offline recognition (sense-voice / paraformer).
///
/// Offline models consume a whole utterance per decode, so long audio is cut
/// into ~30s windows whose edges snap to the quietest nearby frame - cutting at
/// a fixed offset slices words in half. Everything heavy (model load, decode)
/// runs in its own isolate: the ffi call is synchronous and would freeze the
/// ui isolate for seconds per window otherwise.
class SherpaOnnxAsrEngine implements AiAsrEngine {
  @override
  String get label => 'sherpa-onnx';

  static const _sampleRate = 16000;

  /// 0.5s rms frames, both for the boundary snapping and for file scanning.
  static const _frameSamples = 8000;
  static const _windowFrames = 56; // 28s, sense-voice is trained on ~30s
  static const _snapFrames = 4; // look ±2s around a boundary for a quiet spot

  @override
  Future<List<SubtitleSrtCue>> transcribe(
    File audio, {
    required AiAsrSettings settings,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final dirPath = await _checkedModelDir(settings);

    onProgress?.call(0);
    final pcm = await AiAsrShared.toVoskPcm(audio);
    try {
      final words = await _wordsFromIsolate(pcm.path, settings, dirPath, onProgress: onProgress, cancelToken: cancelToken);

      final cues = SubtitleSrt.splitLongCues(SubtitleSrt.normalize(AiAsrShared.wordsToCues(words)));
      if (cues.isEmpty) {
        throw const AiAsrException('Nothing was recognized in this audio');
      }
      return cues;
    } finally {
      pcm.delete().ignoreError();
    }
  }

  @override
  Future<void> testConnection(AiAsrSettings settings, {CancelToken? cancelToken}) async {
    final dirPath = await _checkedModelDir(settings);

    final probe = Completer<void>();
    final port = ReceivePort();
    Isolate? isolate;
    StreamSubscription<dynamic>? sub;

    sub = port.listen((message) {
      if (message is List && message.isNotEmpty) {
        switch (message.first) {
          case 'done':
            if (!probe.isCompleted) probe.complete();
          case 'error':
            if (!probe.isCompleted) probe.completeError(AiAsrException('${message.last}'));
        }
      }
    });

    try {
      isolate = await Isolate.spawn(
        _isolateMain,
        _IsolateRequest(mainPort: port.sendPort, pcmPath: '', settings: settings, modelDir: dirPath, testOnly: true),
        errorsAreFatal: true,
      );
      await probe.future.timeout(const Duration(minutes: 3));
    } on TimeoutException {
      throw const AiAsrException('Loading the model took too long');
    } catch (e) {
      throw AiAsrException('$e');
    } finally {
      isolate?.kill(priority: Isolate.immediate);
      await sub.cancel();
      port.close();
    }
  }

  /// Spawns the worker, wires progress/cancel, and hands back the words on
  /// success. A thrown [AiAsrException] means the user cancelled or it failed.
  Future<List<({double start, double end, String word})>> _wordsFromIsolate(
    String pcmPath,
    AiAsrSettings settings,
    String dirPath, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) {
    if (cancelToken?.isCancelled ?? false) {
      throw const AiAsrException('Cancelled');
    }

    final words = Completer<List<({double start, double end, String word})>>();
    final port = ReceivePort();
    Isolate? isolate;
    SendPort? workerPort;
    StreamSubscription<dynamic>? sub;
    var finished = false;

    void finish() {
      if (finished) return;
      finished = true;
      isolate?.kill(priority: Isolate.immediate);
      sub?.cancel();
      port.close();
    }

    sub = port.listen((message) {
      if (message is List && message.isNotEmpty) {
        switch (message.first) {
          case 'cancelPort':
            workerPort = message.last;
            // -- the isolate cannot see the token, the state is relayed whenever
            // -- the worker reports in, taking effect at the next window edge.
            if (cancelToken?.isCancelled ?? false) workerPort?.send('cancel');
          case 'progress':
            onProgress?.call((message.last as num).toDouble());
            if (cancelToken?.isCancelled ?? false) workerPort?.send('cancel');
          case 'done':
            final result = (message.last as List).cast<({double start, double end, String word})>();
            if (!words.isCompleted) words.complete(result);
            finish();
          case 'error':
            if (!words.isCompleted) words.completeError(AiAsrException('${message.last}'));
            finish();
        }
      }
    });

    () async {
      try {
        isolate = await Isolate.spawn(
          _isolateMain,
          _IsolateRequest(mainPort: port.sendPort, pcmPath: pcmPath, settings: settings, modelDir: dirPath, testOnly: false),
          errorsAreFatal: true,
        );
      } catch (e) {
        if (!words.isCompleted) words.completeError(AiAsrException('$e'));
        finish();
      }
    }();

    return words.future;
  }

  static Future<String> _checkedModelDir(AiAsrSettings settings) async {
    final info = AiSubtitleModels.sherpaInfoFor(settings.localModelName);
    if (info == null) {
      throw AiAsrException('No sherpa-onnx model is selected for ${settings.engine.label}, pick one on the local models page');
    }

    final dirPath = await AiSubtitleModels.localModelPath(settings.localModelName);
    if (dirPath.isEmpty || !Directory(dirPath).existsSync()) {
      throw const AiAsrException('The model is not downloaded yet, get it from the local models page');
    }
    for (final file in info.files) {
      if (!File(FileParts.joinPath(dirPath, file)).existsSync()) {
        throw AiAsrException('The model is incomplete ($file is missing), download it again');
      }
    }
    return dirPath;
  }

  /// -- everything below runs inside the spawned isolate --

  static void _isolateMain(_IsolateRequest request) {
    final cancelPort = ReceivePort();
    var cancelled = false;
    cancelPort.listen((_) => cancelled = true);
    request.mainPort.send(['cancelPort', cancelPort.sendPort]);

    try {
      sherpa.initBindings();

      final recognizer = _createRecognizer(request.settings, request.modelDir);
      try {
        if (request.testOnly) {
          request.mainPort.send(['done', 'ok']);
          return;
        }

        final pcmFile = File(request.pcmPath);
        final totalSamples = pcmFile.lengthSync() ~/ 2;
        if (totalSamples == 0) {
          throw const AiAsrException('The audio file has no decodable content');
        }

        // -- pass 1: a mean square per 0.5s frame decides where windows may cut.
        final frames = _frameMeanSquare(pcmFile, totalSamples);
        final boundaries = _boundaries(frames.length, (i) => frames[i]);

        final words = <({double start, double end, String word})>[];
        for (var i = 0; i < boundaries.length - 1; i++) {
          if (cancelled) throw const AiAsrException('Cancelled');

          final startSample = boundaries[i] * _frameSamples;
          final endSample = min(boundaries[i + 1] * _frameSamples, totalSamples);
          final offset = startSample / _sampleRate;

          final stream = recognizer.createStream();
          stream.acceptWaveform(samples: _windowSamples(pcmFile, startSample, endSample), sampleRate: _sampleRate);
          recognizer.decode(stream);
          final result = recognizer.getResult(stream);
          stream.free();

          words.addAll(
            _wordsOf(
              result,
              offset: offset,
              fallbackEnd: (endSample - startSample) / _sampleRate,
            ),
          );

          final progress = (i + 1) / (boundaries.length - 1);
          request.mainPort.send(['progress', progress.clamp(0.0, 1.0)]);
        }

        if (words.isEmpty) {
          throw const AiAsrException('Nothing was recognized in this audio');
        }
        request.mainPort.send(['done', words]);
      } finally {
        recognizer.free();
      }
    } catch (e) {
      request.mainPort.send(['error', '$e']);
    } finally {
      cancelPort.close();
    }
  }

  static sherpa.OfflineRecognizer _createRecognizer(AiAsrSettings settings, String dirPath) {
    final info = AiSubtitleModels.sherpaInfoFor(settings.localModelName)!;
    final files = info.files;
    final tokensPath = FileParts.joinPath(dirPath, _fileOf(files, 'tokens'));
    final threads = (Platform.numberOfProcessors - 1).clamp(1, 4);

    final modelConfig = switch (info.engine) {
      AiLocalAsrEngine.whisper => sherpa.OfflineModelConfig(
          tokens: tokensPath,
          whisper: sherpa.OfflineWhisperModelConfig(
            encoder: FileParts.joinPath(dirPath, _fileOf(files, '-encoder.')),
            decoder: FileParts.joinPath(dirPath, _fileOf(files, '-decoder.')),
            language: info.name.endsWith('.en') ? '' : _whisperLanguage(settings.languageCode),
            task: 'transcribe',
            enableTokenTimestamps: true,
          ),
          numThreads: threads,
          debug: false,
          provider: 'cpu',
        ),
      AiLocalAsrEngine.moonshine => sherpa.OfflineModelConfig(
          tokens: tokensPath,
          moonshine: sherpa.OfflineMoonshineModelConfig(
            preprocessor: FileParts.joinPath(dirPath, _fileOf(files, RegExp('^preprocess'))),
            encoder: FileParts.joinPath(dirPath, _fileOf(files, RegExp('^encode'))),
            uncachedDecoder: FileParts.joinPath(dirPath, _fileOf(files, RegExp('^uncached'))),
            cachedDecoder: FileParts.joinPath(dirPath, _fileOf(files, RegExp('^cached'))),
          ),
          numThreads: threads,
          debug: false,
          provider: 'cpu',
        ),
      AiLocalAsrEngine.paraformer => sherpa.OfflineModelConfig(
          tokens: tokensPath,
          paraformer: sherpa.OfflineParaformerModelConfig(model: FileParts.joinPath(dirPath, files.first)),
          numThreads: threads,
          debug: false,
          provider: 'cpu',
        ),
      _ => sherpa.OfflineModelConfig(
          tokens: tokensPath,
          senseVoice: sherpa.OfflineSenseVoiceModelConfig(
            model: FileParts.joinPath(dirPath, files.first),
            language: _senseVoiceLanguage(settings.languageCode),
            useInverseTextNormalization: true,
          ),
          numThreads: threads,
          debug: false,
          provider: 'cpu',
        ),
    };

    return sherpa.OfflineRecognizer(sherpa.OfflineRecognizerConfig(model: modelConfig));
  }

  /// Picks the file matching [pattern], so model file name variations do not
  /// need a per model branch here.
  static String _fileOf(List<String> files, Pattern pattern) {
    return files.firstWhere((file) => pattern.allMatches(file).isNotEmpty, orElse: () => files.first);
  }

  /// sense-voice reads an empty language as "detect it", anything that is not
  /// one of its languages is better left to that auto detection.
  static String _senseVoiceLanguage(String code) {
    const supported = ['zh', 'en', 'ja', 'ko', 'yue'];
    final lower = code.toLowerCase();
    return supported.contains(lower) ? lower : '';
  }

  /// whisper speaks iso codes, an unknown or empty one means auto detect.
  static String _whisperLanguage(String code) {
    final match = RegExp(r'^([a-z]{2})', caseSensitive: false).firstMatch(code.trim().toLowerCase());
    return match?.group(1) ?? '';
  }

  /// Reads the pcm once, producing the mean square per [_frameSamples] window.
  static Float32List _frameMeanSquare(File pcm, int totalSamples) {
    final frameCount = (totalSamples / _frameSamples).ceil();
    final frames = Float32List(frameCount);

    final random = pcm.openSync();
    try {
      final bytes = Uint8List(_frameSamples * 2);
      final view = ByteData.sublistView(bytes);

      for (var frame = 0; frame < frameCount; frame++) {
        final wanted = min(bytes.length, (totalSamples - frame * _frameSamples) * 2);
        if (wanted <= 0) break;
        random.readIntoSync(bytes, 0, wanted);

        var sum = 0.0;
        final samples = wanted ~/ 2;
        for (var i = 0; i < samples; i++) {
          final v = view.getInt16(i * 2, Endian.little) / 32768.0;
          sum += v * v;
        }
        frames[frame] = samples > 0 ? sum / samples : 1.0;
      }
    } finally {
      random.closeSync();
    }
    return frames;
  }

  /// Window edges snapped to the quietest frame around the fixed grid, so
  /// speech is not cut mid word.
  static List<int> _boundaries(int frameCount, double Function(int frame) meanSquare) {
    final boundaries = <int>[0];
    var position = 0;

    while (frameCount - position > _windowFrames * 3 ~/ 2) {
      final target = position + _windowFrames;
      var best = target;
      var bestValue = meanSquare(target);
      for (var i = max(target - _snapFrames, position + _windowFrames ~/ 2); i <= min(target + _snapFrames, frameCount - 1); i++) {
        if (meanSquare(i) < bestValue) {
          best = i;
          bestValue = meanSquare(i);
        }
      }
      boundaries.add(best);
      position = best;
    }

    boundaries.add(frameCount);
    return boundaries;
  }

  static Float32List _windowSamples(File pcm, int startSample, int endSample) {
    final count = endSample - startSample;
    final bytes = Uint8List(count * 2);

    final random = pcm.openSync();
    try {
      random.setPositionSync(startSample * 2);
      random.readIntoSync(bytes);
    } finally {
      random.closeSync();
    }

    final view = ByteData.sublistView(bytes);
    final samples = Float32List(count);
    for (var i = 0; i < count; i++) {
      samples[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return samples;
  }

  /// Token runs become words: a `▁`/`Ġ` prefix starts one, and so does the
  /// script flipping (an english word followed by a han character must not
  /// merge). Models without timestamps (moonshine) get their runs spread over
  /// the window weighted by text length - approximate, but readable.
  static List<({double start, double end, String word})> _wordsOf(
    sherpa.OfflineRecognizerResult result, {
    required double offset,
    required double fallbackEnd,
  }) {
    final tokens = result.tokens;
    if (tokens.isEmpty) return const [];

    final special = RegExp(r'^<\|.*\|>$');
    final cjk = RegExp(r'[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uac00-\ud7af]');

    // -- pass 1: merge tokens into runs, remembering each run's token range.
    final runs = <({String text, int first, int last})>[];
    final runText = StringBuffer();
    var runFirst = 0;

    void flushRun(int lastIndex) {
      final text = runText.toString().trim();
      if (text.isNotEmpty) {
        runs.add((text: text, first: runFirst, last: lastIndex));
      }
      runText.clear();
    }

    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      if (special.hasMatch(token)) continue;

      var clean = token.replaceAll('▁', '').replaceAll('Ġ', ' ').replaceAll('ĉ', ' ').trim();
      if (clean.isEmpty) continue;

      final previous = runText.isEmpty ? '' : runText.toString().substring(runText.length - 1);
      final startsRun = token.startsWith('▁') || token.startsWith('Ġ') || (previous.isNotEmpty && cjk.hasMatch(previous) != cjk.hasMatch(clean));

      if (runText.isNotEmpty && startsRun) {
        flushRun(i - 1);
        runFirst = i;
      } else if (runText.isEmpty) {
        runFirst = i;
      }
      runText.write(clean);
    }
    flushRun(tokens.length - 1);

    if (runs.isEmpty) return const [];

    // -- pass 2: real timestamps when the model has them, an even spread else.
    final timestamps = result.timestamps;
    final words = <({double start, double end, String word})>[];

    if (timestamps.isNotEmpty) {
      for (final run in runs) {
        final start = (run.first < timestamps.length ? timestamps[run.first] : fallbackEnd) + offset;
        final end = (run.last + 1 < timestamps.length ? timestamps[run.last + 1] : fallbackEnd) + offset;
        words.add((start: start, end: end > start ? end : start + 0.2, word: run.text));
      }
      return words;
    }

    final totalChars = runs.fold<int>(0, (sum, run) => sum + run.text.length);
    if (totalChars == 0) return const [];
    var cursor = 0.0;
    for (final run in runs) {
      final share = fallbackEnd * run.text.length / totalChars;
      words.add((start: offset + cursor, end: offset + cursor + share, word: run.text));
      cursor += share;
    }
    return words;
  }
}

class _IsolateRequest {
  final SendPort mainPort;
  final String pcmPath;
  final AiAsrSettings settings;
  final String modelDir;
  final bool testOnly;

  const _IsolateRequest({
    required this.mainPort,
    required this.pcmPath,
    required this.settings,
    required this.modelDir,
    required this.testOnly,
  });
}
