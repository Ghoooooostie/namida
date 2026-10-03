import 'dart:convert';

import 'package:rhttp/rhttp.dart';
import 'package:namida/controller/navigator_controller.dart';
import 'package:nampack/nampack.dart';

import 'package:namida/class/http_manager.dart';
import 'package:namida/controller/logs_controller.dart';
import 'package:namida/core/constants.dart';
import 'package:namida/core/extensions.dart';
import 'package:namida/podcast/class/podcast.dart';

/// Apple Podcasts 目录分类。用于「发现」页的分类浏览。
class PodcastGenre {
  final int id;
  final String name;
  final String icon;

  const PodcastGenre(this.id, this.name, this.icon);

  static const all = [
    PodcastGenre(1304, 'Education', 'school'),
    PodcastGenre(1315, 'Society & Culture', 'forum'),
    PodcastGenre(1301, 'Arts', 'palette'),
    PodcastGenre(1308, 'Health & Fitness', 'heart'),
    PodcastGenre(1324, 'Business', 'work'),
    PodcastGenre(1302, 'Business', 'work'),
    PodcastGenre(1317, 'Technology', 'memory'),
    PodcastGenre(1314, 'Science', 'science'),
    PodcastGenre(1307, 'History', 'history_edu'),
    PodcastGenre(1305, 'Fiction', 'auto_stories'),
    PodcastGenre(1303, 'Comedy', 'mood'),
    PodcastGenre(1319, 'News', 'newspaper'),
    PodcastGenre(1521, 'TV & Film', 'movie'),
    PodcastGenre(1518, 'True Crime', 'gavel'),
    PodcastGenre(1311, 'Music', 'music_note'),
    PodcastGenre(1313, 'Spirituality', 'self_improvement'),
    PodcastGenre(1318, 'Science & Tech', 'science'),
    PodcastGenre(1309, 'Kids & Family', 'child_care'),
  ];
}

/// 目录区域。日语/英语学习类播客需要切到对应区域才能搜到。
class PodcastRegion {
  final String country;
  final String lang;
  final String name;

  const PodcastRegion(this.country, this.lang, this.name);

  static const all = [
    PodcastRegion('US', 'en_us', 'English'),
    PodcastRegion('JP', 'ja_jp', '日本語'),
    PodcastRegion('CN', 'zh_cn', '中文'),
    PodcastRegion('GB', 'en_gb', 'UK'),
    PodcastRegion('CA', 'en_ca', 'Canada'),
    PodcastRegion('AU', 'en_au', 'Australia'),
    PodcastRegion('DE', 'de_de', 'Deutsch'),
    PodcastRegion('FR', 'fr_fr', 'Français'),
    PodcastRegion('ES', 'es_es', 'Español'),
    PodcastRegion('KR', 'ko_kr', '한국어'),
  ];
}

class PodcastApi {
  PodcastApi._internal();

  static final PodcastApi inst = PodcastApi._internal();

  HttpMultiRequestManager? _http;
  Future<HttpMultiRequestManager> get _client async => _http ??= await HttpMultiRequestManager.create(3);

  String get userAgent => 'Namida/${NamidaDeviceInfo.packageInfo?.version ?? 'app'}';

  static String _query(Map<String, String> params) {
    return params.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
  }

  // ------------------------------------------------------------------
  // Search
  // ------------------------------------------------------------------

  Future<List<PodcastShow>> searchShows(
    String term, {
    String country = 'US',
    String lang = 'en_us',
    int limit = 40,
  }) async {
    final url = 'https://itunes.apple.com/search?${_query({
          'media': 'podcast',
          'term': term,
          'limit': limit.toString(),
          'country': country,
          'lang': lang,
        })}';

    final json = await _getJson(url);
    final results = json?['results'] as List?;
    if (results == null) return const [];
    return results.map((e) => _showFromLookup(e as Map)).where((e) => e.id.isNotEmpty).toList();
  }

  /// 单集搜索, 用于「在全部播客里搜某一集」。
  Future<List<PodcastEpisode>> searchEpisodes(
    String term, {
    String country = 'US',
    String lang = 'en_us',
    int limit = 30,
  }) async {
    final url = 'https://itunes.apple.com/search?${_query({
          'media': 'podcastEpisode',
          'term': term,
          'limit': limit.toString(),
          'country': country,
          'lang': lang,
        })}';

    final json = await _getJson(url);
    final results = json?['results'] as List?;
    if (results == null) return const [];
    return results.whereType<Map>().map((e) => _episodeFromLookup(e, podcastName: e['collectionName'] as String?)).toList();
  }

  // ------------------------------------------------------------------
  // Top / Charts
  // ------------------------------------------------------------------

  Future<List<PodcastShow>> topShows(
    int genreId, {
    String country = 'US',
    int limit = 30,
  }) async {
    final url = 'https://itunes.apple.com/$country/rss/toppodcasts/limit=$limit/genre=$genreId/json';
    final json = await _getJson(url);
    final feed = json?['feed'];
    if (feed is! Map) return const [];

    // -- 榜单是个 RSS-JSON，条目在 `feed.entry`，且每个字段都包成 `{"label": ...}`。
    // -- 注意不是 `feed.results`（那会让列表恒空，表现为永远转圈）。
    final entries = feed['entry'];
    if (entries is! List) return const [];

    return entries.whereType<Map>().map((e) {
      final name = _labelOf(e['im:name']) ?? '';
      final author = _labelOf(e['im:artist']) ?? '';
      final pageUrl = _labelOf(e['id']) ?? '';

      // -- 榜单封面给的是 100x100，改尺寸即可拿到大图。
      var artworkUrl = '';
      final images = e['im:image'];
      if (images is List && images.isNotEmpty) {
        artworkUrl = _labelOf(images.first) ?? '';
        artworkUrl = artworkUrl.replaceAll(RegExp(r'\d+x\d+bb'), '600x600bb');
      }

      // -- 详情页要靠 collectionId 去 lookup 单集，榜单只给了页面地址，从里面抠出来。
      final itunesId = int.tryParse(_itunesIdInUrl.firstMatch(pageUrl)?.group(1) ?? '');

      return PodcastShow(
        id: itunesId?.toString() ?? pageUrl,
        title: name,
        author: author,
        description: _labelOf(e['summary']) ?? '',
        artworkUrl: artworkUrl,
        websiteUrl: pageUrl,
        feedUrl: '',
        genres: const [],
        sourceType: PodcastSourceType.itunes,
        itunesId: itunesId,
      );
    }).where((e) => e.id.isNotEmpty && e.title.isNotEmpty).toList();
  }

  /// RSS-JSON 里 `{"label": "..."}` 结构的取值。
  static String? _labelOf(dynamic value) {
    if (value is Map) return value['label'] as String?;
    if (value is String) return value;
    return null;
  }

  static final _itunesIdInUrl = RegExp(r'/id(\d+)', caseSensitive: false);

  // ------------------------------------------------------------------
  // Episodes
  // ------------------------------------------------------------------

  /// 拉取节目单集。优先 RSS（能拿到封面/时长/描述），失败则退回 iTunes lookup。
  Future<List<PodcastEpisode>> fetchEpisodes(PodcastShow show, {int limit = 100}) async {
    final feedUrl = show.feedUrl;
    if (feedUrl.isNotEmpty) {
      try {
        final xml = await _getText(feedUrl);
        if (xml != null && xml.isNotEmpty) {
          final parsed = PodcastFeedParser.parseFeed(xml, showId: show.id, showTitle: show.title, showArtwork: show.artworkUrl);
          if (parsed.isNotEmpty) return parsed.take(limit).toList();
        }
      } catch (e, st) {
        logger.error('podcast feed fetch failed', e: e, st: st);
      }
    }

    final itunesId = show.itunesId;
    if (itunesId == null) return const [];
    return lookupEpisodes(itunesId, limit: limit);
  }

  Future<List<PodcastEpisode>> lookupEpisodes(int collectionId, {int limit = 100}) async {
    final url = 'https://itunes.apple.com/lookup?${_query({
          'id': collectionId.toString(),
          'entity': 'podcastEpisode',
          'limit': limit.toString(),
        })}';

    final json = await _getJson(url);
    final results = json?['results'] as List?;
    if (results == null) return const [];

    String showTitle = '';
    String showArtwork = '';
    final episodes = <PodcastEpisode>[];
    for (final raw in results.whereType<Map>()) {
      final wrapper = raw['wrapperType'] as String?;
      if (wrapper != 'podcastEpisode') {
        // -- 节目本体（wrapperType 为 'track'）常排在第一条，用来补节目名与封面。
        if (showTitle.isEmpty) showTitle = raw['collectionName'] as String? ?? '';
        if (showArtwork.isEmpty) showArtwork = (raw['artworkUrl600'] as String? ?? raw['artworkUrl100'] as String? ?? '').replaceFirst('100x100', '400x400');
        continue;
      }
      episodes.add(_episodeFromLookup(raw, podcastName: showTitle.isEmpty ? raw['collectionName'] as String? : showTitle, showArtwork: showArtwork));
    }
    return episodes;
  }

  /// 手动添加 RSS 时, 用 feed 本身补全节目信息。
  Future<PodcastShow?> resolveShowFromFeed(String feedUrl) async {
    final xml = await _getText(feedUrl);
    if (xml == null || xml.isEmpty) return null;
    final meta = PodcastFeedParser.parseFeedMeta(xml);
    if (meta == null) return null;
    return PodcastShow(
      id: feedUrl,
      title: meta.title,
      author: meta.author,
      description: meta.description,
      artworkUrl: meta.artworkUrl,
      feedUrl: feedUrl,
      websiteUrl: meta.websiteUrl,
      language: meta.language,
      genres: meta.genres,
      sourceType: PodcastSourceType.manual,
    );
  }

  // ------------------------------------------------------------------
  // HTTP
  // ------------------------------------------------------------------

  Future<Map<String, dynamic>?> _getJson(String url) async {
    final text = await _getText(url);
    if (text == null || text.isEmpty) return null;
    try {
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e, st) {
      logger.error('podcast json decode failed: $url', e: e, st: st);
      return null;
    }
  }

  Future<String?> _getText(String url) async {
    try {
      final manager = await _client;
      return await manager.execute((requester) async {
        final response = await requester.get(url, headers: HttpHeaders.rawMap({
          'User-Agent': userAgent,
        }));
        return response.body;
      });
    } catch (e, st) {
      logger.error('podcast request failed: $url', e: e, st: st);
      return null;
    }
  }

  // ------------------------------------------------------------------
  // iTunes JSON mapping
  // ------------------------------------------------------------------

  PodcastShow _showFromLookup(Map json) {
    final collectionId = json['collectionId'] as int?;
    final feedUrl = json['feedUrl'] as String? ?? '';
    return PodcastShow(
      id: feedUrl.isNotEmpty ? feedUrl : (collectionId?.toString() ?? ''),
      title: json['collectionName'] as String? ?? json['trackName'] as String? ?? '',
      author: json['artistName'] as String? ?? '',
      description: json['description'] as String? ?? '',
      artworkUrl: (json['artworkUrl600'] as String? ?? json['artworkUrl100'] as String? ?? '').replaceFirst('100x100', '400x400'),
      feedUrl: feedUrl,
      websiteUrl: json['collectionViewUrl'] as String? ?? '',
      language: json['country'] as String? ?? '',
      genres: (json['genres'] as List?)?.cast<String>() ?? const [],
      episodeCount: json['trackCount'] as int? ?? 0,
      itunesId: collectionId,
    );
  }

  PodcastEpisode _episodeFromLookup(Map json, {String? podcastName, String showArtwork = ''}) {
    final url = json['episodeUrl'] as String? ?? '';
    final trackId = json['trackId'] as int?;
    final showId = json['collectionId']?.toString() ?? podcastName ?? '';
    return PodcastEpisode(
      id: trackId?.toString() ?? url,
      showId: showId,
      showTitle: podcastName ?? '',
      title: json['trackName'] as String? ?? '',
      description: json['shortDescription'] as String? ?? json['description'] as String? ?? '',
      audioUrl: url,
      artworkUrl: (json['artworkUrl600'] as String? ?? showArtwork).replaceFirst('100x100', '400x400'),
      pubDateMS: _parseIsoDateMS(json['releaseDate'] as String?),
      durationMS: json['trackTimeMillis'] as int? ?? 0,
      mimeType: 'audio/mp4',
      kind: PodcastEpisodeKind.full,
    );
  }

  /// iTunes 返回的是 ISO-8601 (`2024-01-02T03:04:05Z`)，交给 `DateTime.parse` 即可。
  static int _parseIsoDateMS(String? raw) {
    if (raw == null || raw.isEmpty) return 0;
    return DateTime.tryParse(raw)?.millisecondsSinceEpoch ?? 0;
  }
}

// ==========================================================================
// RSS parsing
// ==========================================================================

class PodcastFeedMeta {
  final String title;
  final String author;
  final String description;
  final String artworkUrl;
  final String websiteUrl;
  final String language;
  final List<String> genres;

  const PodcastFeedMeta({
    this.title = '',
    this.author = '',
    this.description = '',
    this.artworkUrl = '',
    this.websiteUrl = '',
    this.language = '',
    this.genres = const [],
  });
}

class PodcastFeedParser {
  PodcastFeedParser._internal();

  static final PodcastFeedParser inst = PodcastFeedParser._internal();

  static final _itemRegex = RegExp(r'<item[^>]*>([\s\S]*?)</item>', caseSensitive: false);
  static final _cdataRegex = RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>');

  static String _unwrap(String value) {
    var v = value.trim();
    final cdata = _cdataRegex.firstMatch(v);
    if (cdata != null) v = cdata.group(1) ?? '';
    v = v.replaceAll(RegExp(r'<[^>]*>'), '');
    return _decodeEntities(v).trim();
  }

  static String _decodeEntities(String input) {
    return input
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&');
  }

  static String? _tag(String block, String tag) {
    final regex = RegExp('<$tag(?:\\s[^>]*)?>([\\s\\S]*?)</$tag>', caseSensitive: false);
    return _unwrap(regex.firstMatch(block)?.group(1) ?? '');
  }

  /// 从 `href="..."` 形式的属性里取值 (itunes:image 等)。
  static String? _attr(String block, String tag, String attr) {
    final regex = RegExp('<$tag\\b[^>]*\\b$attr\\s*=\\s*"([^"]*)"', caseSensitive: false);
    return _decodeEntities(regex.firstMatch(block)?.group(1) ?? '').trim();
  }

  static PodcastFeedMeta? parseFeedMeta(String xml) {
    final channelMatch = RegExp(r'<channel[^>]*>([\s\S]*)</channel>', caseSensitive: false).firstMatch(xml);
    final channel = channelMatch?.group(1) ?? xml;
    if (channel.isEmpty) return null;

    return PodcastFeedMeta(
      title: _tag(channel, 'title') ?? '',
      author: _attr(channel, 'itunes:author', 'href') ?? _tag(channel, 'itunes:author') ?? _tag(channel, 'managingEditor') ?? '',
      description: _tag(channel, 'description') ?? _tag(channel, 'itunes:summary') ?? '',
      artworkUrl: _attr(channel, 'itunes:image', 'href') ?? _tag(channel, 'url') ?? '',
      websiteUrl: _attr(channel, 'link', 'href') ?? _tag(channel, 'link') ?? '',
      language: _tag(channel, 'language') ?? '',
      genres: _tag(channel, 'itunes:category') == null ? const [] : [_tag(channel, 'itunes:category')!],
    );
  }

  static List<PodcastEpisode> parseFeed(
    String xml, {
    required String showId,
    required String showTitle,
    required String showArtwork,
  }) {
    final meta = parseFeedMeta(xml);
    final episodes = <PodcastEpisode>[];

    for (final match in _itemRegex.allMatches(xml)) {
      final item = match.group(1) ?? '';
      if (item.isEmpty) continue;

      final enclosureUrl = _attr(item, 'enclosure', 'url') ?? '';
      if (enclosureUrl.isEmpty) continue;

      final rawGuid = _tag(item, 'guid') ?? '';
      final title = _tag(item, 'title') ?? '';
      final pubDate = _tag(item, 'pubDate') ?? '';
      final duration = _tag(item, 'itunes:duration') ?? '';
      final type = _tag(item, 'itunes:episodeType') ?? '';
      final itemArtwork = _attr(item, 'itunes:image', 'href') ?? _attr(item, 'image', 'href') ?? '';

      episodes.add(PodcastEpisode(
        id: rawGuid.isNotEmpty ? rawGuid : enclosureUrl,
        showId: showId,
        showTitle: meta?.title.isNotEmpty == true ? meta!.title : showTitle,
        title: title.isEmpty ? enclosureUrl : title,
        description: _tag(item, 'content:encoded') ?? _tag(item, 'description') ?? '',
        audioUrl: enclosureUrl,
        artworkUrl: itemArtwork.isNotEmpty ? itemArtwork : (meta?.artworkUrl.isNotEmpty == true ? meta!.artworkUrl : showArtwork),
        pubDateMS: parseRfc2822Date(pubDate),
        durationMS: parseDurationSeconds(duration),
        fileSize: int.tryParse(_attr(item, 'enclosure', 'length') ?? '') ?? 0,
        mimeType: _attr(item, 'enclosure', 'type') ?? '',
        kind: switch (type.toLowerCase()) {
          'trailer' => PodcastEpisodeKind.trailer,
          'bonus' => PodcastEpisodeKind.bonus,
          _ => PodcastEpisodeKind.full,
        },
      ));
    }

    episodes.sort((a, b) => b.pubDateMS.compareTo(a.pubDateMS));
    return episodes;
  }

  /// 解析 `HH:MM:SS` / `MM:SS` / 纯秒数。
  static int parseDurationSeconds(String? raw) {
    if (raw == null) return 0;
    final value = raw.trim();
    if (value.isEmpty) return 0;

    if (!value.contains(':')) return int.tryParse(value) ?? 0;

    final parts = value.split(':').map((e) => int.tryParse(e.trim()) ?? 0).toList();
    var seconds = 0;
    for (final part in parts) {
      seconds = seconds * 60 + part;
    }
    return seconds * 1000;
  }

  static final _months = {
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };

  /// `DateTime.parse` 不支持 RFC-2822，这里自己拆。
  static final _rfc2822Regex = RegExp(
    r'(\d{1,2})\s+(\w{3})\w*\s+(\d{2,4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([+-]\d{4})?',
    caseSensitive: false,
  );

  static int parseRfc2822Date(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 0;
    final m = _rfc2822Regex.firstMatch(raw.trim());
    if (m == null) return 0;

    final day = int.tryParse(m.group(1) ?? '') ?? 0;
    final month = _months[m.group(2)?.toLowerCase() ?? ''] ?? 0;
    var year = int.tryParse(m.group(3) ?? '') ?? 0;
    if (year < 100) year += year < 70 ? 2000 : 1900;

    final hour = int.tryParse(m.group(4) ?? '') ?? 0;
    final minute = int.tryParse(m.group(5) ?? '') ?? 0;
    final second = int.tryParse(m.group(6) ?? '') ?? 0;

    if (day == 0 || month == 0) return 0;

    var ms = DateTime.utc(year, month, day, hour, minute, second).millisecondsSinceEpoch;

    // -- 折算时区偏移，如 "+0900" 表示本地时间比 UTC 快 9 小时。
    final offset = m.group(7);
    if (offset != null && (offset.startsWith('+') || offset.startsWith('-'))) {
      final sign = offset.startsWith('-') ? -1 : 1;
      final offsetHours = int.tryParse(offset.substring(1, 3)) ?? 0;
      final offsetMinutes = int.tryParse(offset.substring(3, 5)) ?? 0;
      ms -= sign * (offsetHours * 3600 + offsetMinutes * 60) * 1000;
    }

    return ms;
  }
}