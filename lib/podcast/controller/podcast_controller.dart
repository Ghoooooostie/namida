import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:namida/controller/navigator_controller.dart';
import 'package:namida/core/extensions.dart';
import 'package:nampack/nampack.dart';

import 'package:namida/controller/indexer_controller.dart';
import 'package:namida/controller/logs_controller.dart';
import 'package:namida/controller/settings_controller.dart';
import 'package:namida/core/constants.dart';
import 'package:namida/core/enums.dart';
import 'package:namida/podcast/class/podcast.dart';
import 'package:namida/podcast/controller/podcast_api.dart';
import 'package:namida/podcast/controller/podcast_downloads_controller.dart';

/// 历史里带日期的一集播客。
class PodcastEpisodeWithDate extends PodcastEpisode {
  final int listenedAtMS;

  const PodcastEpisodeWithDate({super.dateAdded, required this.listenedAtMS, required super.id, required super.showId, super.showTitle, super.title, super.description, super.audioUrl, super.artworkUrl, super.pubDateMS, super.durationMS, super.fileSize, super.mimeType, super.kind, super.downloadedPath, super.queueSource});

  factory PodcastEpisodeWithDate.fromJson(Map<String, dynamic> json) {
    final base = PodcastEpisode.fromJson(json);
    return PodcastEpisodeWithDate(
      id: base.id,
      showId: base.showId,
      showTitle: base.showTitle,
      title: base.title,
      description: base.description,
      audioUrl: base.audioUrl,
      artworkUrl: base.artworkUrl,
      pubDateMS: base.pubDateMS,
      durationMS: base.durationMS,
      fileSize: base.fileSize,
      mimeType: base.mimeType,
      kind: base.kind,
      downloadedPath: base.downloadedPath,
      dateAdded: base.dateAdded,
      queueSource: base.queueSource,
      listenedAtMS: json['listenedAtMS'] as int? ?? base.dateAdded,
    );
  }

  @override
  PodcastEpisodeWithDate copyWith({
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
    return PodcastEpisodeWithDate(
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
      downloadedPath: clearDownloadedPath ? null : (downloadedPath ?? this.downloadedPath),
      dateAdded: dateAdded ?? this.dateAdded,
      queueSource: queueSource ?? this.queueSource,
      listenedAtMS: listenedAtMS,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'listenedAtMS': listenedAtMS,
  };
}

class PodcastController {
  PodcastController._internal();

  static final PodcastController inst = PodcastController._internal();

  bool get isInitialized => _isInitialized;
  bool _isInitialized = false;

  /// 已订阅节目。key = showId。
  final subscriptions = <String, PodcastShow>{}.obs;

  /// 每个节目的已拉取单集。key = showId。
  final episodesCache = <String, List<PodcastEpisode>>{}.obs;

  /// 正在拉取节目单的 showId，避免重复请求。
  final fetchingEpisodes = <String>[].obs;

  /// 收藏的单集（按收藏时间倒序）。
  final favourites = <PodcastEpisode>[].obs;

  /// 播放历史，最新在前。
  final history = <PodcastEpisodeWithDate>[].obs;

  /// 播放进度（毫秒）。key = episodeId。
  final positions = <String, int>{}.obs;

  /// 每天自动检查更新的间隔。
  final lastSubscriptionsRefreshMS = 0.obs;

  // ------------------------------------------------------------------
  // Discovery / Search
  // ------------------------------------------------------------------

  final isSearching = false.obs;
  final searchResults = <PodcastShow>[].obs;
  final searchEpisodesResults = <PodcastEpisode>[].obs;
  final searchError = Rxn<String>();
  final lastSearchTerm = ''.obs;

  final topShows = <PodcastShow>[].obs;
  final isTopLoading = false.obs;
  final topError = Rxn<String>();

  /// 当前目录区域，决定搜到哪国的播客。
  final currentRegion = PodcastRegion.all.first.obs;

  /// 正在拉取节目单/请求详情。
  final loadingShowIds = <String>{}.obs;

  Future<void> search(String term, {bool includeEpisodes = false}) async {
    final query = term.trim();
    if (query.isEmpty) {
      clearSearch();
      return;
    }

    isSearching.value = true;
    searchError.value = null;
    lastSearchTerm.value = query;
    final region = currentRegion.value;

    try {
      final shows = await PodcastApi.inst.searchShows(query, country: region.country, lang: region.lang);
      searchResults.assignAll(shows);

      if (includeEpisodes) {
        final episodes = await PodcastApi.inst.searchEpisodes(query, country: region.country, lang: region.lang);
        searchEpisodesResults.assignAll(episodes);
      } else {
        searchEpisodesResults.clear();
      }
    } catch (e, st) {
      logger.error('podcast search failed', e: e, st: st);
      searchError.value = '$e';
    } finally {
      isSearching.value = false;
    }
  }

  void clearSearch() {
    searchResults.clear();
    searchEpisodesResults.clear();
    searchError.value = null;
    lastSearchTerm.value = '';
  }

  Future<void> fetchTopShows(int genreId, {bool force = false}) async {
    if (isTopLoading.value) {
      // -- 正在加载时又收到新请求（典型场景：加载途中切了区域），
      // -- 直接 return 会让这次切换永远等不到数据，所以排队等当前这次结束再补一次。
      _pendingTopRefresh = true;
      _pendingTopGenreId = genreId;
      return;
    }
    if (!force && topShows.isNotEmpty && _lastTopGenreId == genreId) return;

    isTopLoading.value = true;
    topError.value = null;
    _lastTopGenreId = genreId;

    try {
      final shows = await PodcastApi.inst.topShows(genreId, country: currentRegion.value.country);
      topShows.assignAll(shows);
      // -- 空结果也要给个说法, 否则 UI 只能显示空白。
      topError.value = shows.isEmpty ? 'No charts returned for this region' : null;
    } catch (e, st) {
      logger.error('podcast top fetch failed', e: e, st: st);
      topError.value = '$e';
    } finally {
      isTopLoading.value = false;

      // -- 补做加载途中被挡下的那次请求。
      if (_pendingTopRefresh) {
        final pendingGenre = _pendingTopGenreId;
        _pendingTopRefresh = false;
        _pendingTopGenreId = null;
        if (pendingGenre != null) {
          await fetchTopShows(pendingGenre, force: true);
        }
      }
    }
  }

  int? _lastTopGenreId;
  bool _pendingTopRefresh = false;
  int? _pendingTopGenreId;

  /// 当前榜单所属分类, UI 用它做「换一批」刷新。
  int? get lastTopGenreId => _lastTopGenreId;

  void setRegion(PodcastRegion region) {
    if (currentRegion.value.country == region.country) return;
    currentRegion.value = region;

    // -- 榜单换了国家就得重拉, 否则清空后一直是空白, 只能靠用户手动 Retry。
    topShows.clear();
    // -- 保留用户当前选中的分类, 只换国家, 不粗暴地退回第一个分类。
    fetchTopShows(_lastTopGenreId ?? PodcastGenre.all.first.id, force: true);

    if (lastSearchTerm.value.isNotEmpty) search(lastSearchTerm.value);
  }

  // ------------------------------------------------------------------
  // Episodes
  // ------------------------------------------------------------------

  List<PodcastEpisode> episodesFor(String showId) => episodesCache.value[showId] ?? const [];

  bool isFavourite(PodcastEpisode ep) => favourites.value.any((e) => e.id == ep.id);

  /// 拉取节目单集，命中缓存则直接返回。
  Future<List<PodcastEpisode>> getEpisodes(PodcastShow show, {bool forceRefresh = false}) async {
    final cached = episodesCache.value[show.id];
    if (cached != null && cached.isNotEmpty && !forceRefresh) return cached;
    if (fetchingEpisodes.value.contains(show.id)) return cached ?? const [];

    fetchingEpisodes.add(show.id);
    try {
      final fetched = await PodcastApi.inst.fetchEpisodes(show);

      // -- 让已缓存的单集带上下载状态，避免 UI 显示不一致。
      final decorated = fetched.map((e) {
        final dl = _downloadedPathOf(e);
        return dl != null ? e.copyWith(downloadedPath: dl) : e;
      }).toList();

      episodesCache.value[show.id] = decorated;
      episodesCache.refresh();

      saveEpisodesCache();
      return decorated;
    } catch (e, st) {
      logger.error('podcast episodes fetch failed', e: e, st: st);
      return cached ?? const [];
    } finally {
      fetchingEpisodes.value.remove(show.id);
      fetchingEpisodes.refresh();
    }
  }

  // ------------------------------------------------------------------
  // Subscriptions
  // ------------------------------------------------------------------

  bool isSubscribed(String showId) => subscriptions.value.containsKey(showId);

  List<PodcastShow> get subscriptionsList => subscriptions.value.values.toList();

  Future<void> subscribe(PodcastShow show) async {
    if (show.id.isEmpty) return;
    subscriptions.value[show.id] = show;
    subscriptions.refresh();
    _saveSubscriptions();
    await getEpisodes(show);
  }

  void unsubscribe(String showId) {
    subscriptions.value.remove(showId);
    subscriptions.refresh();
    episodesCache.value.remove(showId);
    episodesCache.refresh();
    _saveSubscriptions();
    saveEpisodesCache();
  }

  Future<void> toggleSubscribe(PodcastShow show) async {
    if (isSubscribed(show.id)) {
      unsubscribe(show.id);
    } else {
      await subscribe(show);
    }
  }

  /// 拉取所有订阅的最新单集。
  Future<void> refreshSubscriptions({bool force = false}) async {
    if (subscriptions.value.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;

    final intervalMinutes = settings.podcast.autoRefreshSubscriptionsMinutes.value;
    final minIntervalMS = intervalMinutes <= 0 ? const Duration(minutes: 30).inMilliseconds : Duration(minutes: intervalMinutes).inMilliseconds;
    if (!force && now - lastSubscriptionsRefreshMS.value < minIntervalMS) return;
    lastSubscriptionsRefreshMS.value = now;

    for (final show in subscriptions.value.values.toList()) {
      await getEpisodes(show, forceRefresh: true);
    }
  }

  /// 新单集数量（用于订阅页上的红点）。
  int newEpisodesCountFor(String showId, {int withinDays = 7}) {
    final episodes = episodesCache.value[showId];
    if (episodes == null) return 0;
    final cutoff = DateTime.now().subtract(Duration(days: withinDays)).millisecondsSinceEpoch;
    final listened = history.value.map((e) => e.id).toSet();
    return episodes.where((e) => e.pubDateMS >= cutoff && !listened.contains(e.id)).length;
  }

  // ------------------------------------------------------------------
  // Favourites
  // ------------------------------------------------------------------

  void toggleFavourite(PodcastEpisode episode) {
    final list = favourites.value;
    final index = list.indexWhere((e) => e.id == episode.id);
    if (index >= 0) {
      list.removeAt(index);
    } else {
      list.insert(0, episode.copyWith(dateAdded: DateTime.now().millisecondsSinceEpoch));
    }
    favourites.refresh();
    _saveFavourites();
  }

  // ------------------------------------------------------------------
  // History
  // ------------------------------------------------------------------

  Future<void> addToHistory(PodcastEpisode episode) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final withDate = PodcastEpisodeWithDate(
      id: episode.id,
      showId: episode.showId,
      showTitle: episode.showTitle,
      title: episode.title,
      description: episode.description,
      audioUrl: episode.audioUrl,
      artworkUrl: episode.artworkUrl,
      pubDateMS: episode.pubDateMS,
      durationMS: episode.durationMS,
      fileSize: episode.fileSize,
      mimeType: episode.mimeType,
      kind: episode.kind,
      downloadedPath: episode.downloadedPath,
      dateAdded: now,
      listenedAtMS: now,
    );

    final histList = history.value;
    final existingIndex = histList.indexWhere((e) => e.id == episode.id);
    if (existingIndex >= 0) histList.removeAt(existingIndex);
    histList.insert(0, withDate);

    while (histList.length > 500) {
      histList.removeLast();
    }
    history.refresh();
    _saveHistory();
  }

  void clearHistory() {
    history.value.clear();
    history.refresh();
    _saveHistory();
  }

  // ------------------------------------------------------------------
  // Positions
  // ------------------------------------------------------------------

  int? getPosition(String episodeId) => positions.value[episodeId];

  Duration getResumePosition(PodcastEpisode ep) {
    final ms = positions.value[ep.id] ?? 0;
    // -- 剩余不足 30 秒视为听完, 从头开始。
    if (ms <= 0) return Duration.zero;
    final durationMS = ep.durationMS;
    if (durationMS > 0 && durationMS - ms <= 30000) return Duration.zero;
    return Duration(milliseconds: ms);
  }

  void savePosition(String episodeId, int positionMS) {
    if (positionMS <= 0) {
      positions.value.remove(episodeId);
    } else {
      positions.value[episodeId] = positionMS;
    }
    positions.refresh();
    _savePositions();
  }

  // ------------------------------------------------------------------
  // Downloads (bridged with PodcastDownloadsController)
  // ------------------------------------------------------------------

  String? _downloadedPathOf(PodcastEpisode ep) {
    final info = PodcastDownloadsController.inst.taskFor(ep.id);
    if (info != null && info.state == PodcastDownloadState.done && info.localPath != null) {
      return info.localPath;
    }
    return ep.downloadedPath;
  }

  /// 下载完成后刷新所有缓存里的这一集。
  void onEpisodeDownloaded(PodcastEpisode ep, String localPath) {
    final list = episodesCache.value[ep.showId];
    if (list != null) {
      for (var i = 0; i < list.length; i++) {
        if (list[i].id == ep.id) list[i] = list[i].copyWith(downloadedPath: localPath);
      }
      episodesCache.refresh();
      saveEpisodesCache();
    }

    final favList = favourites.value;
    final favIndex = favList.indexWhere((e) => e.id == ep.id);
    if (favIndex >= 0) {
      favList[favIndex] = favList[favIndex].copyWith(downloadedPath: localPath);
      favourites.refresh();
      _saveFavourites();
    }

    final histList = history.value;
    final histIndex = histList.indexWhere((e) => e.id == ep.id);
    if (histIndex >= 0) {
      histList[histIndex] = histList[histIndex].copyWith(downloadedPath: localPath);
      history.refresh();
      _saveHistory();
    }

    // -- 让刚下载的文件直接出现在资料库里, 而不是等用户手动刷新/重启。
    // -- 扫描目录已在 prepare 时确保覆盖下载目录, 所以这里跑一次差量刷新即可。
    unawaited(
      Indexer.inst.refreshLibraryAndCheckForDiff(allowDeletion: false, showFinishedSnackbar: false).catchError(
        (e, st) => logger.error('post podcast download library refresh', e: e, st: st),
      ),
    );
  }

  void onEpisodeDownloadRemoved(PodcastEpisode ep) {
    final list = episodesCache.value[ep.showId];
    if (list != null) {
      for (var i = 0; i < list.length; i++) {
        if (list[i].id == ep.id) list[i] = list[i].copyWith(clearDownloadedPath: true);
      }
      episodesCache.refresh();
      saveEpisodesCache();
    }

    final favList = favourites.value;
    final favIndex = favList.indexWhere((e) => e.id == ep.id);
    if (favIndex >= 0) {
      favList[favIndex] = favList[favIndex].copyWith(clearDownloadedPath: true);
      favourites.refresh();
      _saveFavourites();
    }

    final histList = history.value;
    final histIndex = histList.indexWhere((e) => e.id == ep.id);
    if (histIndex >= 0) {
      histList[histIndex] = histList[histIndex].copyWith(clearDownloadedPath: true);
      history.refresh();
      _saveHistory();
    }
  }

  // ------------------------------------------------------------------
  // Storage
  // ------------------------------------------------------------------

  Future<void> prepareAll() async {
    if (_isInitialized) return;
    try {
      await File(AppPaths.PODCAST_SUBSCRIPTIONS).create(recursive: true);
      await File(AppPaths.PODCAST_FAVOURITES).create(recursive: true);
      await File(AppPaths.PODCAST_HISTORY).create(recursive: true);
      await File(AppPaths.PODCAST_EPISODES_CACHE).create(recursive: true);
      await File(AppPaths.PODCAST_STATS_DB_INFO.file.path).create(recursive: true);
    } catch (e, st) {
      logger.error('podcast dirs prepare failed', e: e, st: st);
    }

    await Future.wait([
      _loadJson(AppPaths.PODCAST_SUBSCRIPTIONS, (json) {
        if (json is! List) return;
        for (final raw in json.whereType<Map>()) {
          final show = PodcastShow.fromJson(raw.cast<String, dynamic>());
          subscriptions.value[show.id] = show;
        }
        subscriptions.refresh();
      }),
      _loadJson(AppPaths.PODCAST_FAVOURITES, (json) {
        if (json is! List) return;
        for (final raw in json.whereType<Map>()) {
          favourites.value.add(PodcastEpisode.fromJson(raw.cast<String, dynamic>()));
        }
        favourites.refresh();
      }),
      _loadJson(AppPaths.PODCAST_HISTORY, (json) {
        if (json is! List) return;
        for (final raw in json.whereType<Map>()) {
          history.value.add(PodcastEpisodeWithDate.fromJson(raw.cast<String, dynamic>()));
        }
        history.refresh();
      }),
      _loadJson(AppPaths.PODCAST_EPISODES_CACHE, (json) {
        if (json is! Map) return;
        for (final entry in json.entries) {
          final value = entry.value;
          if (value is! List) continue;
          final list = <PodcastEpisode>[];
          for (final raw in value.whereType<Map>()) {
            list.add(PodcastEpisode.fromJson(raw.cast<String, dynamic>()));
          }
          episodesCache.value[entry.key.toString()] = list;
        }
        episodesCache.refresh();
      }),
      _loadJson(AppPaths.PODCAST_STATS_DB_INFO.file.path, (json) {
        if (json is! Map) return;
        for (final entry in json.entries) {
          if (entry.value is int) positions.value[entry.key.toString()] = entry.value as int;
        }
        positions.refresh();
      }),
    ]);

    _isInitialized = true;
  }

  Future<void> _loadJson(String path, void Function(dynamic json) onLoaded) async {
    try {
      final file = File(path);
      if (!await file.exists()) return;
      final content = await file.readAsString();
      if (content.trim().isEmpty) return;
      onLoaded(jsonDecode(content));
    } catch (e, st) {
      logger.error('podcast load failed: $path', e: e, st: st);
    }
  }

  Future<void> _writeJson(String path, Object? data) async {
    try {
      final file = File(path);
      await file.create(recursive: true);
      await file.writeAsString(jsonEncode(data), flush: true);
    } catch (e, st) {
      logger.error('podcast save failed: $path', e: e, st: st);
    }
  }

  void _saveSubscriptions() => unawaited(_writeJson(AppPaths.PODCAST_SUBSCRIPTIONS, subscriptions.value.values.map((e) => e.toJson()).toList()));

  void _saveFavourites() => unawaited(_writeJson(AppPaths.PODCAST_FAVOURITES, favourites.value.map((e) => e.toJson()).toList()));

  void _saveHistory() => unawaited(_writeJson(AppPaths.PODCAST_HISTORY, history.value.map((e) => e.toJson()).toList()));

  void _savePositions() => unawaited(_writeJson(AppPaths.PODCAST_STATS_DB_INFO.file.path, positions.value));

  void saveEpisodesCache() => unawaited(_writeJson(AppPaths.PODCAST_EPISODES_CACHE, {
        for (final entry in episodesCache.value.entries) entry.key: entry.value.map((e) => e.toJson()).toList(),
      }));

  /// 备份/还原时调用。
  Future<void> exportAll(Map<String, dynamic> out) async {
    out['subscriptions'] = subscriptions.value.values.map((e) => e.toJson()).toList();
    out['favourites'] = favourites.value.map((e) => e.toJson()).toList();
    out['history'] = history.value.map((e) => e.toJson()).toList();
    out['positions'] = positions.value;
  }
}