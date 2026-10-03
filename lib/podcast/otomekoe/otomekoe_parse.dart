/// otomekoe.moe 页面解析(纯函数, 零依赖, 可脱离 Flutter 单测)。
library;

/// 列表页里的一条帖子。
class OtomekoePost {
  final int id;
  final String title;
  final String url;
  final String date;
  final List<String> categories;
  final String artworkUrl;

  const OtomekoePost({
    required this.id,
    required this.title,
    required this.url,
    this.date = '',
    this.categories = const [],
    this.artworkUrl = '',
  });
}

/// 帖子页解析结果。
class OtomekoePostDetail {
  final String title;
  final String m3u8Url;
  final String rjCode;

  const OtomekoePostDetail({
    required this.title,
    required this.m3u8Url,
    this.rjCode = '',
  });
}

const otomekoeSiteRoot = 'https://otomekoe.moe';

/// CDN(v.weeab0o.xyz 等)只放行浏览器 UA + otomekoe.moe 源 referer,
/// curl/mpv/LAVF/Namida 等 UA 一律 403, 播放和下载都必须带这两个头。
const otomekoeBrowserUA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
const otomekoeReferer = '$otomekoeSiteRoot/';

final _postBlockRegex = RegExp(r'class="site-archive-post[\s\S]*?(?=class="site-archive-post|</main>|</ul>|$)');
final _postIdRegex = RegExp(r'\bpost-(\d+)\b');
final _titleRegex = RegExp(r'<h2 class="entry-title"><a href="([^"]+)">([\s\S]*?)</a></h2>', caseSensitive: false);
final _dateRegex = RegExp(r'<time datetime="([^"]+)"');
final _categoryRegex = RegExp(r'<a[^>]*rel="category tag"[^>]*>([^<]+)</a>');
final _lazyImageRegex = RegExp(r'data-src="(https?://[^"]+?\.(?:jpg|jpeg|png|webp)[^"]*)"', caseSensitive: false);

final _sourceTagRegex = RegExp(r'<source\s+src="(https?://[^"]+\.m3u8[^"]*)"', caseSensitive: false);
final _anyM3u8Regex = RegExp(r'''https?://[^\s"'<>]+\.m3u8[^\s"'<>]*''', caseSensitive: false);
final _rjCodeRegex = RegExp(r"rjcode='(RJ\d+)'", caseSensitive: false);
final _pageTitleRegex = RegExp(r'<h1 class="page-title"[^>]*>([\s\S]*?)</h1>', caseSensitive: false);

final _tagRegex = RegExp(r'<[^>]*>');

String _stripTags(String value) {
  return value
      .replaceAll(_tagRegex, '')
      .replaceAll('&amp;', '&')
      .replaceAll('&#8211;', '–')
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'")
      .trim();
}

List<OtomekoePost> parseOtomekoeListing(String html) {
  final posts = <OtomekoePost>[];
  for (final blockMatch in _postBlockRegex.allMatches(html)) {
    final block = blockMatch.group(0) ?? '';
    final id = int.tryParse(_postIdRegex.firstMatch(block)?.group(1) ?? '');
    final link = _titleRegex.firstMatch(block);
    final url = link?.group(1) ?? '';
    if (id == null || url.isEmpty) continue;

    posts.add(OtomekoePost(
      id: id,
      url: url,
      title: _stripTags(link?.group(2) ?? ''),
      date: _dateRegex.firstMatch(block)?.group(1) ?? '',
      categories: _categoryRegex.allMatches(block).map((e) => e.group(1) ?? '').where((e) => e.isNotEmpty).toList(),
      artworkUrl: _lazyImageRegex.firstMatch(block)?.group(1) ?? '',
    ));
  }
  return posts;
}

OtomekoePostDetail? parseOtomekoePost(String html) {
  final m3u8 = _sourceTagRegex.firstMatch(html)?.group(1) ?? _anyM3u8Regex.firstMatch(html)?.group(0);
  if (m3u8 == null) return null;
  return OtomekoePostDetail(
    title: _stripTags(_pageTitleRegex.firstMatch(html)?.group(1) ?? ''),
    m3u8Url: m3u8,
    rjCode: _rjCodeRegex.firstMatch(html)?.group(1) ?? '',
  );
}

final _extinfRegex = RegExp(r'#EXTINF:([\d.]+)');

/// 累加 VOD 播放列表里的 `#EXTINF` 得到总时长。
/// mpv 把 `HlsSource` 一律当直播处理(不等时长), 所以时长必须我们自己算。
int parseM3u8DurationMS(String playlist) {
  double seconds = 0;
  for (final match in _extinfRegex.allMatches(playlist)) {
    seconds += double.tryParse(match.group(1) ?? '') ?? 0;
  }
  return (seconds * 1000).round();
}
