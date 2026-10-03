// STUB layer for the removed YouTube feature.
//
// The YouTube section was stripped out of this build. These types are kept
// ONLY so the rest of namida still type-checks. Every method call on a stub
// instance is forwarded to [noSuchMethod], which returns null -- the feature
// is non-functional at runtime.

export 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:history_manager/history_manager.dart';
import 'package:namico_subscription_manager/_stubs_base.dart';
import 'package:playlist_manager/playlist_manager.dart';
import 'package:nampack/nampack.dart';
import 'package:youtipie/_stubs_base.dart';

import 'package:namida/class/track.dart';
import 'package:namida/class/video.dart';
import 'package:namida/class/route.dart';
import 'package:namida/core/enums.dart';
export 'package:flutter/widgets.dart' hide ReorderableDelayedDragStartListener, ReorderCallback, SliverReorderableList;
export 'package:youtipie/_stubs_base.dart';
export 'package:namico_subscription_manager/_stubs_base.dart';

/// Placeholder observables for stub members that are consumed as `Rx`
/// (eg. `ObxO(rx: YoutubeController.inst.activeRawDownloadsCount)`), where a
/// plain `null` throws a type error instead of being ignored.
/// Deliberately declared here, outside any `AUTO` block, so that
/// [gen_stub_ext.ps1] does not regenerate them back to `null`.
final _stubRawDownloadsCountRx = 0.obs;

/// 播放器界面使用的 YouTube 音轨 DTO。
class AudioTrack {
  final String? id;
  final String? langCode;
  final String? displayName;
  final bool? isDefault;

  const AudioTrack({this.id, this.langCode, this.displayName, this.isDefault});
}

// ---------------------------------------------------------------------------
// YoutubeID & related Playable pieces
// ---------------------------------------------------------------------------

class YoutubeID extends Playable<Map<String, dynamic>> with ItemWithDate, PlaylistItemWithDate {
  final String id;
  final String? channelUrl;
  final QueueSourceBase? queueSource;
  final TrackSource? sourceNull;
  final PlaylistID? playlistID;
  final YTWatch? watchNull;

  const YoutubeID({
    required this.id,
    this.channelUrl,
    this.queueSource,
    TrackSource? source,
    this.playlistID,
    this.watchNull,
  }) : sourceNull = source;

  static const YoutubeID fake = YoutubeID(id: '');

  @override
  String get key => id;

  @override
  PlayableType get playableType => PlayableType.ytVideo;

  YTWatch get watch => watchNull ?? const YTWatch(dateMSNull: 0, isYTMusic: false);

  int get dateAddedMS => watch.dateMS;

  /// 从播放器队列或同步数据恢复视频标识。
  factory YoutubeID.fromJson(Map<String, dynamic> json) {
    final sourceName = json['source'] as String?;
    TrackSource? source;
    if (sourceName != null) {
      for (final value in TrackSource.values) {
        if (value.name == sourceName) {
          source = value;
          break;
        }
      }
    }
    return YoutubeID(
      id: json['id'] as String? ?? '',
      channelUrl: json['channelUrl'] as String?,
      queueSource: QueueSource.fromJson(json['qs']) ?? QueueSourceYoutubeID.fromJson(json['qs']),
      source: source,
      playlistID: json['playlistID'] == null ? null : PlaylistID(id: json['playlistID'] as String),
      watchNull: json['watch'] is Map ? YTWatch.fromJson((json['watch'] as Map).cast<String, dynamic>()) : null,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    if (channelUrl != null) 'channelUrl': channelUrl,
    if (queueSource != null) 'qs': queueSource?.toJson(),
    if (sourceNull != null) 'source': sourceNull?.name,
    if (playlistID != null) 'playlistID': playlistID?.id,
    if (watchNull != null) 'watch': watchNull?.toJson(),
  };

  // 在已移除 YouTube 功能的构建中返回空缩略图。
  Future<File?> getThumbnail({required bool temp}) => Future<File?>.value();

  @override
  bool operator ==(Object other) => other is YoutubeID && id == other.id && playlistID == other.playlistID && watchNull == other.watchNull;

  @override
  int get hashCode => Object.hash(id, playlistID, watchNull);
}

extension YoutubeIdStringStubUtils on String {
  // 空标识是当前占位视频的唯一来源。
  bool get isDummyVideoId => isEmpty;
}

class QueueChipHeaderRow {
  const QueueChipHeaderRow();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  // -- deliberately outside the AUTO block, and in the exact `static dynamic get x` form
  // -- [gen_stub_ext.ps1] recognizes: it's used in layout math (`+ QueueChipHeaderRow.minHeight`),
  // -- where a `null` throws NoSuchMethodError on `operator +`.
  static dynamic get minHeight => 32.0;
}

class YTQueueChipHeaderRow extends StatelessWidget {
  final bool addLeftMargin;
  final bool showPlaybackActions;
  final VoidCallback? onArrowDownPressed;

  const YTQueueChipHeaderRow({super.key, this.addLeftMargin = false, this.showPlaybackActions = false, this.onArrowDownPressed});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class LocalQueueChipHeaderRow extends StatelessWidget {
  final bool addLeftMargin;
  final bool showPlaybackActions;
  final VoidCallback? onArrowDownPressed;

  const LocalQueueChipHeaderRow({super.key, this.addLeftMargin = false, this.showPlaybackActions = false, this.onArrowDownPressed});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class MixedQueueChipHeaderRow extends StatelessWidget {
  final bool addLeftMargin;
  final bool showPlaybackActions;
  final VoidCallback? onArrowDownPressed;

  const MixedQueueChipHeaderRow({super.key, this.addLeftMargin = false, this.showPlaybackActions = false, this.onArrowDownPressed});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class SkipSponsorButton extends StatelessWidget {
  final Color? itemsColor;

  const SkipSponsorButton({super.key, this.itemsColor});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class YtThumbnailOverlayBox extends StatelessWidget {
  final String? text;
  final dynamic icon;

  const YtThumbnailOverlayBox({super.key, this.text, this.icon});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

// ---------------------------------------------------------------------------
// Controllers (singletons, forwarded)
// ---------------------------------------------------------------------------

class YoutubeInfoController {
  static final YoutubeInfoController inst = YoutubeInfoController._();
  const YoutubeInfoController._();
  static final YoutubeInfoCurrentStub current = YoutubeInfoCurrentStub();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  // === AUTO CLASS START ===
  static dynamic initialize([dynamic a0, dynamic a1, dynamic a2, dynamic a3, dynamic a4, dynamic a5, dynamic a6, dynamic a7]) => null;
  static dynamic dispose([dynamic a0, dynamic a1, dynamic a2, dynamic a3, dynamic a4, dynamic a5, dynamic a6, dynamic a7]) => null;
  // === AUTO CLASS END ===

  // -- outside the AUTO block on purpose, see [QueueChipHeaderRow.minHeight].
  // -- these namespaces are dereferenced all over the app: `utils.getVideoName(...)`,
  // -- `utils.lazyInfoRefresh` is handed to `ObxO(rx:)` & `textRefreshRx:` (incl. inside the
  // -- lyrics view), `video.fetchVideoStreams(...)`, `history.markVideoWatched(...)`.
  // -- returning `null` turns each of those into a NoSuchMethodError.
  static dynamic get utils => _stubYoutubeInfoNamespace;
  static dynamic get video => _stubYoutubeInfoNamespace;
  static dynamic get history => _stubYoutubeInfoNamespace;
  static dynamic get playlist => _stubYoutubeInfoNamespace;
  static dynamic get search => _stubYoutubeInfoNamespace;
}

final _stubYoutubeInfoNamespace = _YoutubeInfoNamespaceStub();

class _YoutubeInfoNamespaceStub {
  /// drives the metadata refresh listeners, so it has to be a real observable.
  final Rxn<int> lazyInfoRefresh = Rxn<int>();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class YoutubeInfoCurrentStub {
  final Rxn<VideoStreamsResult> currentYTStreams = Rxn<VideoStreamsResult>();
  final RxList<NamidaVideo> currentCachedQualities = RxList<NamidaVideo>(<NamidaVideo>[]);
  final Rxn<YoutubeVideoPage> currentVideoPage = Rxn<YoutubeVideoPage>();

  void onVideoPageReset() {}
  void resetAll() {}
  Future<bool> updateCurrentCommentsCache([dynamic value]) async => true;
  Future<void> updateVideoPage(dynamic value, {bool? requestPage, bool? requestComments}) async {}
  Future<bool> updateVideoPageCache([dynamic value]) async => true;
  void clearCurrentDislikeCount() {}
  void fetchAndUpdateDislikeCount([dynamic value]) {}
}

class YoutubeVideoPage {
  final List<YoutubeStreamSegment> streamSegments;
  final dynamic videoInfo;
  final dynamic channelInfo;

  const YoutubeVideoPage({this.streamSegments = const [], this.videoInfo, this.channelInfo});
}

class YoutubeStreamSegment {
  final String title;
  final int? startSeconds;

  const YoutubeStreamSegment({this.title = '', this.startSeconds});
}

extension YoutubeStreamSegmentListUtils on List<YoutubeStreamSegment> {
  YoutubeStreamSegment? findByMillisecond(int milliseconds) => isEmpty ? null : first;
}

class YoutubeHistoryController with HistoryManager<YoutubeID, String> {
  static final YoutubeHistoryController inst = YoutubeHistoryController._();
  YoutubeHistoryController._();

  @override
  String mainItemToSubItem(YoutubeID item) => item.id;

  @override
  Future<HistoryPrepareInfo<YoutubeID, String>> prepareAllHistoryFilesFunction(String directoryPath) async => HistoryPrepareInfo(
        historyMap: SplayTreeMap<int, List<YoutubeID>>(),
        topItems: ListensSortedMap<String>(),
        totalItemsCount: 0,
      );

  @override
  Map<String, dynamic> itemToJson(YoutubeID item) => item.toJson();

  @override
  String get HISTORY_DIRECTORY => '';

  @override
  Rx<MostPlayedTimeRange> get currentMostPlayedTimeRange => MostPlayedTimeRange.allTime.obs;

  @override
  Rx<DateRange> get mostPlayedCustomDateRange => DateRange(
        oldest: DateTime.fromMillisecondsSinceEpoch(0),
        newest: DateTime.now(),
      ).obs;

  @override
  Rx<bool> get mostPlayedCustomIsStartOfDay => false.obs;

  @override
  double daysToSectionExtent(List<int> days) => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;

}

class YoutubeController {
  static final YoutubeController inst = YoutubeController._();
  const YoutubeController._();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  // === AUTO CLASS START ===
  dynamic get statsManager => null;
  // 保留上游空列表与首项回退契约。
  static AudioStream? getPreferredAudioStream(List<AudioStream>? streams) {
    if (streams == null || streams.isEmpty) return null;
    return streams.first;
  }

  // 仅匹配确定相同的音频流，不猜测相似流。
  static AudioStream? matchAudioStreamOrSimilar(List<AudioStream>? streams, AudioStream? target, {String? prefferedItag}) {
    if (streams == null || streams.isEmpty) return null;
    final targetItag = prefferedItag == null ? target?.itag : int.tryParse(prefferedItag) ?? target?.itag;
    if (targetItag == null) return null;
    for (final stream in streams) {
      if (stream.itag == targetItag) return stream;
    }
    return null;
  }

  // 仅匹配确定相同的视频流，不猜测相似流。
  static VideoStream? matchVideoStreamOrSimilar(List<VideoStream>? streams, VideoStream? target, {String? prefferedItag}) {
    if (streams == null || streams.isEmpty) return null;
    final targetItag = prefferedItag == null ? target?.itag : int.tryParse(prefferedItag) ?? target?.itag;
    if (targetItag == null) return null;
    for (final stream in streams) {
      if (stream.itag == targetItag) return stream;
    }
    return null;
  }

  // 保留上游空列表与末项回退契约。
  static VideoStream? getPreferredStreamQuality(List<VideoStream> streams, {List<String> qualities = const [], bool preferIncludeWebm = false}) {
    if (streams.isEmpty) return null;
    return streams.last;
  }

  dynamic stopLatestSingleDownload([dynamic a0, dynamic a1, dynamic a2, dynamic a3, dynamic a4, dynamic a5, dynamic a6, dynamic a7]) => null;
  static dynamic isSameVideoStream([dynamic a0, dynamic a1, dynamic a2, dynamic a3, dynamic a4, dynamic a5, dynamic a6, dynamic a7]) => null;
  dynamic dispose([dynamic a0, dynamic a1, dynamic a2, dynamic a3, dynamic a4, dynamic a5, dynamic a6, dynamic a7]) => null;
  Future<dynamic> downloadYoutubeVideo({dynamic canStartDownloading, dynamic id, dynamic stream, dynamic creationDate, dynamic onAvailableQualities, dynamic onChoosingQuality, dynamic onInitialFileSize, dynamic downloadingStream}) async => null;
  dynamic loadDownloadTasksInfoFileAsync([dynamic a0, dynamic a1, dynamic a2, dynamic a3, dynamic a4, dynamic a5, dynamic a6, dynamic a7]) => null;
  static dynamic removeDuplicateCachedQualities([dynamic a0, dynamic a1, dynamic a2, dynamic a3, dynamic a4, dynamic a5, dynamic a6, dynamic a7]) => null;
  // === AUTO CLASS END ===

  // -- outside the AUTO block on purpose, see [_stubRawDownloadsCountRx].
  dynamic get activeRawDownloadsCount => _stubRawDownloadsCountRx;
}

class YoutubePlaylistController extends PlaylistManager<YoutubeID, String, YTSortType> {
  static final YoutubePlaylistController inst = YoutubePlaylistController._();
  YoutubePlaylistController._() : super();

  @override
  RegExp get cleanupFilenameRegex => RegExp(r'[\\/:*?"<>|]');

  @override
  String identifyBy(YoutubeID item) => item.id;

  @override
  String get playlistsDirectory => '';
  @override
  String get playlistsArtworksDirectory => '';
  @override
  String get playlistsMetadataDirectory => '';
  @override
  String get favouritePlaylistPath => '';
  @override
  String get EMPTY_NAME => '';
  @override
  String get NAME_CONTAINS_BAD_CHARACTER => '';
  @override
  String get SAME_NAME_EXISTS => '';
  @override
  String get NAME_IS_NOT_ALLOWED => '';
  @override
  String get PLAYLIST_NAME_FAV => 'YouTube Favourites';
  @override
  String get PLAYLIST_NAME_HISTORY => 'YouTube History';
  @override
  String get PLAYLIST_NAME_MOST_PLAYED => 'YouTube Most Played';

  @override
  Map<String, dynamic> itemToJson(YoutubeID item) => item.toJson();

  @override
  Future<Map<String, GeneralPlaylist<YoutubeID, YTSortType>>> prepareAllPlaylistsFunction() async => {};

  @override
  Future<GeneralPlaylist<YoutubeID, YTSortType>?> prepareFavouritePlaylistFunction() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  // YouTube 收藏已移除，保留可空结果和通知参数契约。
  bool favouriteButtonOnPressed(dynamic item, {bool refreshNotification = true}) => false;
  dynamic prepareAllPlaylists([dynamic a0, dynamic a1, dynamic a2, dynamic a3, dynamic a4, dynamic a5, dynamic a6, dynamic a7]) => null;
  dynamic resetCanReorder([dynamic a0, dynamic a1, dynamic a2, dynamic a3, dynamic a4, dynamic a5, dynamic a6, dynamic a7]) => null;
  dynamic addNewPlaylist(dynamic name, {dynamic videoIds}) => null;
  
  Future<void> importTracksToPlaylist(GeneralPlaylist<YoutubeID, YTSortType> playlist, Iterable<YoutubeID> tracks) => super.importTracksToPlaylist(playlist, tracks);
  static dynamic fromJson([dynamic a0, dynamic a1, dynamic a2, dynamic a3, dynamic a4, dynamic a5, dynamic a6, dynamic a7]) => null;
  static dynamic toJson([dynamic a0, dynamic a1, dynamic a2, dynamic a3, dynamic a4, dynamic a5, dynamic a6, dynamic a7]) => null;
  static dynamic get name => null;
}

class YoutubeSubscriptionsController {
  static final YoutubeSubscriptionsController inst = YoutubeSubscriptionsController._();
  const YoutubeSubscriptionsController._();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  // === AUTO CLASS START ===
  dynamic buildSyncEntries([dynamic a0, dynamic a1, dynamic a2, dynamic a3, dynamic a4, dynamic a5, dynamic a6, dynamic a7]) => null;
  dynamic readAllGroups([dynamic a0, dynamic a1, dynamic a2, dynamic a3, dynamic a4, dynamic a5, dynamic a6, dynamic a7]) => null;
  dynamic importGroups([dynamic a0, dynamic a1, dynamic a2, dynamic a3, dynamic a4, dynamic a5, dynamic a6, dynamic a7]) => null;
  Future<void> import(Iterable<YoutubeSubscription> items) async {}
  dynamic loadSubscriptionsFileAsync([dynamic a0, dynamic a1, dynamic a2, dynamic a3, dynamic a4, dynamic a5, dynamic a6, dynamic a7]) => null;
  static dynamic fromJson([dynamic a0, dynamic a1, dynamic a2, dynamic a3, dynamic a4, dynamic a5, dynamic a6, dynamic a7]) => null;
  static dynamic toJson([dynamic a0, dynamic a1, dynamic a2, dynamic a3, dynamic a4, dynamic a5, dynamic a6, dynamic a7]) => null;
  // === AUTO CLASS END ===
}

class YoutubeAccountController {
  static final YoutubeAccountController inst = YoutubeAccountController._();
  const YoutubeAccountController._();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  // === AUTO CLASS START ===
  static final YoutubeMembershipStub membership = YoutubeMembershipStub();
  static dynamic initialize([dynamic a0, dynamic a1, dynamic a2, dynamic a3, dynamic a4, dynamic a5, dynamic a6, dynamic a7]) => null;
  static dynamic fetchAccSupportDetails([dynamic a0, dynamic a1, dynamic a2, dynamic a3, dynamic a4, dynamic a5, dynamic a6, dynamic a7]) => null;
  // === AUTO CLASS END ===

  // -- outside the AUTO block on purpose, see [QueueChipHeaderRow.minHeight]:
  // -- `current.activeAccountChannel` is both passed to `ObxO(rx: ...)` and `.value`d,
  // -- so `null` here throws a type error / a NoSuchMethodError respectively.
  static dynamic get current => _stubYoutubeAccount;
}

final _stubYoutubeAccount = YoutubeAccountStub();

class YoutubeAccountStub {
  final Rxn<String> activeAccountChannel = Rxn<String>();
}

class YoutubeMembershipStub {
  final Rxn<MembershipType> userMembershipTypeGlobal = Rxn<MembershipType>();
  final Rxn<MembershipType> userMembershipTypePatreon = Rxn<MembershipType>();
  final Rxn<dynamic> userSupabaseSub = Rxn<dynamic>();
  dynamic redirectUrlCompleter;
}

class YoutubeImportController {
  static final YoutubeImportController inst = YoutubeImportController._();
  const YoutubeImportController._();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  // === AUTO CLASS START ===
  static dynamic parseDate([dynamic a0, dynamic a1, dynamic a2, dynamic a3, dynamic a4, dynamic a5, dynamic a6, dynamic a7]) => null;
  // === AUTO CLASS END ===
}

class YoutubeLocalSearchController {
  static final YoutubeLocalSearchController inst = YoutubeLocalSearchController._();
  const YoutubeLocalSearchController._();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class YtGeneratorsController {
  static final YtGeneratorsController inst = YtGeneratorsController._();
  const YtGeneratorsController._();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class YoutubeMiniplayerUiController {
  static final YoutubeMiniplayerUiController inst = YoutubeMiniplayerUiController._();
  const YoutubeMiniplayerUiController._();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  // === AUTO CLASS START ===
  void startDimTimer({dynamic brightness}) {}
  dynamic get ytMiniplayerKey => null;
  dynamic ensureSegmentsVisible([dynamic a0, dynamic a1, dynamic a2, dynamic a3, dynamic a4, dynamic a5, dynamic a6, dynamic a7]) => null;
  // === AUTO CLASS END ===
}

class SponsorBlockController {
  static final SponsorBlockController inst = SponsorBlockController._();
  const SponsorBlockController._();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  // === AUTO CLASS START ===
  dynamic clearSegmentsIfVideoIsDifferent([dynamic a0, dynamic a1, dynamic a2, dynamic a3, dynamic a4, dynamic a5, dynamic a6, dynamic a7]) => null;
  dynamic updateSegments([dynamic a0, dynamic a1, dynamic a2, dynamic a3, dynamic a4, dynamic a5, dynamic a6, dynamic a7]) => null;
  dynamic clearSegments([dynamic a0, dynamic a1, dynamic a2, dynamic a3, dynamic a4, dynamic a5, dynamic a6, dynamic a7]) => null;
  // === AUTO CLASS END ===
}

class YtVideoLikeManager {
  static final YtVideoLikeManager inst = YtVideoLikeManager._();
  const YtVideoLikeManager._();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  // === AUTO CLASS START ===
  static dynamic get current => null;
  static dynamic get preferLikeOverFavourite => null;
  dynamic get currentVideoLikeStatus => null;
  dynamic onLikeClicked([dynamic a0, dynamic a1, dynamic a2, dynamic a3, dynamic a4, dynamic a5, dynamic a6, dynamic a7]) => null;
  // === AUTO CLASS END ===
}

class NamidaYTGenerator {
  const NamidaYTGenerator();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  // === AUTO CLASS START ===
  static dynamic get inst => null;
  // === AUTO CLASS END ===
}

class YTUtils {
  const YTUtils();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  // === AUTO CLASS START ===
  dynamic showVideoClearDialog(dynamic videoId, {dynamic afterDeleting, dynamic extraTiles}) => null;
  static dynamic copyThumbnailToStorage([dynamic a0, dynamic a1, dynamic a2, dynamic a3, dynamic a4, dynamic a5, dynamic a6, dynamic a7]) => null;
  static dynamic getPlayerAfterVideo([dynamic a0, dynamic a1, dynamic a2, dynamic a3, dynamic a4, dynamic a5, dynamic a6, dynamic a7]) => null;
  static dynamic getVideoCardMenuItemsForCurrentlyPlaying({dynamic queueSource, dynamic numberOfRepeats, dynamic videoId, dynamic videoTitle, dynamic channelID, dynamic displayGoToChannel, dynamic displayCopyUrl}) => null;
  static dynamic getVideoCardMenuItems({
    dynamic queueSource,
    dynamic downloadIndex,
    dynamic totalLength,
    dynamic streamInfoItem,
    dynamic videoId,
    dynamic channelID,
    dynamic displayGoToChannel,
    dynamic playlistID,
    dynamic playlistId,
    dynamic showInfoTile,
    dynamic idsNamesLookup,
    dynamic isInFullScreen,
    dynamic userPlaylist,
  }) => null;
  static dynamic getVideosMenuItems({dynamic queueSource, dynamic context, dynamic videos, dynamic playlistName}) => null;
  static dynamic get onYoutubeHistoryPlaylistTap => null;
  static dynamic onYoutubeMostPlayedPlaylistTap({dynamic mptr, dynamic dateCustom}) => null;
  dynamic copyCurrentVideoUrl(dynamic a0, {dynamic withTimestamp}) => null;
  static dynamic showCopyItemsDialog([dynamic a0, dynamic a1, dynamic a2, dynamic a3, dynamic a4, dynamic a5, dynamic a6, dynamic a7]) => null;
  // === AUTO CLASS END ===
}

class ReturnYoutubeDislikeSettings {
  final bool enabled;
  const ReturnYoutubeDislikeSettings({this.enabled = true});
  static ReturnYoutubeDislikeSettings fromJson(Map<String, dynamic>? json) => ReturnYoutubeDislikeSettings(enabled: json?['enabled'] as bool? ?? true);
  Map<String, dynamic> toJson() => {'enabled': enabled};
  String get defaultWebsiteUrl => 'https://returnyoutubedislike.com';
  ReturnYoutubeDislikeSettings copyWith({bool? enabled}) => ReturnYoutubeDislikeSettings(enabled: enabled ?? this.enabled);
}

class SponsorBlockSettings {
  final bool enabled;
  final bool trackSkipCount;
  final String? serverAddress;
  final int hideSkipButtonAfterMS;
  final int minimumSegmentDurationMS;
  final bool removeSegmentsFromDownloads;
  final Map<SponsorBlockCategory, SponsorBlockCategoryConfig> configs;
  const SponsorBlockSettings({this.enabled = true, this.trackSkipCount = true, this.serverAddress, this.hideSkipButtonAfterMS = 4000, this.minimumSegmentDurationMS = 0, this.removeSegmentsFromDownloads = false, this.configs = const {}});
  String get defaultServerAddress => 'https://sponsor.ajay.app';
  static SponsorBlockSettings fromJson(Map<String, dynamic>? json) => SponsorBlockSettings(enabled: json?['enabled'] as bool? ?? true);
  Map<String, dynamic> toJson() => {'enabled': enabled};
  SponsorBlockSettings copyWith({bool? enabled, bool? trackSkipCount, String? serverAddress, int? hideSkipButtonAfterMS, int? minimumSegmentDurationMS, bool? removeSegmentsFromDownloads, Map<SponsorBlockCategory, SponsorBlockCategoryConfig>? configs}) => SponsorBlockSettings(enabled: enabled ?? this.enabled, trackSkipCount: trackSkipCount ?? this.trackSkipCount, serverAddress: serverAddress ?? this.serverAddress, hideSkipButtonAfterMS: hideSkipButtonAfterMS ?? this.hideSkipButtonAfterMS, minimumSegmentDurationMS: minimumSegmentDurationMS ?? this.minimumSegmentDurationMS, removeSegmentsFromDownloads: removeSegmentsFromDownloads ?? this.removeSegmentsFromDownloads, configs: configs ?? this.configs);
}

class SponsorBlockCategoryConfig {
  final SponsorBlockAction action;
  final Color color;
  final bool removeFromDownloads;
  const SponsorBlockCategoryConfig(this.action, this.color, this.removeFromDownloads);
  SponsorBlockCategoryConfig copyWith({SponsorBlockAction? action, Color? color, bool? removeFromDownloads}) => SponsorBlockCategoryConfig(action ?? this.action, color ?? this.color, removeFromDownloads ?? this.removeFromDownloads);
}

extension SponsorBlockCategoryStubUtils on SponsorBlockCategory {
  SponsorBlockCategoryConfig get defaultConfig => SponsorBlockCategoryConfig(SponsorBlockAction.showSkipButton, const Color(0xB200D400), this != SponsorBlockCategory.poi_highlight);
  bool get canBeRemovedFromDownloads => this != SponsorBlockCategory.poi_highlight;
}

class YoutubeSearchResultsPageState extends State<YoutubeSearchResultsPage> {
  static String? _latestSearch;
  YoutubeSearchResultsPageState();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  // === AUTO CLASS START ===
  static dynamic setFilters([dynamic a0, dynamic a1, dynamic a2, dynamic a3, dynamic a4, dynamic a5, dynamic a6, dynamic a7]) => null;
  Future<void> fetchSearch({String? customText}) async { _latestSearch = customText; }
  String? get currentSearchText => _latestSearch;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
  // === AUTO CLASS END ===
}

/// YouTube 搜索页的空实现，保留页面状态和搜索入口契约。
class YoutubeSearchResultsPage extends StatefulWidget {
  final String Function()? searchTextCallback;
  final void Function(StreamInfoItem video)? onVideoTap;

  const YoutubeSearchResultsPage({super.key, this.searchTextCallback, this.onVideoTap});

  @override
  YoutubeSearchResultsPageState createState() => YoutubeSearchResultsPageState();
}

class YTHostedPlaylistSubpage {
  const YTHostedPlaylistSubpage();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  // === AUTO CLASS START ===
  static dynamic fromId({dynamic playlistId, dynamic userPlaylist}) => null;
  // === AUTO CLASS END ===
}

class SeekReadyWidget extends StatefulWidget {
  final bool isLocal;
  final bool isFullscreen;
  final bool showPositionCircle;
  final bool showSponsorBlockSegments;
  final bool showBufferBars;
  final bool clampCircleEdges;
  final bool useReducedProgressColor;
  final bool Function()? canDrag;
  final void Function(bool)? onDraggingChange;

  const SeekReadyWidget({
    super.key,
    this.isLocal = false,
    this.isFullscreen = false,
    this.showPositionCircle = true,
    this.showSponsorBlockSegments = true,
    this.showBufferBars = true,
    this.clampCircleEdges = false,
    this.useReducedProgressColor = false,
    this.canDrag,
    this.onDraggingChange,
  });

  static final GlobalKey<SeekReadyWidgetState> fullscreenKey = GlobalKey<SeekReadyWidgetState>();
  static final GlobalKey<SeekReadyWidgetState> normalKey = GlobalKey<SeekReadyWidgetState>();

  @override
  SeekReadyWidgetState createState() => SeekReadyWidgetState();
}

class SeekReadyWidgetState extends State<SeekReadyWidget> {
  Widget createHitTestWidget({bool expandHitTest = false, bool allowTapping = true, double? maxWidth}) => const SizedBox.shrink();
  void onHorizontalDragStartSimple([DragStartDetails? details]) {}
  void onHorizontalDragUpdateSimple(DragUpdateDetails details) {}
  void onHorizontalDragEnd({DragEndDetails? details, bool allowMagnet = true}) {}
  void onHorizontalDragCancel() {}

  VoidCallback? get onHorizontalDragCancelCallback => onHorizontalDragCancel;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

// ---------------------------------------------------------------------------
// Enums (values are best-effort; only affect runtime, not compilation)
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Misc constants & types
// ---------------------------------------------------------------------------

const double kYoutubeMiniplayerHeight = 0.0;

class DownloadTaskFilename {
  const DownloadTaskFilename();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  // === AUTO CLASS START ===
  static String cleanupFilename(dynamic value, {dynamic parentDirPath}) => value?.toString() ?? '';
  dynamic get key => null;
  static dynamic get cleanupFilenameRegex => null;
  // === AUTO CLASS END ===
}

class YoutubeSubscription {
  final String id;
  final String name;
  const YoutubeSubscription({this.id = '', this.name = ''});
  factory YoutubeSubscription.fromJson(Map<String, dynamic> json) => YoutubeSubscription(id: json['id'] as String? ?? '', name: json['name'] as String? ?? '');
  Map<String, dynamic> toJson() => {'id': id, 'name': name};
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class VideoPlayerInfo {
  const VideoPlayerInfo();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class PlaylistRemoteSource {
  final String sourceKey;
  final String remoteId;

  const PlaylistRemoteSource({required this.sourceKey, required this.remoteId});

  static const PlaylistRemoteSource? none = null;
}

class YoutubePlaylist extends GeneralPlaylist<YoutubeID, YTSortType> {
  const YoutubePlaylist({super.name = '', super.tracks = const []});
  factory YoutubePlaylist.fromJson(
    Map<String, dynamic> json,
    YoutubeID Function(Map<String, dynamic>) itemFromJson,
    dynamic Function(dynamic) sortFromJson,
  ) => YoutubePlaylist(
    name: json['name'] as String? ?? '',
    tracks: (json['tracks'] as List? ?? const []).whereType<Map>().map((e) => itemFromJson(e.cast<String, dynamic>())).toList(),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class YoutubeSettingsController {
  const YoutubeSettingsController();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  // === AUTO CLASS START ===
  static dynamic openDataSaverConfigureDialog([dynamic a0, dynamic a1, dynamic a2, dynamic a3, dynamic a4, dynamic a5, dynamic a6, dynamic a7]) => null;
  // === AUTO CLASS END ===
}

class SeekReadyDimensions {
  const SeekReadyDimensions();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  // -- see [QueueChipHeaderRow.minHeight], these are divided in layout math (`barHeight / 2`).
  static dynamic get barHeight => 4.0;
  static dynamic get progressBarHeight => 4.0;
}

class YTMarkVideoWatchedResult {
  const YTMarkVideoWatchedResult();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  // === AUTO CLASS START ===
  static dynamic get addedAsPending => null;
  // === AUTO CLASS END ===
}

/// 空缩略图组件，保留原页面的构造参数。
class YoutubeThumbnail extends StatelessWidget {
  final ThumbnailType type;
  final String? videoId;
  final String? id;
  final String? customUrl;
  final double? width;
  final double? height;
  final double? borderRadius;

  const YoutubeThumbnail({
    super.key,
    this.type = ThumbnailType.video,
    this.videoId,
    this.id,
    this.customUrl,
    this.width,
    this.height,
    this.borderRadius,
    bool? isImportantInCache,
    bool? isTemp,
    bool? isCircle,
    bool? forceSquared,
    bool? displayFallbackIcon,
    bool? disableBlurBgSizeShrink,
    bool? preferLowerRes,
    bool? compressed,
    double? blur,
    double? blurRadius,
    dynamic icon,
    dynamic iconSize,
    dynamic fit,
    dynamic onColorReady,
    dynamic onTopWidgets,
    bool? extractColor,
    int? fadeMilliSeconds,
    List<BoxShadow>? boxShadow,
    bool? allowFloating,
  });

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class MembershipCard extends StatelessWidget {
  final bool displayName;
  const MembershipCard({super.key, this.displayName = true});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// 视频历史卡片空实现，只保留调用方需要的构造参数。
class YTHistoryVideoCard extends StatelessWidget {
  const YTHistoryVideoCard({
    super.key,
    dynamic properties,
    dynamic videos,
    int? index,
    dynamic day,
    double? thumbnailHeight,
    double? cardColorOpacity,
    double? fadeOpacity,
    bool? preferFetchNewInfo,
    bool? minimalCard,
    double? minimalCardWidth,
    dynamic overrideListens,
  });

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// 支持任意条目类型的历史卡片空实现。
class YTHistoryVideoCardBase<T> extends StatelessWidget {
  const YTHistoryVideoCardBase({
    super.key,
    dynamic properties,
    dynamic mainList,
    dynamic itemToYTVideoId,
    dynamic info,
    int? index,
    dynamic day,
    double? minimalCardWidth,
    double? thumbnailHeight,
    dynamic overrideListens,
    bool? minimalCard,
  });

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// YouTube 风格小播放器空实现。
class YoutubeMiniPlayer extends StatelessWidget {
  const YoutubeMiniPlayer({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// 视频卡片属性占位类型。
class VideoTileProperties {
  const VideoTileProperties();
}

class VideoTilePropertiesConfigs {
  final dynamic queueSource;
  final dynamic playlistID;

  const VideoTilePropertiesConfigs({
    this.queueSource,
    this.playlistID,
    bool? openMenuOnLongPress,
    bool? displayTimeAgo,
    bool? draggingEnabled,
    bool? draggableThumbnail,
    bool? showMoreIcon,
    bool? horizontalGestures,
  });
}

class VideoTilePropertiesProvider extends StatelessWidget {
  final VideoTilePropertiesConfigs? configs;
  final Widget Function(VideoTileProperties) builder;

  const VideoTilePropertiesProvider({super.key, this.configs, required this.builder});

  @override
  Widget build(BuildContext context) => builder(const VideoTileProperties());
}

class YTMiniplayerQueueChipState extends State<YTMiniplayerQueueChip> {
  bool isOpened = false;
  void dismissSheet() {}
  void openSheet() => isOpened = true;
  void toggleSheet() => isOpened = !isOpened;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class YTMiniplayerQueueChip extends StatefulWidget {
  const YTMiniplayerQueueChip({super.key});

  @override
  YTMiniplayerQueueChipState createState() => YTMiniplayerQueueChipState();
}

class YTVideoLikeParamters {
  final bool isActive;
  final LikeAction action;
  final void Function()? onStart;
  final void Function()? onEnd;

  const YTVideoLikeParamters({required this.isActive, required this.action, this.onStart, this.onEnd});
}

class YoutubeManageSubscriptionPage extends StatelessWidget with NamidaRouteWidget {
  const YoutubeManageSubscriptionPage({super.key});

  @override
  RouteType get route => RouteType.YOUTUBE_USER_MANAGE_SUBSCRIPTION_SUBPAGE;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// YouTube 页面已移除，保留可构造的空页面以维持导航和路由类型。
class YouTubeHomeView extends StatelessWidget with NamidaRouteWidget {
  const YouTubeHomeView({super.key});

  @override
  RouteType get route => RouteType.YOUTUBE_HOME;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// YouTube 视频信息弹窗的空实现。
class VideoInfoDialog extends StatelessWidget {
  final String videoId;

  const VideoInfoDialog({super.key, required this.videoId});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// YouTube 频道页的空实现。
class YTChannelSubpage extends StatelessWidget with NamidaRouteWidget {
  final String channelID;
  final dynamic channel;

  const YTChannelSubpage({super.key, required this.channelID, this.channel});

  @override
  RouteType get route => RouteType.YOUTUBE_CHANNEL_SUBPAGE;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// YouTube 播放列表下载页的空实现。
class YTPlaylistDownloadPage extends StatelessWidget with NamidaRouteWidget {
  final List<YoutubeID> ids;
  final String playlistName;
  final Map<String, dynamic> infoLookup;
  final PlaylistBasicInfo playlistInfo;

  const YTPlaylistDownloadPage({
    super.key,
    required this.ids,
    required this.playlistName,
    required this.infoLookup,
    required this.playlistInfo,
  });

  @override
  RouteType get route => RouteType.YOUTUBE_PLAYLIST_DOWNLOAD_SUBPAGE;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// YouTube 操作入口在移除功能后保持无操作行为。
void showAddToPlaylistSheet({required Iterable<String> ids, required Map<String, String> idsNamesLookup}) {}

/// YouTube 播放记录弹窗在移除功能后保持无操作行为。
void showVideoListensDialog(String videoId) {}

/// YouTube 下载入口在移除功能后保持无操作行为。
void showDownloadVideoBottomSheet({
  required String videoId,
  dynamic originalIndex,
  dynamic totalLength,
  dynamic playlistId,
  dynamic streamInfoItem,
}) {}
