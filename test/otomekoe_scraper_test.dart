import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:namida/podcast/otomekoe/otomekoe_parse.dart';

void main() {
  group('parseOtomekoeListing', () {
    final html = File('test/fixtures/otomekoe_listing.html').readAsStringSync();
    final posts = parseOtomekoeListing(html);

    test('extracts all entries on the page', () {
      expect(posts.length, 14);
    });

    test('first entry matches the fixture', () {
      final first = posts.first;
      expect(first.id, 10944);
      expect(first.url, 'https://otomekoe.moe/10944/');
      expect(first.title, '特別競売調教室');
      expect(first.date, '2026-07-24');
      expect(first.categories, contains('NSFW'));
      expect(first.artworkUrl, contains('RJ01267545'));
    });

    test('ids are unique', () {
      final ids = posts.map((e) => e.id).toList();
      expect(ids.toSet().length, ids.length);
    });
  });

  group('parseOtomekoePost', () {
    final html = File('test/fixtures/otomekoe_post.html').readAsStringSync();
    final detail = parseOtomekoePost(html);

    test('finds the embedded m3u8', () {
      expect(detail, isNotNull);
      expect(detail!.m3u8Url, 'https://v.weeab0o.xyz/RJ01049217.m3u8');
    });

    test('extracts title and RJ code', () {
      expect(detail!.title, contains('禁断過度愛'));
      expect(detail.rjCode, 'RJ01049217');
    });
  });

  group('parseOtomekoePost fallback', () {
    test('grabs a bare m3u8 URL when no <source> tag exists', () {
      const html = "<script>var audioSrc = 'https://cdn.example.com/a/b.m3u8';</script>";
      final detail = parseOtomekoePost(html);
      expect(detail?.m3u8Url, 'https://cdn.example.com/a/b.m3u8');
    });

    test('returns null when page has no stream', () {
      expect(parseOtomekoePost('<html><body>nothing</body></html>'), isNull);
    });
  });

  group('parseM3u8DurationMS', () {
    test('sums #EXTINF entries', () {
      const playlist = '''
#EXTM3U
#EXT-X-VERSION:3
#EXTINF:10.005333,
a.ts
#EXTINF:9.994667,
b.ts
#EXT-X-ENDLIST''';
      expect(parseM3u8DurationMS(playlist), 20000);
    });

    test('empty playlist -> 0', () {
      expect(parseM3u8DurationMS('#EXTM3U'), 0);
    });
  });
}
