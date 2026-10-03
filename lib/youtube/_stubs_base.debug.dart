// STUB layer for the removed YouTube feature.
//
// The YouTube section was stripped out of this build. These types are kept
// ONLY so the rest of namida still type-checks. Every method call on a stub
// instance is forwarded to [noSuchMethod], which returns null -- the feature
// is non-functional at runtime.

export 'dart:async';
import 'package:flutter/widgets.dart';
export 'package:flutter/widgets.dart';
export 'package:youtipie/_stubs_base.dart';
export 'package:namico_subscription_manager/_stubs_base.dart';

// ---------------------------------------------------------------------------
// YoutubeID & related Playable pieces
// ---------------------------------------------------------------------------

class YoutubeID {
  final String id;
  final String? channelUrl;
  const YoutubeID({required this.id, this.channelUrl});
  static const YoutubeID fake = YoutubeID(id: '');
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  // === AUTO CLASS START ===
  dynamic get queueSource => null;
  dynamic getThumbnail([dynamic a0, dynamic a1, dynamic a2], {dynamic temp}) => null;
  dynamic get dateAddedMS => null;
  dynamic get sourceNull => null;
  dynamic get playlistID => null;
  dynamic get watchNull => null;
  dynamic fromJson([dynamic a0, dynamic a1, dynamic a2], {dynamic isVideo}) => null;
  dynamic get watch => null;
  // === AUTO CLASS END ===
}

class YoutiPieVideoThumbnail {
  const YoutiPieVideoThumbnail();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class QueueChipHeaderRow {
  const QueueChipHeaderRow();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  // === AUTO CLASS START ===
  dynamic get minHeight => null;
  // === AUTO CLASS END ===
}

// ---------------------------------------------------------------------------
// Controllers (singletons, forwarded)
// ---------------------------------------------------------------------------

class YoutubeInfoController {
  static final YoutubeInfoController inst = YoutubeInfoController._();
  const YoutubeInfoController._();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  // === AUTO CLASS START ===
  dynamic get utils => null;
  dynamic get current => null;
  dynamic get video => null;
  dynamic get history => null;
  dynamic get playlist => null;
  dynamic get search => null;
  dynamic initialize([dynamic a0, dynamic a1, dynamic a2]) => null;
  dynamic dispose([dynamic a0, dynamic a1, dynamic a2], {dynamic force, dynamic cancelRunningRequests}) => null;
  // === AUTO CLASS END ===
}

class YoutubeHistoryController {
  static final YoutubeHistoryController inst = YoutubeHistoryController._();
  const YoutubeHistoryController._();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  // === AUTO CLASS START ===
  dynamic addTracksToHistory([dynamic a0, dynamic a1, dynamic a2]) => null;
  dynamic prepareHistoryFile([dynamic a0, dynamic a1, dynamic a2]) => null;
  dynamic removeDuplicatedItems([dynamic a0, dynamic a1, dynamic a2]) => null;
  dynamic sortHistoryTracks([dynamic a0, dynamic a1, dynamic a2]) => null;
  dynamic saveHistoryToStorage([dynamic a0, dynamic a1, dynamic a2]) => null;
  dynamic updateMostPlayedPlaylist([dynamic a0, dynamic a1, dynamic a2]) => null;
  dynamic get historyMap => null;
  dynamic setIdleStatus([dynamic a0, dynamic a1, dynamic a2]) => null;
  dynamic get totalHistoryItemsCount => null;
  dynamic get historyTracks => null;
  dynamic get topTracksMapListens => null;
  dynamic addTracksToHistoryImportPreventDuplicates([dynamic a0, dynamic a1, dynamic a2]) => null;
  dynamic getHistoryYears([dynamic a0, dynamic a1, dynamic a2]) => null;
  dynamic get isLoadingHistory => null;
  dynamic get oldestTrack => null;
  dynamic get waitForHistoryAndMostPlayedLoad => null;
  // === AUTO CLASS END ===
}

class YoutubeController {
  static final YoutubeController inst = YoutubeController._();
  const YoutubeController._();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  // === AUTO CLASS START ===
  dynamic get statsManager => null;
  dynamic getPreferredAudioStream([dynamic a0, dynamic a1, dynamic a2]) => null;
  dynamic matchVideoStreamOrSimilar([dynamic a0, dynamic a1, dynamic a2]) => null;
  dynamic getPreferredStreamQuality([dynamic a0, dynamic a1, dynamic a2], {dynamic preferIncludeWebm}) => null;
  dynamic matchAudioStreamOrSimilar([dynamic a0, dynamic a1, dynamic a2]) => null;
  dynamic stopLatestSingleDownload([dynamic a0, dynamic a1, dynamic a2]) => null;
  dynamic isSameVideoStream([dynamic a0, dynamic a1, dynamic a2]) => null;
  dynamic dispose([dynamic a0, dynamic a1, dynamic a2], {dynamic force, dynamic cancelRunningRequests}) => null;
  dynamic downloadYoutubeVideo([dynamic a0, dynamic a1, dynamic a2]) => null;
  dynamic loadDownloadTasksInfoFileAsync([dynamic a0, dynamic a1, dynamic a2]) => null;
  dynamic removeDuplicateCachedQualities([dynamic a0, dynamic a1, dynamic a2]) => null;
  dynamic get activeRawDownloadsCount => null;
  // === AUTO CLASS END ===
}

class YoutubePlaylistController {
  static final YoutubePlaylistController inst = YoutubePlaylistController._();
  const YoutubePlaylistController._();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  // === AUTO CLASS START ===
  dynamic favouriteButtonOnPressed([dynamic a0, dynamic a1, dynamic a2], {dynamic refreshNotification}) => null;
  dynamic prepareAllPlaylists([dynamic a0, dynamic a1, dynamic a2]) => null;
  dynamic prepareDefaultPlaylistsFileAsync([dynamic a0, dynamic a1, dynamic a2]) => null;
  dynamic resetCanReorder([dynamic a0, dynamic a1, dynamic a2]) => null;
  dynamic addNewPlaylist([dynamic a0, dynamic a1, dynamic a2], {dynamic tracks, dynamic m3uPath, dynamic videoIds}) => null;
  dynamic importPlaylistsIfNewer([dynamic a0, dynamic a1, dynamic a2]) => null;
  dynamic get favouritesPlaylist => null;
  dynamic importTracksToPlaylist([dynamic a0, dynamic a1, dynamic a2]) => null;
  dynamic getPlaylist([dynamic a0, dynamic a1, dynamic a2]) => null;
  // === AUTO CLASS END ===

  // === AUTO CLASS START ===
  dynamic fromJson([dynamic a0, dynamic a1, dynamic a2], {dynamic isVideo}) => null;
  dynamic toJson([dynamic a0, dynamic a1, dynamic a2], {dynamic includeTracks}) => null;
  dynamic get name => null;
  // === AUTO CLASS END ===
}

class YoutubeSubscriptionsController {
  static final YoutubeSubscriptionsController inst = YoutubeSubscriptionsController._();
  const YoutubeSubscriptionsController._();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  
  // === AUTO CLASS START ===
  dynamic buildSyncEntries([dynamic a0, dynamic a1, dynamic a2]) => null;
  dynamic readAllGroups([dynamic a0, dynamic a1, dynamic a2]) => null;
  dynamic importGroups([dynamic a0, dynamic a1, dynamic a2]) => null;
  dynamic loadSubscriptionsFileAsync([dynamic a0, dynamic a1, dynamic a2]) => null;
  // === AUTO CLASS END ===

  // === AUTO CLASS START ===
  dynamic fromJson([dynamic a0, dynamic a1, dynamic a2], {dynamic isVideo}) => null;
  dynamic toJson([dynamic a0, dynamic a1, dynamic a2], {dynamic includeTracks}) => null;
  // === AUTO CLASS END ===
}

class YoutubeAccountController {
  static final YoutubeAccountController inst = YoutubeAccountController._();
  const YoutubeAccountController._();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  // === AUTO CLASS START ===
  dynamic get current => null;
  dynamic get membership => null;
  dynamic initialize([dynamic a0, dynamic a1, dynamic a2]) => null;
  dynamic fetchAccSupportDetails([dynamic a0, dynamic a1, dynamic a2]) => null;
  // === AUTO CLASS END ===
}

class YoutubeImportController {
  static final YoutubeImportController inst = YoutubeImportController._();
  const YoutubeImportController._();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  // === AUTO CLASS START ===
  dynamic parseDate([dynamic a0, dynamic a1, dynamic a2]) => null;
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
  dynamic startDimTimer([dynamic a0, dynamic a1, dynamic a2], {dynamic brightness}) => null;
  dynamic get ytMiniplayerKey => null;
  dynamic ensureSegmentsVisible([dynamic a0, dynamic a1, dynamic a2]) => null;
  // === AUTO CLASS END ===
}

class SponsorBlockController {
  static final SponsorBlockController inst = SponsorBlockController._();
  const SponsorBlockController._();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  // === AUTO CLASS START ===
  dynamic clearSegmentsIfVideoIsDifferent([dynamic a0, dynamic a1, dynamic a2]) => null;
  dynamic updateSegments([dynamic a0, dynamic a1, dynamic a2]) => null;
  dynamic clearSegments([dynamic a0, dynamic a1, dynamic a2]) => null;
  // === AUTO CLASS END ===
}

class YtVideoLikeManager {
  static final YtVideoLikeManager inst = YtVideoLikeManager._();
  const YtVideoLikeManager._();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  // === AUTO CLASS START ===
  dynamic get current => null;
  dynamic get preferLikeOverFavourite => null;
  dynamic get currentVideoLikeStatus => null;
  dynamic onLikeClicked([dynamic a0, dynamic a1, dynamic a2]) => null;
  // === AUTO CLASS END ===
}

class NamidaYTGenerator {
  const NamidaYTGenerator();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  // === AUTO CLASS START ===
  dynamic get inst => null;
  // === AUTO CLASS END ===
}

class YTUtils {
  const YTUtils();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  // === AUTO CLASS START ===
  dynamic showVideoClearDialog([dynamic a0, dynamic a1, dynamic a2]) => null;
  dynamic copyThumbnailToStorage([dynamic a0, dynamic a1, dynamic a2]) => null;
  dynamic getPlayerAfterVideo([dynamic a0, dynamic a1, dynamic a2]) => null;
  dynamic getVideoCardMenuItemsForCurrentlyPlaying([dynamic a0, dynamic a1, dynamic a2]) => null;
  dynamic getVideoCardMenuItems([dynamic a0, dynamic a1, dynamic a2]) => null;
  dynamic getVideosMenuItems([dynamic a0, dynamic a1, dynamic a2]) => null;
  dynamic get onYoutubeHistoryPlaylistTap => null;
  dynamic onYoutubeMostPlayedPlaylistTap([dynamic a0, dynamic a1, dynamic a2]) => null;
  dynamic copyCurrentVideoUrl([dynamic a0, dynamic a1, dynamic a2], {dynamic withTimestamp}) => null;
  dynamic showCopyItemsDialog([dynamic a0, dynamic a1, dynamic a2]) => null;
  // === AUTO CLASS END ===
}

class ReturnYoutubeDislikeSettings {
  const ReturnYoutubeDislikeSettings();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  // === AUTO CLASS START ===
  dynamic get fromJson => null;
  dynamic toJson([dynamic a0, dynamic a1, dynamic a2], {dynamic includeTracks}) => null;
  dynamic get enabled => null;
  dynamic copyWith([dynamic a0, dynamic a1, dynamic a2], {dynamic pitch, dynamic type, dynamic preamp, dynamic amount, dynamic textScaler, dynamic showValueIndicator, dynamic fontSize, dynamic equalizerEnabled, dynamic top, dynamic path, dynamic hideSkipButtonAfterMS, dynamic dateModified, dynamic sorts, dynamic speed, dynamic datas, dynamic minimumSegmentDurationMS, dynamic left, dynamic fontFamily, dynamic aggregate, dynamic frequency, dynamic durationMS, dynamic size, dynamic moods, dynamic autoDisposeTimerDuration, dynamic letterSpacing, dynamic configs, dynamic generatePathHash, dynamic unit, dynamic volume, dynamic enabled, dynamic sortReverse, dynamic gain, dynamic modifiedDate, dynamic scope, dynamic year, dynamic m3uPath, dynamic title, dynamic control, dynamic add, dynamic action, dynamic skipSilence, dynamic fontWeight, dynamic fontFeatures, dynamic equalizer, dynamic color, dynamic removeSegmentsFromDownloads, dynamic isFav, dynamic trackSkipCount, dynamic removeFromDownloads, dynamic chat, dynamic w700, dynamic disableAnimations, dynamic decoration, dynamic q, dynamic loudnessEnhancerEnabled, dynamic relativeDuration, dynamic joiner, dynamic serverAddress, dynamic height, dynamic channel, dynamic autoPreamp, dynamic loudnessEnhancer, dynamic name, dynamic edit, dynamic limiter, dynamic order}) => null;
  dynamic get defaultWebsiteUrl => null;
  // === AUTO CLASS END ===
}

class SponsorBlockSettings {
  const SponsorBlockSettings();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  // === AUTO CLASS START ===
  dynamic get enabled => null;
  dynamic get fromJson => null;
  dynamic toJson([dynamic a0, dynamic a1, dynamic a2], {dynamic includeTracks}) => null;
  dynamic copyWith([dynamic a0, dynamic a1, dynamic a2], {dynamic pitch, dynamic type, dynamic preamp, dynamic amount, dynamic textScaler, dynamic showValueIndicator, dynamic fontSize, dynamic equalizerEnabled, dynamic top, dynamic path, dynamic hideSkipButtonAfterMS, dynamic dateModified, dynamic sorts, dynamic speed, dynamic datas, dynamic minimumSegmentDurationMS, dynamic left, dynamic fontFamily, dynamic aggregate, dynamic frequency, dynamic durationMS, dynamic size, dynamic moods, dynamic autoDisposeTimerDuration, dynamic letterSpacing, dynamic configs, dynamic generatePathHash, dynamic unit, dynamic volume, dynamic enabled, dynamic sortReverse, dynamic gain, dynamic modifiedDate, dynamic scope, dynamic year, dynamic m3uPath, dynamic title, dynamic control, dynamic add, dynamic action, dynamic skipSilence, dynamic fontWeight, dynamic fontFeatures, dynamic equalizer, dynamic color, dynamic removeSegmentsFromDownloads, dynamic isFav, dynamic trackSkipCount, dynamic removeFromDownloads, dynamic chat, dynamic w700, dynamic disableAnimations, dynamic decoration, dynamic q, dynamic loudnessEnhancerEnabled, dynamic relativeDuration, dynamic joiner, dynamic serverAddress, dynamic height, dynamic channel, dynamic autoPreamp, dynamic loudnessEnhancer, dynamic name, dynamic edit, dynamic limiter, dynamic order}) => null;
  dynamic get removeSegmentsFromDownloads => null;
  dynamic get hideSkipButtonAfterMS => null;
  dynamic get minimumSegmentDurationMS => null;
  dynamic get configs => null;
  dynamic get trackSkipCount => null;
  dynamic get serverAddress => null;
  dynamic get defaultServerAddress => null;
  // === AUTO CLASS END ===
}

class YoutubeSearchResultsPageState {
  const YoutubeSearchResultsPageState();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  // === AUTO CLASS START ===
  dynamic setFilters([dynamic a0, dynamic a1, dynamic a2]) => null;
  dynamic fetchSearch([dynamic a0, dynamic a1, dynamic a2], {dynamic customText}) => null;
  dynamic get currentSearchText => null;
  // === AUTO CLASS END ===
}

class YTHostedPlaylistSubpage {
  const YTHostedPlaylistSubpage();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  // === AUTO CLASS START ===
  dynamic fromId([dynamic a0, dynamic a1, dynamic a2], {dynamic playlistId, dynamic userPlaylist}) => null;
  // === AUTO CLASS END ===
}

class SeekReadyWidget extends StatelessWidget {
  const SeekReadyWidget({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();

  // === AUTO CLASS START ===
  dynamic get fullscreenKey => null;
  dynamic get normalKey => null;
  // === AUTO CLASS END ===
}

// ---------------------------------------------------------------------------
// Enums (values are best-effort; only affect runtime, not compilation)
// ---------------------------------------------------------------------------

enum PlaylistTagFilterState { none, included, excluded }

enum PlaylistTagsFilter { all, any }

// ---------------------------------------------------------------------------
// Misc constants & types
// ---------------------------------------------------------------------------

const double kYoutubeMiniplayerHeight = 0.0;

class DownloadTaskFilename {
  const DownloadTaskFilename();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  // === AUTO CLASS START ===
  dynamic cleanupFilename([dynamic a0, dynamic a1, dynamic a2], {dynamic parentDirPath}) => null;
  dynamic get key => null;
  dynamic get cleanupFilenameRegex => null;
  // === AUTO CLASS END ===
}

class YoutubeSubscription {
  const YoutubeSubscription();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class VideoPlayerInfo {
  const VideoPlayerInfo();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class PlaylistRemoteSource {
  const PlaylistRemoteSource();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  // === AUTO CLASS START ===
  dynamic get none => null;
  // === AUTO CLASS END ===
}

class YoutubePlaylist {
  const YoutubePlaylist();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class YoutubeSettings {
  const YoutubeSettings();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  // === AUTO CLASS START ===
  dynamic openDataSaverConfigureDialog([dynamic a0, dynamic a1, dynamic a2]) => null;
  // === AUTO CLASS END ===
}

class PlayerConfigModificationScale {
  const PlayerConfigModificationScale();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  // === AUTO CLASS START ===
  dynamic get main => null;
  dynamic get alt => null;
  dynamic get none => null;
  // === AUTO CLASS END ===
}

class SeekReadyDimensions {
  const SeekReadyDimensions();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  // === AUTO CLASS START ===
  dynamic get barHeight => null;
  dynamic get progressBarHeight => null;
  // === AUTO CLASS END ===
}

class YTMarkVideoWatchedResult {
  const YTMarkVideoWatchedResult();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  // === AUTO CLASS START ===
  dynamic get addedAsPending => null;
  // === AUTO CLASS END ===
}






