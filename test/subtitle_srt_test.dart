import 'package:flutter_test/flutter_test.dart';
import 'package:namida/class/subtitle_srt.dart';

void main() {
  group('timestamps', () {
    test('parses both separators and a missing hour field', () {
      expect(SubtitleSrt.parseTimestamp('00:00:12,500'), 12500);
      expect(SubtitleSrt.parseTimestamp('00:00:12.500'), 12500);
      expect(SubtitleSrt.parseTimestamp('01:02,250'), 62250);
      expect(SubtitleSrt.parseTimestamp('01:23:45,678'), 5025678);
      expect(SubtitleSrt.parseTimestamp('nonsense'), isNull);
    });

    test('fraction digits are padded by significance, not position', () {
      expect(SubtitleSrt.parseTimestamp('00:00:00,5'), 500);
      expect(SubtitleSrt.parseTimestamp('00:00:00,05'), 50);
      expect(SubtitleSrt.parseTimestamp('00:00:00,005'), 5);
    });

    test('formats back to the SRT shape', () {
      expect(SubtitleSrt.formatTimestamp(12500), '00:00:12,500');
      expect(SubtitleSrt.formatTimestamp(5025678), '01:23:45,678');
      expect(SubtitleSrt.formatTimestamp(-5), '00:00:00,000');
    });
  });

  group('parse', () {
    test('reads a normal srt body', () {
      const input = '''
1
00:00:01,000 --> 00:00:03,500
first line

2
00:00:04,000 --> 00:00:06,000
second line
''';

      final cues = SubtitleSrt.parse(input);
      expect(cues.length, 2);
      expect(cues.first.startMS, 1000);
      expect(cues.first.endMS, 3500);
      expect(cues.first.text, 'first line');
      expect(cues.last.text, 'second line');
    });

    test('keeps multi line cues together', () {
      const input = '''
1
00:00:01,000 --> 00:00:04,000
line one
line two
''';

      final cues = SubtitleSrt.parse(input);
      expect(cues.single.text, 'line one\nline two');
    });

    test('survives a missing index line, CRLF and a BOM', () {
      const input = '\uFEFF00:00:01,000 --> 00:00:02,000\r\nno index here\r\n';
      expect(SubtitleSrt.parse(input).single.text, 'no index here');
    });

    test('ignores trailing position data after the end timestamp', () {
      const input = '1\n00:00:01,000 --> 00:00:02,000 X1:100 X2:200\ntext\n';
      expect(SubtitleSrt.parse(input).single.endMS, 2000);
    });

    test('drops cues without text and stretches zero length ones', () {
      const input = '''
1
00:00:01,000 --> 00:00:02,000

2
00:00:03,000 --> 00:00:03,000
kept
''';

      final cues = SubtitleSrt.parse(input);
      expect(cues.length, 1);
      expect(cues.single.text, 'kept');
      expect(cues.single.endMS, greaterThan(cues.single.startMS));
    });
  });
  group('normalize', () {
    test('sorts by time and removes overlaps', () {
      final cues = SubtitleSrt.normalize([
        const SubtitleSrtCue(startMS: 5000, endMS: 6000, text: 'second'),
        const SubtitleSrtCue(startMS: 1000, endMS: 4000, text: 'first'),
        const SubtitleSrtCue(startMS: 2000, endMS: 5500, text: 'overlapping'),
      ]);

      expect(cues.map((e) => e.text).toList(), ['first', 'overlapping', 'second']);
      // -- a later cue can never start before the previous one ended.
      expect(cues[1].startMS, greaterThanOrEqualTo(cues[0].endMS));
      expect(cues[2].startMS, greaterThanOrEqualTo(cues[1].endMS));
    });
  });

  group('build', () {
    test('round trips through parse', () {
      final original = [
        const SubtitleSrtCue(startMS: 0, endMS: 1200, text: 'one'),
        const SubtitleSrtCue(startMS: 1500, endMS: 3000, text: 'two\nlines'),
      ];

      final parsed = SubtitleSrt.parse(SubtitleSrt.build(original));
      expect(parsed.length, 2);
      expect(parsed.first.startMS, 0);
      expect(parsed.last.text, 'two\nlines');
    });

    test('numbers from 1 and skips invalid cues', () {
      final text = SubtitleSrt.build([
        const SubtitleSrtCue(startMS: 0, endMS: 1000, text: 'valid'),
        const SubtitleSrtCue(startMS: 2000, endMS: 2000, text: 'invalid'),
      ]);

      expect(text, startsWith('1\n00:00:00,000 --> 00:00:01,000\nvalid'));
      expect(text, isNot(contains('invalid')));
    });
  });

  group('splitLongCues', () {
    test('wraps a long line and slices its time range', () {
      final long = 'a' * 100;
      final result = SubtitleSrt.splitLongCues([
        SubtitleSrtCue(startMS: 0, endMS: 6000, text: long),
      ]);

      expect(result.length, greaterThan(1));
      for (final cue in result) {
        expect(cue.text.length, lessThanOrEqualTo(42));
      }
      // -- consecutive, and still inside the original range.
      expect(result.first.startMS, 0);
      expect(result.last.endMS, 6000);
      for (var i = 1; i < result.length; i++) {
        expect(result[i].startMS, greaterThanOrEqualTo(result[i - 1].startMS));
      }
    });

    test('leaves a short cue untouched', () {
      final result = SubtitleSrt.splitLongCues([
        const SubtitleSrtCue(startMS: 0, endMS: 1000, text: 'short'),
      ]);

      expect(result.single.text, 'short');
    });
  });
}
