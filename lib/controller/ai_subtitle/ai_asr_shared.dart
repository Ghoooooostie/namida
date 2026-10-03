import 'dart:convert';
import 'dart:io';

import 'package:rhttp/rhttp.dart';

import 'package:namida/class/file_parts.dart';
import 'package:namida/class/subtitle_srt.dart';
import 'package:namida/controller/ai_subtitle/ai_subtitle_config.dart';
import 'package:namida/controller/platform/ffmpeg_executer/ffmpeg_executer.dart';
import 'package:namida/core/constants.dart';

/// A recognition failure with something worth showing to the user.
class AiAsrException implements Exception {
  final String message;
  const AiAsrException(this.message);

  @override
  String toString() => message;
}

/// Turns an audio file into cues. Implementations are stateless, [AiAsrSettings]
/// carries everything a job needs so a settings change mid batch cannot break it.
abstract class AiAsrEngine {
  /// shown in the task list
  String get label;

  Future<List<SubtitleSrtCue>> transcribe(
    File audio, {
    required AiAsrSettings settings,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  });

  /// A cheap round trip that only proves the key, the base url and the model name
  /// are usable. Uploading a whole audio file to validate settings is not ok.
  Future<void> testConnection(AiAsrSettings settings, {CancelToken? cancelToken});
}

/// Temp files, ffmpeg, and transport failures turned into readable messages.
class AiAsrShared {
  static const voskSampleRate = 16000;

  /// OpenAI rejects uploads over 25MB, and every provider copes better with a
  /// small mono file, so anything bigger is re-encoded before being sent.
  static const maxUploadBytes = 20 * 1024 * 1024;

  static final _executer = FFMPEGExecuter.platform()..init();

  static String trimTrailingSlash(String url) => url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  static String tempPath(String extension) {
    final dir = Directory(FileParts.joinPath(AppDirs.APP_CACHE, 'AiSubtitle'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return FileParts.joinPath(dir.path, '${DateTime.now().microsecondsSinceEpoch}$extension');
  }

  /// 16k mono signed 16 bit little endian PCM, the only format vosk accepts.
  static Future<File> toVoskPcm(File audio) async {
    final out = tempPath('.pcm');
    final ok = await _executer.ffmpegExecute([
      '-i', audio.path, '-vn', '-ac', '1', '-ar', '$voskSampleRate', '-f', 's16le', '-acodec', 'pcm_s16le', '-y', out,
    ], noTimeout: true);

    final file = File(out);
    if (!ok || !file.existsSync() || file.lengthSync() == 0) {
      throw const AiAsrException('FFmpeg could not decode this audio file');
    }
    return file;
  }

  /// [audio] untouched when it is small enough, otherwise a compressed copy.
  static Future<File> prepareUploadFile(File audio) async {
    if (audio.lengthSync() <= maxUploadBytes) return audio;

    final out = tempPath('.mp3');
    final ok = await _executer.ffmpegExecute([
      '-i', audio.path, '-vn', '-ac', '1', '-ar', '16000', '-b:a', '32k', '-y', out,
    ], noTimeout: true);

    final file = File(out);
    if (!ok || !file.existsSync() || file.lengthSync() == 0) return audio;
    return file;
  }
  static String describeHttpFailure(int statusCode, String body) {
    final trimmed = body.length > 400 ? '${body.substring(0, 400)}…' : body;
    return switch (statusCode) {
      400 || 404 => 'The API rejected the request ($statusCode). Check the base url and the model name.\n$trimmed',
      401 || 403 => 'The API key was rejected ($statusCode).',
      413 => 'The audio file is too large for this provider.',
      429 => 'Rate limited by the provider ($statusCode), try again later.',
      >= 500 => 'The provider failed to handle the request ($statusCode).',
      _ => 'Request failed ($statusCode).\n$trimmed',
    };
  }

  static String mimeTypeFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.ogg') || lower.endsWith('.opus')) return 'audio/ogg';
    if (lower.endsWith('.m4a') || lower.endsWith('.aac')) return 'audio/aac';
    if (lower.endsWith('.flac')) return 'audio/flac';
    if (lower.endsWith('.mp4') || lower.endsWith('.m4v')) return 'audio/mp4';
    return 'audio/mpeg';
  }

  /// Pulls the text parts out of a gemini response.
  static String extractGeminiText(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final candidates = json['candidates'];
      if (candidates is List && candidates.isNotEmpty) {
        final parts = (candidates.first as Map)['content']?['parts'];
        if (parts is List) return parts.map((p) => p['text']?.toString() ?? '').join();
      }
    } catch (_) {}
    return '';
  }

  static String stripFence(String input) {
    final trimmed = input.trim();
    if (!trimmed.startsWith('```')) return trimmed;
    return trimmed.replaceAll(RegExp(r'^```[a-zA-Z]*\n?'), '').replaceAll(RegExp(r'\n?```$'), '').trim();
  }

  static int toMS(Object? value) {
    if (value is num) return (value * 1000).round();
    if (value is String) return SubtitleSrt.parseTimestamp(value) ?? 0;
    return 0;
  }
  /// Groups flat vosk words into readable cues. Vosk has no notion of a sentence,
  /// so a pause, a full stop, the length or the word count ends the current cue.
  static List<SubtitleSrtCue> wordsToCues(List<({double start, double end, String word})> words) {
    if (words.isEmpty) return const [];

    const maxGapSeconds = 0.6;
    const maxCueSeconds = 6.0;
    const maxWords = 14;
    final sentenceEnders = RegExp(r'[.!?。！？;；,，]$');

    final cues = <SubtitleSrtCue>[];
    var startMS = (words.first.start * 1000).round();
    var endMS = (words.first.end * 1000).round();
    final buffer = <String>[];

    void flush() {
      if (buffer.isEmpty) return;
      final text = buffer.join(' ').trim();
      if (text.isNotEmpty) {
        cues.add(SubtitleSrtCue(startMS: startMS, endMS: endMS > startMS ? endMS : startMS + 200, text: text));
      }
      buffer.clear();
    }

    for (final word in words) {
      final wordMS = (word.end * 1000).round();

      if (buffer.isNotEmpty) {
        final gapSeconds = word.start - endMS / 1000;
        final durationSeconds = (wordMS - startMS) / 1000;
        final endsSentence = sentenceEnders.hasMatch(buffer.last);
        if (gapSeconds > maxGapSeconds || durationSeconds > maxCueSeconds || buffer.length >= maxWords || endsSentence) {
          flush();
          startMS = (word.start * 1000).round();
        }
      }

      buffer.add(word.word);
      endMS = wordMS;
    }

    flush();
    return cues;
  }
}
