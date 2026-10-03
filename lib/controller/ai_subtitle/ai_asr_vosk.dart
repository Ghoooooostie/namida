import 'dart:convert';
import 'dart:io';

import 'package:rhttp/rhttp.dart';
import 'package:vosk_flutter_fixed/vosk_flutter.dart';

import 'package:namida/class/subtitle_srt.dart';
import 'package:namida/controller/ai_subtitle/ai_asr_shared.dart';
import 'package:namida/controller/ai_subtitle/ai_subtitle_config.dart';
import 'package:namida/controller/ai_subtitle/ai_subtitle_models.dart';
import 'package:namida/core/extensions.dart';

/// Fully offline recognition. Whisper and the sherpa-onnx family need a native
/// runtime that is not bundled yet, see [AiLocalAsrEngine.isAvailable].
class VoskAsrEngine implements AiAsrEngine {
  @override
  String get label => 'Vosk';

  /// vosk only answers once it decoded a whole utterance, so progress is the
  /// amount of audio already fed rather than a real percentage.
  static const _kChunkBytes = 32000 * 2; // 1s of 16k mono s16le

  @override
  Future<List<SubtitleSrtCue>> transcribe(
    File audio, {
    required AiAsrSettings settings,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final modelName = settings.localModelName.isEmpty ? AiLocalAsrEngine.vosk.defaultModelName! : settings.localModelName;
    final modelPath = await AiSubtitleModels.localModelPath(modelName);
    if (!Directory(modelPath).existsSync()) {
      throw const AiAsrException('The Vosk model is not downloaded yet, get it from the local models page');
    }

    onProgress?.call(0);
    final pcm = await AiAsrShared.toVoskPcm(audio);
    final totalBytes = pcm.lengthSync();
    if (totalBytes == 0) {
      pcm.delete().ignoreError();
      throw const AiAsrException('The audio file has no decodable content');
    }

    Recognizer? recognizer;
    try {
      final vosk = VoskFlutterPlugin.instance();
      final model = await vosk.createModel(modelPath);
      recognizer = await vosk.createRecognizer(model: model, sampleRate: AiAsrShared.voskSampleRate);
      // -- word timings are the only way to get a usable timeline out of vosk.
      await recognizer.setWords(words: true);

      final words = <({double start, double end, String word})>[];
      final handle = await pcm.open();
      var read = 0;

      while (read < totalBytes) {
        if (cancelToken?.isCancelled ?? false) {
          throw const AiAsrException('Cancelled');
        }

        // -- RandomAccessFile.read only takes a byte count, the tail is shorter.
        final wanted = (totalBytes - read).clamp(0, _kChunkBytes);
        final slice = await handle.read(wanted);
        if (slice.isEmpty) break;
        read += slice.length;

        if (await recognizer.acceptWaveformBytes(slice)) {
          words.addAll(parseWords(await recognizer.getResult()));
        } else {
          // -- partials are only good for progress, they are not stable output.
          await recognizer.getPartialResult();
        }

        onProgress?.call((read / totalBytes).clamp(0, 1));
      }

      await handle.close();
      words.addAll(parseWords(await recognizer.getFinalResult()));

      final cues = AiAsrShared.wordsToCues(words);
      if (cues.isEmpty) {
        throw const AiAsrException('Vosk did not recognize any speech in this audio');
      }
      return cues;
    } finally {
      await recognizer?.dispose();
      pcm.delete().ignoreError();
    }
  }
  static List<({double start, double end, String word})> parseWords(String result) {
    if (result.isEmpty) return const [];
    try {
      final json = jsonDecode(result) as Map<String, dynamic>;
      final list = json['result'];
      if (list is! List) return const [];

      final words = <({double start, double end, String word})>[];
      for (final item in list) {
        if (item is! Map) continue;
        final word = item['word']?.toString() ?? '';
        final start = item['start'];
        final end = item['end'];
        if (word.isEmpty || start is! num || end is! num) continue;
        words.add((start: start.toDouble(), end: end.toDouble(), word: word));
      }
      return words;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> testConnection(AiAsrSettings settings, {CancelToken? cancelToken}) async {
    final modelName = settings.localModelName.isEmpty ? AiLocalAsrEngine.vosk.defaultModelName! : settings.localModelName;
    final modelPath = await AiSubtitleModels.localModelPath(modelName);
    if (!Directory(modelPath).existsSync()) {
      throw const AiAsrException('The Vosk model is not downloaded yet');
    }

    // -- loading the model is the only honest check, the rest needs real audio.
    final vosk = VoskFlutterPlugin.instance();
    final model = await vosk.createModel(modelPath);
    final recognizer = await vosk.createRecognizer(model: model, sampleRate: AiAsrShared.voskSampleRate);
    await recognizer.dispose();
  }
}
