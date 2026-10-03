import 'package:namida/class/track.dart';
import 'package:namida/core/enums.dart';
import 'package:namida/core/extensions.dart';

/// 来源类型: iTunes 公开目录 / YouTube 频道 / 用户手动填写的 RSS。
enum PodcastSourceType {
  itunes,
  youtube,
  manual;

  static PodcastSourceType fromName(String? name) {
    if (name == null) return itunes;
    for (final value in PodcastSourceType.values) {
      if (value.name == name) return value;
    }
    return itunes;
  }
}

enum PodcastEpisodeKind {
  full,
  trailer,
  bonus;

  static PodcastEpisodeKind fromName(String? name) {
    if (name == null) return full;
    for (final value in PodcastEpisodeKind.values) {
      if (value.name == name) return value;
    }
    return full;
  }
}

enum PodcastDownloadState {
  none,
  downloading,
  done,
  failed;

  static PodcastDownloadState fromName(String? name) {
    if (name == null) return none;
    for (final value in PodcastDownloadState.values) {
      if (value.name == name) return value;
    }
    return none;
  }
}

/// 一档播客节目（对应一个 RSS feed）。
class PodcastShow {
  /// 稳定标识: 优先用 feedUrl, 其次用 iTunes collectionId。
  final String id;
  final String title;
  final String author;
  final String description;
  final String artworkUrl;

  /// RSS 地址。为空时只能靠 iTunes lookup 拉单集。
  final String feedUrl;
  final String websiteUrl;
  final String language;
  final List<String> genres;
  final int episodeCount;
  final PodcastSourceType sourceType;

  /// iTunes collectionId, 用于 lookup 拉取单集。
  final int? itunesId;

  const PodcastShow({
    required this.id,
    required this.title,
    this.author = '',
    this.description = '',
    this.artworkUrl = '',
    this.feedUrl = '',
    this.websiteUrl = '',
    this.language = '',
    this.genres = const [],
    this.episodeCount = 0,
    this.sourceType = PodcastSourceType.itunes,
    this.itunesId,
  });

  factory PodcastShow.fromJson(Map<String, dynamic> json) {
    final feed = json['feedUrl'] as String? ?? '';
    final itunes = json['itunesId'] as int?;
    return PodcastShow(
      id: json['id'] as String? ?? feed,
      title: json['title'] as String? ?? '',
      author: json['author'] as String? ?? '',
      description: json['description'] as String? ?? '',
      artworkUrl: json['artworkUrl'] as String? ?? '',
      feedUrl: feed,
      websiteUrl: json['websiteUrl'] as String? ?? '',
      language: json['language'] as String? ?? '',
      genres: (json['genres'] as List?)?.cast<String>() ?? const [],
      episodeCount: json['episodeCount'] as int? ?? 0,
      sourceType: PodcastSourceType.fromName(json['sourceType'] as String?),
      itunesId: itunes,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'author': author,
    'description': description,
    'artworkUrl': artworkUrl,
    'feedUrl': feedUrl,
    'websiteUrl': websiteUrl,
    'language': language,
    'genres': genres,
    'episodeCount': episodeCount,
    'sourceType': sourceType.name,
    'itunesId': itunesId,
  };

  /// 用户手动粘贴 RSS 时, 输入往往只是首页地址, 这里宽松地提取其中的 feed。
  static String? extractFeedUrlFromInput(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('http')) return trimmed;
    return null;
  }

  @override
  bool operator ==(Object other) => other is PodcastShow && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'PodcastShow($title)';
}

/// 一集播客。实现 [Playable] 以便直接进入播放队列。
class PodcastEpisode extends Playable<Map<String, dynamic>> {
  /// RSS `<guid>`，缺失时退化为 audioUrl。
  final String id;
  final String showId;
  final String showTitle;
  final String title;
  final String description;
  final String audioUrl;
  final String artworkUrl;
  final int pubDateMS;
  final int durationMS;
  final int fileSize;
  final String mimeType;
  final PodcastEpisodeKind kind;

  /// 部分站点 CDN(如 otomekoe 的 m3u8)校验 Referer, 播放/下载时随请求头带上。
  final String refererUrl;

  /// 下载后的本地绝对路径。离线播放优先用它。
  final String? downloadedPath;
  final int dateAdded;

  final QueueSourceBase? queueSource;

  const PodcastEpisode({
    required this.id,
    required this.showId,
    this.showTitle = '',
    this.title = '',
    this.description = '',
    this.audioUrl = '',
    this.artworkUrl = '',
    this.pubDateMS = 0,
    this.durationMS = 0,
    this.fileSize = 0,
    this.mimeType = '',
    this.kind = PodcastEpisodeKind.full,
    this.refererUrl = '',
    this.downloadedPath,
    this.dateAdded = 0,
    this.queueSource,
  });

  factory PodcastEpisode.fromJson(Map<String, dynamic> json) {
    return PodcastEpisode(
      id: json['id'] as String? ?? json['url'] as String? ?? '',
      showId: json['showId'] as String? ?? '',
      showTitle: json['showTitle'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      audioUrl: json['url'] as String? ?? '',
      artworkUrl: json['artworkUrl'] as String? ?? '',
      pubDateMS: json['pubDateMS'] as int? ?? 0,
      durationMS: json['durationMS'] as int? ?? 0,
      fileSize: json['fileSize'] as int? ?? 0,
      mimeType: json['mimeType'] as String? ?? '',
      kind: PodcastEpisodeKind.fromName(json['kind'] as String?),
      refererUrl: json['ref'] as String? ?? '',
      downloadedPath: json['dl'] as String?,
      dateAdded: json['dateAdded'] as int? ?? 0,
      queueSource: QueueSourcePodcast.fromJson(json['qs']),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'showId': showId,
    'showTitle': showTitle,
    'title': title,
    'description': description,
    'url': audioUrl,
    'artworkUrl': artworkUrl,
    'pubDateMS': pubDateMS,
    'durationMS': durationMS,
    'fileSize': fileSize,
    'mimeType': mimeType,
    'kind': kind.name,
    if (refererUrl.isNotEmpty) 'ref': refererUrl,
    if (downloadedPath != null) 'dl': downloadedPath,
    if (dateAdded > 0) 'dateAdded': dateAdded,
    if (queueSource != null) 'qs': queueSource?.toJson(),
  };

  PodcastEpisode copyWith({
    String? title,
    String? description,
    String? artworkUrl,
    String? downloadedPath,
    bool clearDownloadedPath = false,
    int? durationMS,
    int? fileSize,
    int? dateAdded,
    QueueSourceBase? queueSource,
  }) {
    return PodcastEpisode(
      id: id,
      showId: showId,
      showTitle: showTitle,
      title: title ?? this.title,
      description: description ?? this.description,
      audioUrl: audioUrl,
      artworkUrl: artworkUrl ?? this.artworkUrl,
      pubDateMS: pubDateMS,
      durationMS: durationMS ?? this.durationMS,
      fileSize: fileSize ?? this.fileSize,
      mimeType: mimeType,
      kind: kind,
      refererUrl: refererUrl,
      downloadedPath: clearDownloadedPath ? null : (downloadedPath ?? this.downloadedPath),
      dateAdded: dateAdded ?? this.dateAdded,
      queueSource: queueSource ?? this.queueSource,
    );
  }

  @override
  String get key => id;

  @override
  PlayableType get playableType => PlayableType.podcastEpisode;

  @override
  int get dateAddedMS => dateAdded;

  /// 播放优先级最高的本地文件路径（优先问下载任务表, 再退回自身快照）。
  /// 模型层不 import controller, 这里的"问一次"由 [audio_handler] 里的扩展完成,
  /// 本 getter 只反映对象自身携带的下载状态。
  bool get isDownloaded => downloadedPath != null && downloadedPath!.isNotEmpty;

  /// 真正拿去播的地址: 已下载走本地, 否则走网络。
  String get playableUrl {
    final local = downloadedPath;
    if (local != null && local.isNotEmpty) return local;
    return audioUrl;
  }

  bool get isPlayable => playableUrl.isNotEmpty;

  String get extension {
    if (isDownloaded && downloadedPath != null) return downloadedPath!.getExtension;
    final url = Uri.tryParse(audioUrl);
    final last = url?.pathSegments.lastOrNull ?? '';
    final dot = last.lastIndexOf('.');
    if (dot != -1 && dot > last.length - 6) return last.substring(dot + 1);
    return 'mp3';
  }

  @override
  bool operator ==(Object other) => other is PodcastEpisode && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'PodcastEpisode($title)';
}