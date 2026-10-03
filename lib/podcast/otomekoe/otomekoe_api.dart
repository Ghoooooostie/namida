import 'package:rhttp/rhttp.dart';

import 'package:namida/class/http_manager.dart';
import 'package:namida/controller/logs_controller.dart';
import 'package:namida/podcast/class/podcast.dart';
import 'package:namida/podcast/otomekoe/otomekoe_parse.dart';

/// otomekoe.moe 网络层。页面解析在 [otomekoe_parse.dart](纯函数, 单独可测)。
class OtomekoeApi {
  OtomekoeApi._internal();

  static final OtomekoeApi inst = OtomekoeApi._internal();

  HttpMultiRequestManager? _http;
  Future<HttpMultiRequestManager> get _client async => _http ??= await HttpMultiRequestManager.create(2);

  Future<String?> _getHtml(String url, {String? referer}) async {
    try {
      final manager = await _client;
      return await manager.execute((requester) async {
        final response = await requester.get(url, headers: HttpHeaders.rawMap({
          'User-Agent': otomekoeBrowserUA,
          'Referer': ?referer,
        }));
        return response.body;
      });
    } catch (e, st) {
      logger.error('otomekoe request failed: $url', e: e, st: st);
      return null;
    }
  }

  /// 拉取列表页。[page] 从 1 开始, 1 即首页。
  Future<List<OtomekoePost>> fetchListing({int page = 1}) async {
    final url = page <= 1 ? otomekoeSiteRoot : '$otomekoeSiteRoot/page/$page/';
    final html = await _getHtml(url);
    if (html == null || html.isEmpty) return const [];
    return parseOtomekoeListing(html);
  }

  /// 抓帖子页里的 m3u8, 转成可直接进播放队列的 [PodcastEpisode]。
  Future<PodcastEpisode?> resolveEpisode(OtomekoePost post) async {
    final html = await _getHtml(post.url);
    if (html == null || html.isEmpty) return null;
    final detail = parseOtomekoePost(html);
    if (detail == null) return null;

    final title = detail.title.isNotEmpty ? detail.title : post.title;

    // -- 拉一次 m3u8 累加 EXTINF 算总时长(播放层把 HlsSource 当直播, 不会自己等时长)。
    var durationMS = 0;
    final playlist = await _getHtml(detail.m3u8Url, referer: post.url);
    if (playlist != null) durationMS = parseM3u8DurationMS(playlist);

    return PodcastEpisode(
      id: 'otomekoe:${post.id}',
      showId: 'otomekoe',
      showTitle: 'OtomeKoe 乙女声',
      title: detail.rjCode.isEmpty ? title : '$title [${detail.rjCode}]',
      audioUrl: detail.m3u8Url,
      artworkUrl: post.artworkUrl,
      pubDateMS: DateTime.tryParse(post.date)?.millisecondsSinceEpoch ?? 0,
      durationMS: durationMS,
      mimeType: 'application/vnd.apple.mpegurl',
      refererUrl: post.url,
    );
  }
}
