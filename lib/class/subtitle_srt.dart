/// SRT subtitle reading & writing.
///
/// Unlike LRC, SRT has no writer anywhere in the deps, and the AI services all
/// hand back plain text, so both directions live here. Parsing is deliberately
/// lenient: API output (and user edited files) regularly miss the index line,
/// use a dot instead of a comma in the timestamp, or leave a cue with a zero
/// length range.
library;

/// One subtitle entry: [text] is shown from [startMS] until [endMS].
class SubtitleSrtCue {
  final int startMS;
  final int endMS;
  final String text;

  const SubtitleSrtCue({
    required this.startMS,
    required this.endMS,
    required this.text,
  });

  SubtitleSrtCue copyWith({int? startMS, int? endMS, String? text}) {
    return SubtitleSrtCue(
      startMS: startMS ?? this.startMS,
      endMS: endMS ?? this.endMS,
      text: text ?? this.text,
    );
  }

  Duration get start => Duration(milliseconds: startMS);
  Duration get end => Duration(milliseconds: endMS);
  Duration get duration => Duration(milliseconds: endMS - startMS);

  bool get isValid => endMS > startMS && text.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {'start': startMS, 'end': endMS, 'text': text};

  static SubtitleSrtCue fromJson(Map<String, dynamic> json) {
    final start = _asMS(json['start']);
    final end = _asMS(json['end']);
    return SubtitleSrtCue(
      startMS: start,
      endMS: end > start ? end : start + _kMinCueMS,
      text: json['text']?.toString() ?? '',
    );
  }

  static int _asMS(Object? value) {
    if (value is int) return value;
    if (value is num) return (value * 1000).round();
    if (value is String) return SubtitleSrt.parseTimestamp(value) ?? 0;
    return 0;
  }

  @override
  String toString() => 'SubtitleSrtCue(${SubtitleSrt.formatTimestamp(startMS)} --> ${SubtitleSrt.formatTimestamp(endMS)})';
}

/// cues shorter than this get stretched, otherwise a 1 frame cue is invisible.
const int _kMinCueMS = 200;

const int _kMaxCharsPerLine = 42;
const int _kMaxLinesPerCue = 2;

class SubtitleSrt {
  /// `00:00:12,500`, also accepts `.` as the decimal separator and a missing hour field.
  static final _timestampRegex = RegExp(r'(?:(\d{1,3}):)?(\d{1,2}):(\d{1,2})(?:[,.](\d{1,3}))?');

  static int? parseTimestamp(String input) {
    final match = _timestampRegex.firstMatch(input.trim());
    if (match == null) return null;
    final hours = int.tryParse(match.group(1) ?? '0') ?? 0;
    final minutes = int.tryParse(match.group(2) ?? '0') ?? 0;
    final seconds = int.tryParse(match.group(3) ?? '0') ?? 0;
    final fraction = match.group(4) ?? '';
    // `.5` means 500ms, `.05` means 50ms, `.005` means 5ms.
    final millis = fraction.isEmpty ? 0 : int.parse(fraction.padRight(3, '0'));
    return ((hours * 60 + minutes) * 60 + seconds) * 1000 + millis;
  }

  static String formatTimestamp(int ms) {
    String two(int v) => v.toString().padLeft(2, '0');
    String three(int v) => v.toString().padLeft(3, '0');
    final safe = ms < 0 ? 0 : ms;
    final hours = two(safe ~/ 3600000);
    final minutes = two((safe % 3600000) ~/ 60000);
    final seconds = two((safe % 60000) ~/ 1000);
    return '$hours:$minutes:$seconds,${three(safe % 1000)}';
  }

  /// Parses [content], dropping anything that isn't a usable cue.
  static List<SubtitleSrtCue> parse(String content) {
    if (content.isEmpty) return const [];

    final cleaned = content.replaceAll('﻿', '').replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final cues = <SubtitleSrtCue>[];

    // -- a blank line separates cues, but some writers put several timestamp
    // -- lines in a row, so the text is everything until the next timestamp.
    final blocks = cleaned.split(RegExp(r'\n{2,}'));

    for (final block in blocks) {
      final lines = block.split('\n').where((l) => l.trim().isNotEmpty).toList();
      if (lines.isEmpty) continue;

      int? startMS;
      int? endMS;
      final textLines = <String>[];

      for (final line in lines) {
        final arrowIndex = line.indexOf('-->');
        if (arrowIndex != -1) {
          final left = line.substring(0, arrowIndex);
          // -- the right side may carry `X1:... X2:...` positioning data.
          final right = line.substring(arrowIndex + 3).split(RegExp(r'\s+X\d+:')).first;
          startMS = parseTimestamp(left);
          endMS = parseTimestamp(right);
          continue;
        }

        // -- an index line (`12`) before any timestamp is not text.
        if (startMS == null && int.tryParse(line.trim()) != null) continue;
        textLines.add(line.trim());
      }

      if (startMS == null) continue;
      final text = textLines.join('\n').trim();
      if (text.isEmpty) continue;

      final safeEnd = (endMS != null && endMS > startMS) ? endMS : startMS + _kMinCueMS;
      cues.add(SubtitleSrtCue(startMS: startMS, endMS: safeEnd, text: text));
    }

    return normalize(cues);
  }

  /// Serializes [cues] into the SRT text format, numbered from 1.
  static String build(Iterable<SubtitleSrtCue> cues) {
    final buffer = StringBuffer();
    var index = 0;

    for (final cue in cues) {
      if (!cue.isValid) continue;
      index++;
      buffer
        ..writeln(index)
        ..writeln('${formatTimestamp(cue.startMS)} --> ${formatTimestamp(cue.endMS)}')
        ..writeln(cue.text)
        ..writeln();
    }

    return buffer.toString();
  }

  /// Sorts by time, drops empties, and removes overlaps (a later cue can never
  /// start before the previous one ends, otherwise players show stale text).
  static List<SubtitleSrtCue> normalize(List<SubtitleSrtCue> cues) {
    final valid = cues.where((e) => e.isValid).toList()..sort((a, b) => a.startMS.compareTo(b.startMS));
    if (valid.isEmpty) return const [];

    final result = <SubtitleSrtCue>[];
    for (final cue in valid) {
      if (result.isEmpty) {
        result.add(cue);
        continue;
      }

      final previous = result.last;
      final startMS = cue.startMS < previous.endMS ? previous.endMS : cue.startMS;
      result.add(cue.copyWith(startMS: startMS, endMS: cue.endMS > startMS ? cue.endMS : startMS + _kMinCueMS));
    }

    return result;
  }

  /// Wraps [cue]'s text so no line goes past [maxCharsPerLine]. A cue that ends
  /// up with more than [maxLines] lines is additionally split into consecutive
  /// cues that share its time range, so a long monologue is readable instead of
  /// dumping every line at once. Engines with a coarse timeline (Vosk, Whisper
  /// without word timestamps) produce exactly that kind of wall of text.
  static List<SubtitleSrtCue> splitLongCues(List<SubtitleSrtCue> cues, {int maxCharsPerLine = _kMaxCharsPerLine, int maxLines = _kMaxLinesPerCue}) {
    final result = <SubtitleSrtCue>[];

    for (final cue in cues) {
      final chunks = _wrapText(cue.text, maxCharsPerLine);
      if (chunks.isEmpty) continue;

      if (chunks.length == 1) {
        result.add(cue.copyWith(text: chunks.first));
        continue;
      }

      if (chunks.length <= maxLines) {
        result.add(cue.copyWith(text: chunks.join('\n')));
        continue;
      }

      final total = cue.endMS - cue.startMS;
      final per = (total / chunks.length).floor();
      for (var i = 0; i < chunks.length; i++) {
        final startMS = cue.startMS + per * i;
        final endMS = i == chunks.length - 1 ? cue.endMS : startMS + per;
        if (endMS <= startMS) break;
        result.add(SubtitleSrtCue(startMS: startMS, endMS: endMS, text: chunks[i]));
      }
    }

    return result;
  }

  static List<String> _wrapText(String text, int maxChars) {
    final sourceLines = text.split('\n').where((l) => l.trim().isNotEmpty).map((l) => l.trim()).toList();
    if (sourceLines.isEmpty) return const [];

    final result = <String>[];
    for (final source in sourceLines) {
      if (source.length <= maxChars) {
        result.add(source);
        continue;
      }

      // -- CJK has no spaces to break on, so chunk by character count.
      for (var i = 0; i < source.length; i += maxChars) {
        result.add(source.substring(i, (i + maxChars).clamp(0, source.length)));
      }
    }

    return result;
  }

  /// Total spoken time covered by [cues].
  static Duration totalDuration(List<SubtitleSrtCue> cues) {
    var ms = 0;
    for (final cue in cues) {
      ms += cue.endMS - cue.startMS;
    }
    return Duration(milliseconds: ms);
  }
}
