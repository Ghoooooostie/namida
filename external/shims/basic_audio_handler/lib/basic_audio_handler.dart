// Namida 使用的音频服务引擎，负责播放器状态、配置和队列操作。

library;

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:nampack/nampack.dart';

import 'src/audio_effects.dart';
import 'src/audio_models.dart';
import 'src/av_player.dart';

export 'src/audio_effects.dart';
export 'src/audio_models.dart';
export 'src/av_player.dart';
export 'src/parametric_equalizer.dart';

export 'package:audio_service/audio_service.dart' show MediaItem, MediaButton, MediaAction, BaseAudioHandler;
export 'package:just_audio/just_audio.dart'
    show ProcessingState, PlaybackEvent, AudioLoadConfiguration, UriSource, AudioVideoSource, VideoSourceOptions, VideoInfoData, AudioTrack, TextTrack, HlsSource, DashSource;
export 'package:nampack/nampack.dart' show Rx, Rxn, RxBaseCore, RxMap;

/// ---------------------------------------------------------------- Enums

enum PlayerRepeatMode {
  none,
  one,
  all,
  forNtimes,
  allShuffle,
}

enum InterruptionType {
  unknown,
  shouldDuck,
  shouldPause,
}

enum InterruptionAction {
  doNothing,
  duckAudio,
  pause,
}

/// ---------------------------------------------------------------- Engine

abstract class BasicAudioHandler<Q> extends BaseAudioHandler {
  BasicAudioHandler();

  AVPlayer createPlayerInstance();

  AVPlayer? _player;
  AVPlayer get player {
    final existing = _player;
    if (existing != null) return existing;
    final created = createPlayerInstance();
    _player = created;
    _listenToPlayer(created);
    return created;
  }

  AVPlayer get currentPlayer => player;

  // ---------------- state

  final PlayerQueue<Q> currentQueue = PlayerQueue<Q>();
  final Rx<int> currentIndex = 0.obs;
  final Rxn<Q> currentItem = Rxn<Q>();
  final Rx<int> currentPositionMS = 0.obs;
  final Rx<bool> playWhenReady = false.obs;
  RxBaseCore<Duration?> get currentItemDuration => _currentItemDuration;
  final Rxn<Duration> _currentItemDuration = Rxn<Duration>();
  final Rx<bool> isPlaying = false.obs;
  final Rx<double> currentSpeed = 1.0.obs;
  final Rx<Duration> buffered = Duration.zero.obs;
  final Rxn<ProcessingState> currentState = Rxn<ProcessingState>();
  final Rxn<List<AudioTrack>> audioTracks = Rxn<List<AudioTrack>>();
  final Rxn<List<TextTrack>> textTracks = Rxn<List<TextTrack>>();
  final Rxn<String> subtitleText = Rxn<String>();
  final Rxn<VideoInfoData> videoPlayerInfo = Rxn<VideoInfoData>();
  final Rx<PlayerRepeatMode> _repeatMode = PlayerRepeatMode.none.obs;
  final Rx<int> numberOfRepeats = 1.obs;
  final Rx<bool> isShuffled = false.obs;
  final Rx<SleepTimerConfig> sleepTimerConfig = const SleepTimerConfig().obs;
  RxMap<String, int>? totalListenedTimeInSec;
  void Function(Object error, StackTrace stackTrace)? onVideoError;

  int get androidSessionId => player.androidAudioSessionId ?? 0;
  bool get rendersSubtitlesInternally => player.rendersSubtitlesInternally;
  bool get isShuffleEnabled => isShuffled.value;
  bool get isQueueShuffled => currentQueue.originalIndices != null;
  bool get isLastItem => currentQueue.isEmpty || currentIndex.value >= currentQueue.length - 1;
  double get userPlayerVolumeForItem => _lastAppliedConfig.volume;
  int get latestInsertedIndex => _latestInsertedIndex;
  int _latestInsertedIndex = -1;
  bool get isModifyingQueue => _isModifyingQueue;
  bool _isModifyingQueue = false;
  final Map<String, void Function(double)> _volumeListeners = {};
  PlayerConfig _lastAppliedConfig = PlayerConfig.initial;

  PlayerRepeatMode get currentRepeatMode => _repeatMode.value;

  final List<StreamSubscription<dynamic>> _playerSubscriptions = [];

  /// 订阅当前平台播放器的全部可观察状态。
  void _listenToPlayer(AVPlayer player) {
    void reportError(Object error, StackTrace stackTrace) => onVideoError?.call(error, stackTrace);
    _playerSubscriptions.addAll([
      player.positionStream.listen((position) => currentPositionMS.value = position.inMilliseconds, onError: reportError),
      player.bufferedPositionStream.listen((position) => buffered.value = position, onError: reportError),
      player.processingStateStream.listen((state) => currentState.value = state, onError: reportError),
      player.playingStream.listen((playing) => isPlaying.value = playing, onError: reportError),
      player.speedStream.listen((speed) => currentSpeed.value = speed, onError: reportError),
      player.audioTracksStream.listen((tracks) => audioTracks.value = tracks, onError: reportError),
      player.textTracksStream.listen((tracks) => textTracks.value = tracks, onError: reportError),
      player.subtitleTextStream.listen((text) => subtitleText.value = text, onError: reportError),
      player.videoInfoStream.listen((info) => videoPlayerInfo.value = info, onError: reportError),
      player.playbackEventStream.listen(
        (event) {
          currentState.value = event.processingState;
          buffered.value = event.bufferedPosition;
          onPlaybackEventStream(event);
          if (event.processingState == ProcessingState.completed) onPlaybackCompleted();
        },
        onError: reportError,
      ),
    ]);
  }

  // ---------------- hooks (overridden by namida)

  Object identifyBy(Q element) => element as Object;

  FutureOr<int> itemToDurationInSeconds(Q item) async => 0;

  String? itemToTotalListenTimeKey(Q? item) => null;

  FutureOr<ItemPrepareConfig<Q, UriSource>?> prepareItem(Q item, int index) async => null;

  Future<void> onItemPlay(Q item, int index, Function skipItem, ItemPreparedPlayerInfo<Q>? preparedItemInfo) async {}

  FutureOr<void> onItemMarkedListened(Q item, int listenedSeconds, double listenedPercentage) async {}

  void onIndexChanged(int newIndex, Q newItem) {}

  Future<void> onQueueChanged() async {
    queue.add(await Future.wait(currentQueue.value.map(itemToMediaItem)));
  }

  Future<void> onReorderItems(int currentIndex, Q itemDragged) async {}

  FutureOr<void> beforeQueueAddOrInsert(Iterable<Q> items) async {}

  FutureOr<void> clearQueue() async {
    currentQueue.clear();
    currentIndex.value = 0;
    currentItem.value = null;
    currentPositionMS.value = 0;
    _currentItemDuration.value = null;
    mediaItem.add(null);
    queue.add(const []);
  }

  Future<void>? beforeSkippingToItem() => null;

  FutureOr<void> onItemLastPositionReport(Q? currentItem, int currentPositionMs) async {}

  void onPlaybackEventStream(PlaybackEvent event) {}

  /// 把平台播放事件转换成 audio_service 通知栏状态。
  PlaybackState transformEvent(PlaybackEvent event, [bool isFavourite = false, int? itemIndex]) {
    final state = switch (event.processingState) {
      ProcessingState.idle => AudioProcessingState.idle,
      ProcessingState.loading => AudioProcessingState.loading,
      ProcessingState.buffering => AudioProcessingState.buffering,
      ProcessingState.ready => AudioProcessingState.ready,
      ProcessingState.completed => AudioProcessingState.completed,
    };
    return playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        isPlaying.value ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
        if (displayStopButtonInNotification) MediaControl.stop,
      ],
      systemActions: const {MediaAction.seek, MediaAction.seekForward, MediaAction.seekBackward},
      processingState: state,
      playing: isPlaying.value,
      updatePosition: event.updatePosition,
      bufferedPosition: event.bufferedPosition,
      speed: currentSpeed.value,
      queueIndex: itemIndex ?? currentIndex.value,
      repeatMode: switch (displayRepeatMode) {
        PlayerRepeatMode.none => AudioServiceRepeatMode.none,
        PlayerRepeatMode.one || PlayerRepeatMode.forNtimes => AudioServiceRepeatMode.one,
        PlayerRepeatMode.all => AudioServiceRepeatMode.all,
        PlayerRepeatMode.allShuffle => AudioServiceRepeatMode.group,
      },
      shuffleMode: isQueueShuffled ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
    );
  }

  Future<void> onPlaybackCompleted() async {}

  void onRepeatModeChange(PlayerRepeatMode repeatMode) {}

  void onShuffleModeChange(bool shuffled) {}

  void onNotificationFavouriteButtonPressed(Q item) {}

  void onTotalListenTimeIncrease(Map<String, int> totalTimeInSeconds, String key) {}

  Future<void> setSkipSilenceEnabled(bool enabled) async => player.setSkipSilenceEnabled(enabled);

  FutureOr<void> ensureReplayGainVolumeUpdated(Q? item) async {}

  FutureOr<PlayerConfig?> getPlayerConfigForItem(Q? item, AVPlayer player) async => null;

  PlayerConfig getDefaultPlayerConfig(Q? item) => PlayerConfig.initial;

  Future<MediaItem> itemToMediaItem(Q item) async => MediaItem(id: itemToMediaItemId(item), title: itemToMediaItemId(item));

  String itemToMediaItemId(Q item) => identifyBy(item).toString();

  Future<Map<String, int>> prepareTotalListenTime() async {
    final prepared = <String, int>{};
    totalListenedTimeInSec = prepared.obs;
    return prepared;
  }

  bool getLoudnessEnhancerEnabledTrackValue() => false;

  bool getLoudnessEnhancerEnabledTrackValueR() => false;

  double get replayGainLinearVolumeMultiplierValue => 1.0;

  InterruptionAction defaultOnInterruption(InterruptionType type) => InterruptionAction.pause;

  InterruptionAction get onBecomingNoisyEventStream => InterruptionAction.pause;

  Duration get defaultInterruptionResumeThreshold => const Duration(seconds: 5);

  Duration get defaultVolume0ResumeThreshold => const Duration(seconds: 5);

  Duration get defaultConnectWiredResumeThresholdMin => const Duration(minutes: 1);

  Duration get defaultConnectWirelessResumeThresholdMin => const Duration(minutes: 1);

  AudioLoadConfiguration? get defaultAndroidLoadConfig => null;

  MediaControlsProvider get mediaControls => const MediaControlsProvider();

  late final EqualizerExtended _equalizerExtended = EqualizerExtended(() => player);
  late final LoudnessEnhancerExtended _loudnessEnhancerExtended = LoudnessEnhancerExtended(() => player, getLoudnessEnhancerEnabledTrackValue);

  EqualizerExtended? get equalizerExtended => _equalizerExtended;

  LoudnessEnhancerExtended? get loudnessEnhancerExtended => _loudnessEnhancerExtended;

  // ---------------- playback settings hooks

  bool get enableCrossFade => false;
  bool get defaultGaplessEnabled => false;
  int get defaultCrossFadeMilliseconds => 0;
  int get defaultCrossFadeTriggerStartOffsetSeconds => 0;
  bool get displayFavouriteButtonInNotification => true;
  bool get displayFavouriteButtonAsLikeInNotification => false;
  bool get displayStopButtonInNotification => true;
  bool get defaultShouldStartPlayingOnNextPrev => true;
  bool get enableVolumeFadeOnPlayPause => false;
  bool get playerInfiniyQueueOnNextPrevious => false;
  int get playerPauseFadeDurInMilli => 0;
  int get playerPlayFadeDurInMilli => 0;
  bool get playerPauseOnVolume0 => false;
  PlayerRepeatMode get playerRepeatMode => _repeatMode.value;
  PlayerRepeatMode get displayRepeatMode => _repeatMode.value;
  bool get jumpToFirstItemAfterFinishingQueue => false;
  int get listenCounterMarkPlayedPercentage => 50;
  int get listenCounterMarkPlayedSeconds => 30;
  int get maximumSleepTimerMins => 120;
  int get maximumSleepTimerItems => 100;

  // ---------------- transport

  Future<void> onPlayRaw({bool attemptFixVolume = true}) async {
    playWhenReady.value = true;
    await player.play();
    isPlaying.value = true;
    playbackState.add(
      playbackState.value.copyWith(
        playing: true,
        processingState: AudioProcessingState.ready,
        controls: [
          MediaControl.pause,
          MediaControl.skipToNext,
          MediaControl.skipToPrevious,
        ],
        systemActions: const {MediaAction.seek},
        updatePosition: player.position,
      ),
    );
  }

  Future<void> onPauseRaw() async {
    playWhenReady.value = false;
    await player.pause();
    isPlaying.value = false;
    playbackState.add(
      playbackState.value.copyWith(
        playing: false,
        processingState: AudioProcessingState.ready,
        controls: [
          MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.skipToPrevious,
        ],
        systemActions: const {MediaAction.seek},
        updatePosition: player.position,
      ),
    );
  }

  Future<void> setPlayWhenReady(bool value) async {
    playWhenReady.value = value;
    if (value) {
      await onPlayRaw();
    } else {
      await onPauseRaw();
    }
  }

  @override
  Future<void> play({bool checkIfPlaybackEnded = true}) async {
    if (checkIfPlaybackEnded && currentState.value == ProcessingState.completed) {
      await seek(Duration.zero);
    }
    await onPlayRaw();
  }

  @override
  Future<void> pause({bool isUserInitiated = true}) async => await onPauseRaw();

  Future<void> togglePlayPause() async {
    if (playWhenReady.value) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> userPlay() => play();

  Future<void> userPause() => pause();

  Future<void> userTogglePlayPause() => togglePlayPause();

  @override
  Future<void> seek(Duration position) async {
    final resolved = position < Duration.zero ? Duration.zero : position;
    await player.seek(resolved);
    _seekCount++;
    _lastSeekPositionMS = resolved.inMilliseconds;
    currentPositionMS.value = resolved.inMilliseconds;
    playbackState.add(playbackState.value.copyWith(updatePosition: resolved));
  }

  Future<void> userSeek(Duration position) => seek(position);

  int get seekCount => _seekCount;
  int _seekCount = 0;
  int get lastSeekPositionMS => _lastSeekPositionMS;
  int _lastSeekPositionMS = 0;

  @override
  Future<void> fastForward() async => await onFastForward();

  @override
  Future<void> rewind() async => await onRewind();

  Future<void> onFastForward() async {
    final d = player.duration;
    if (d == null) return;
    await seek(player.position + const Duration(seconds: 10) < d ? player.position + const Duration(seconds: 10) : d);
  }

  Future<void> onRewind() async {
    final p = player.position - const Duration(seconds: 10);
    await seek(p < Duration.zero ? Duration.zero : p);
  }

  /// 应用当前项目的音量、速度、音调和 DSP 配置。
  Future<void> refreshCurrentItemPlayerConfig() async {
    final config = await getPlayerConfigForItem(currentItem.value, player) ?? getDefaultPlayerConfig(currentItem.value);
    _lastAppliedConfig = config;
    await setVolumeWithMultiplier(config.volume);
    await setPlayerSpeed(config.speed);
    await setPlayerPitch(config.pitch);
    await setSkipSilenceEnabled(config.skipSilence);
    await equalizerExtended?.apply(config.equalizerEnabled, config.equalizer);
    final loudness = loudnessEnhancerExtended;
    if (loudness != null) {
      await loudness.setTargetGainUser(config.loudnessEnhancer);
      await loudness.setEnabledUser(config.loudnessEnhancerEnabled);
    }
  }

  /// 按回放增益倍率设置实际播放器音量。
  Future<void> setVolumeWithMultiplier(double volume) async {
    _lastAppliedConfig = _lastAppliedConfig.copyWith(volume: volume);
    final actual = (volume * replayGainLinearVolumeMultiplierValue).clamp(0.0, 1.0).toDouble();
    await player.setVolume(actual);
    for (final listener in _volumeListeners.values) {
      listener(actual);
    }
  }

  Future<void> refreshVolumeForReplayGain() => setVolumeWithMultiplier(userPlayerVolumeForItem);

  Future<void> setPlayerPitch(double value) async {
    _lastAppliedConfig = _lastAppliedConfig.copyWith(pitch: value);
    await player.setPitch(value);
  }

  Future<void> setPlayerSpeed(double value) async {
    _lastAppliedConfig = _lastAppliedConfig.copyWith(speed: value);
    currentSpeed.value = value;
    await player.setSpeed(value);
  }

  void onVolumeChangeAddListener(String key, void Function(double musicVolume) listener) => _volumeListeners[key] = listener;

  void onVolumeChangeRemoveListener(String key) => _volumeListeners.remove(key);

  Future<void> executeWithPausedOutput(Future<void> Function() action) async {
    final wasPlaying = isPlaying.value;
    if (wasPlaying) await player.pause();
    try {
      await action();
    } finally {
      if (wasPlaying) await player.play();
    }
  }

  Future<void> executeOnPlayers(Future<void> Function(AVPlayer player) action) => action(player);

  Future<void> setVideo(VideoSourceOptions? video) => player.setVideo(video);

  Future<Duration?> setAudioSource<T>(ItemPrepareConfig<T, UriSource> config) => player.setSource(config);

  Future<void> setAudioTrack(String? trackId) => player.setAudioTrack(trackId);

  Future<void> setTextTrack(String? trackId) => player.setTextTrack(trackId);

  Future<bool> setExternalSubtitle(String? subtitlePath) => player.setExternalSubtitle(subtitlePath);

  /// Plays [index] from the current queue.
  Future<void> playIndex(int index, {Duration? startPosition}) async {
    if (currentQueue.isEmpty) return;
    if (index < 0 || index >= currentQueue.length) return;

    final item = currentQueue[index];
    final prepared = await prepareItem(item, index);
    if (prepared == null) return;

    currentIndex.value = index;
    currentItem.value = item;
    onIndexChanged(index, item);
    mediaItem.add(await itemToMediaItem(item));

    final config = startPosition == null
        ? prepared
        : ItemPrepareConfig<Q, UriSource>(
            prepared.source,
            index: prepared.index,
            initialPosition: startPosition,
            videoOptions: prepared.videoOptions,
            audioTrackId: prepared.audioTrackId,
            item: prepared.item,
            itemExists: prepared.itemExists,
            keepOldVideoSource: prepared.keepOldVideoSource,
          );
    await onItemPlay(item, index, () => skipToNext(), ItemPreparedPlayerInfo(config: config));
    await refreshCurrentItemPlayerConfig();

    if (playWhenReady.value) await onPlayRaw();
  }

  @override
  Future<void> skipToNext() async {
    await playIndex(_nextIndex(1));
  }

  Future<void> userSkipToNext() => skipToNext();

  @override
  Future<void> skipToPrevious({bool isManualSkip = true}) async {
    await playIndex(_nextIndex(-1));
  }

  Future<void> userSkipToPrevious() => skipToPrevious();

  @override
  Future<void> skipToQueueItem(int index, {bool isManualSkip = true}) async {
    await beforeSkippingToItem();
    await playIndex(index);
  }

  Future<void> userSkipToQueueItem(int index) => skipToQueueItem(index);

  bool get previousButtonWillReplay => currentPositionMS.value > 5000;

  int _nextIndex(int delta) {
    final len = currentQueue.length;
    if (len == 0) return 0;
    final next = currentIndex.value + delta;
    if (next < 0) return jumpToFirstItemAfterFinishingQueue || _repeatMode.value != PlayerRepeatMode.none ? len - 1 : 0;
    if (next >= len) return _repeatMode.value == PlayerRepeatMode.none ? 0 : 0;
    return next;
  }

  Future<void> _setPlayerRepeatMode(PlayerRepeatMode mode, {int? times}) async {
    _repeatMode.value = mode;
    if (times != null) numberOfRepeats.value = times;
    onRepeatModeChange(mode);
  }

  void userSetRepeatMode(PlayerRepeatMode mode, {int? times}) => _setPlayerRepeatMode(mode, times: times);

  PlayerRepeatMode userCycleRepeatMode() {
    final values = PlayerRepeatMode.values;
    final next = values[(values.indexOf(currentRepeatMode) + 1) % values.length];
    userSetRepeatMode(next);
    return next;
  }

  void updateNumberOfRepeats(int times) {
    numberOfRepeats.value = times < 1 ? 1 : times;
  }

  Future<void> setShuffleModeEnabled(bool enabled) async {
    isShuffled.value = enabled;
    onShuffleModeChange(enabled);
  }

  Future<void> setQueueShuffled(bool enabled) async {
    if (enabled == isQueueShuffled || currentQueue.length < 2) return;
    if (enabled) {
      final current = currentItem.value;
      final indexed = [for (var i = 0; i < currentQueue.length; i++) (item: currentQueue[i], index: i)];
      indexed.shuffle();
      if (current != null) {
        final playingIndex = indexed.indexWhere((entry) => identifyBy(entry.item) == identifyBy(current));
        if (playingIndex > 0) {
          final playing = indexed.removeAt(playingIndex);
          indexed.insert(0, playing);
        }
      }
      currentQueue.assign(indexed.map((entry) => entry.item), originalIndices: indexed.map((entry) => entry.index).toList());
      currentIndex.value = current == null ? 0 : currentQueue.indexWhere((item) => identifyBy(item) == identifyBy(current));
    } else {
      final indices = currentQueue.originalIndices;
      if (indices == null || indices.length != currentQueue.length) return;
      final current = currentItem.value;
      final restored = List<Q?>.filled(currentQueue.length, null);
      for (var i = 0; i < currentQueue.length; i++) {
        final target = indices[i];
        if (target < 0 || target >= restored.length || restored[target] != null) {
          throw StateError('Invalid original queue indices');
        }
        restored[target] = currentQueue[i];
      }
      currentQueue.assign(restored.cast<Q>());
      currentIndex.value = current == null ? 0 : currentQueue.indexWhere((item) => identifyBy(item) == identifyBy(current));
    }
    isShuffled.value = enabled;
    await onQueueChanged();
    onShuffleModeChange(enabled);
  }

  void refreshPlaybackStateModes() {
    playbackState.add(transformEvent(PlaybackEvent(processingState: currentState.value ?? ProcessingState.idle)));
  }

  int? sleepingItemIndex(int sleepAfterItems, int currentIndex) {
    if (sleepAfterItems <= 0) return null;
    final target = currentIndex + sleepAfterItems;
    return target < currentQueue.length ? target : null;
  }

  Timer? _sleepTimer;

  void updateSleepTimerValues({bool? enableSleepAfterItems, bool? enableSleepAfterMins, int? sleepAfterMin, int? sleepAfterItems}) {
    final updated = sleepTimerConfig.value.copyWith(
      enableSleepAfterItems: enableSleepAfterItems,
      enableSleepAfterMins: enableSleepAfterMins,
      sleepAfterMin: sleepAfterMin,
      sleepAfterItems: sleepAfterItems,
    );
    sleepTimerConfig.value = updated;
    _sleepTimer?.cancel();
    if (updated.enableSleepAfterMins && updated.sleepAfterMin > 0) {
      _sleepTimer = Timer(Duration(minutes: updated.sleepAfterMin), userPause);
    }
  }

  void resetSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    sleepTimerConfig.value = const SleepTimerConfig();
  }

  // ---------------- queue editing (used by namida UI)

  void invokeQueueModifyLock() => _isModifyingQueue = true;

  void invokeQueueModifyLockRelease({bool isCanceled = false}) {
    _isModifyingQueue = false;
    if (!isCanceled) currentQueue.refresh();
  }

  Future<void> resetGaplessPlaybackData() => player.removeAllMediaNext();

  int? shufflePeekPreviousIndex() => currentIndex.value > 0 ? currentIndex.value - 1 : null;

  int? shuffleNextIndex() => currentIndex.value + 1 < currentQueue.length ? currentIndex.value + 1 : null;

  Future<void> assignNewQueue<Id>({
    required int playAtIndex,
    required Iterable<Q> queue,
    bool shuffle = false,
    bool shuffleKeepingItem = false,
    List<int>? originalIndices,
    bool startPlaying = true,
    int? maximumItems,
    void Function()? onQueueEmpty,
    void Function()? onIndexAndQueueSame,
    void Function(List<Q> finalizedQueue, List<int>? originalIndices)? onQueueDifferent,
    void Function(Q currentItem)? onAssigningCurrentItem,
    bool Function(Q? currentItem, Q itemToPlay)? canRestructureQueueOnly,
    void Function()? onRestructuringQueue,
    Id Function(Q currentItem)? duplicateRemover,
  }) async {
    var finalized = List<Q>.of(queue);
    if (duplicateRemover != null) {
      final seen = <Id>{};
      finalized = [
        for (final item in finalized)
          if (seen.add(duplicateRemover(item))) item,
      ];
    }
    if (maximumItems != null && maximumItems >= 0 && finalized.length > maximumItems) {
      finalized = finalized.take(maximumItems).toList();
    }
    if (finalized.isEmpty) {
      onQueueEmpty?.call();
      await clearQueue();
      return;
    }
    final boundedIndex = playAtIndex.clamp(0, finalized.length - 1);
    var targetItem = finalized[boundedIndex];
    if (currentQueue.length == finalized.length &&
        currentIndex.value == boundedIndex &&
        List<bool>.generate(finalized.length, (index) => identifyBy(currentQueue[index]) == identifyBy(finalized[index])).every((same) => same)) {
      onIndexAndQueueSame?.call();
      return;
    }
    List<int>? indices = originalIndices == null ? null : List<int>.of(originalIndices);
    var targetIndex = boundedIndex;
    if (shuffle) {
      final indexed = [for (var i = 0; i < finalized.length; i++) (item: finalized[i], index: i)]..shuffle();
      if (shuffleKeepingItem) {
        final index = indexed.indexWhere((entry) => identifyBy(entry.item) == identifyBy(targetItem));
        final selected = indexed.removeAt(index);
        indexed.insert(0, selected);
      }
      finalized = indexed.map((entry) => entry.item).toList();
      indices = indexed.map((entry) => entry.index).toList();
      targetIndex = finalized.indexWhere((item) => identifyBy(item) == identifyBy(targetItem));
    }
    if (canRestructureQueueOnly?.call(currentItem.value, targetItem) == true) onRestructuringQueue?.call();
    onQueueDifferent?.call(finalized, indices);
    currentQueue.assign(finalized, originalIndices: indices);
    await onQueueChanged();
    currentIndex.value = targetIndex;
    targetItem = finalized[targetIndex];
    onAssigningCurrentItem?.call(targetItem);
    playWhenReady.value = startPlaying;
    await playIndex(targetIndex, startPosition: _takeRequestedStartPosition(targetItem));
  }

  final Map<Object, Duration> _requestedStartPositions = {};

  void requestStartPosition(Q item, Duration position) => _requestedStartPositions[identifyBy(item)] = position;

  Duration? _takeRequestedStartPosition(Q item) => _requestedStartPositions.remove(identifyBy(item));

  void discardRequestedStartPosition() => _requestedStartPositions.clear();

  FutureOr<void> addToQueue(Iterable<Q> items, {bool insertNext = false, bool insertAfterLatest = false}) async {
    final additions = List<Q>.of(items);
    if (additions.isEmpty) return;
    await beforeQueueAddOrInsert(additions);
    final index = insertNext
        ? currentIndex.value + 1
        : insertAfterLatest && _latestInsertedIndex >= currentIndex.value
        ? _latestInsertedIndex + 1
        : currentQueue.length;
    currentQueue.insertAll(index.clamp(0, currentQueue.length), additions);
    _latestInsertedIndex = index + additions.length - 1;
    await onQueueChanged();
  }

  FutureOr<void> insertInQueue(Iterable<Q> items, int index) async {
    final additions = List<Q>.of(items);
    if (additions.isEmpty) return;
    await beforeQueueAddOrInsert(additions);
    final bounded = index.clamp(0, currentQueue.length);
    currentQueue.insertAll(bounded, additions);
    if (bounded <= currentIndex.value) currentIndex.value += additions.length;
    _latestInsertedIndex = bounded + additions.length - 1;
    await onQueueChanged();
  }

  Future<bool> moveToNext(int index) => _moveItem(index, currentIndex.value + 1);

  Future<bool> moveToAfterLatestInserted(int index) => _moveItem(index, (_latestInsertedIndex + 1).clamp(0, currentQueue.length - 1));

  Future<bool> moveToLast(int index) => _moveItem(index, currentQueue.length - 1);

  Future<bool> _moveItem(int from, int to) async {
    if (from < 0 || from >= currentQueue.length || to < 0 || to >= currentQueue.length || from == to) return false;
    final item = currentQueue.value.removeAt(from);
    currentQueue.value.insert(to, item);
    final playingItem = currentItem.value;
    currentQueue.refresh();
    if (playingItem != null) currentIndex.value = currentQueue.indexWhere((entry) => identifyBy(entry) == identifyBy(playingItem));
    await onQueueChanged();
    return true;
  }

  FutureOr<void> reorderItems(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= currentQueue.length) return;
    var target = newIndex;
    if (target > oldIndex) target--;
    target = target.clamp(0, currentQueue.length - 1);
    final item = currentQueue.value.removeAt(oldIndex);
    currentQueue.value.insert(target, item);
    final playingItem = currentItem.value;
    currentQueue.refresh();
    if (playingItem != null) currentIndex.value = currentQueue.indexWhere((entry) => identifyBy(entry) == identifyBy(playingItem));
    await onReorderItems(currentIndex.value, item);
    await onQueueChanged();
  }

  Future<void> shuffleAllItems() async {
    if (currentQueue.length < 2) return;
    final current = currentItem.value;
    currentQueue.value.shuffle();
    currentQueue.refresh();
    if (current != null) currentIndex.value = currentQueue.indexWhere((item) => identifyBy(item) == identifyBy(current));
    await onQueueChanged();
  }

  Future<void> shuffleNextItems() async {
    final start = currentIndex.value + 1;
    if (start >= currentQueue.length - 1) return;
    final next = currentQueue.value.sublist(start)..shuffle();
    currentQueue.value.replaceRange(start, currentQueue.length, next);
    currentQueue.refresh();
    await onQueueChanged();
  }

  int removeDuplicatesFromQueue() {
    final seen = <Object>{};
    final before = currentQueue.length;
    final current = currentItem.value;
    currentQueue.value.removeWhere((item) => !seen.add(identifyBy(item)));
    final removed = before - currentQueue.length;
    if (removed > 0) {
      currentQueue.refresh();
      if (current != null) currentIndex.value = currentQueue.indexWhere((item) => identifyBy(item) == identifyBy(current));
      onQueueChanged();
    }
    return removed;
  }

  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= currentQueue.length) return;
    final removedCurrent = index == currentIndex.value;
    currentQueue.removeAt(index);
    if (currentQueue.isEmpty) {
      currentItem.value = null;
      currentIndex.value = 0;
    } else if (index < currentIndex.value) {
      currentIndex.value--;
    } else if (removedCurrent) {
      currentIndex.value = currentIndex.value.clamp(0, currentQueue.length - 1);
      await playIndex(currentIndex.value);
    }
    await onQueueChanged();
  }

  Future<void> replaceAllItemsInQueue(Q oldItem, Q newItem) async {
    var changed = false;
    for (var i = 0; i < currentQueue.length; i++) {
      if (currentQueue[i] == oldItem) {
        currentQueue.value[i] = newItem;
        changed = true;
      }
    }
    if (!changed) return;
    if (currentItem.value == oldItem) currentItem.value = newItem;
    currentQueue.refresh();
    await onQueueChanged();
  }

  Future<void> replaceAllItemsInQueueBulk(Map<Q, Q> replacements) async {
    var changed = false;
    for (var i = 0; i < currentQueue.length; i++) {
      final replacement = replacements[currentQueue[i]];
      if (replacement != null) {
        currentQueue.value[i] = replacement;
        changed = true;
      }
    }
    if (!changed) return;
    final current = currentItem.value;
    if (current != null) currentItem.value = replacements[current] ?? current;
    currentQueue.refresh();
    await onQueueChanged();
  }

  Future<void> replaceWhereInQueue(bool Function(Q item) test, Q Function(Q oldItem) replacement) async {
    var changed = false;
    for (var i = 0; i < currentQueue.length; i++) {
      final item = currentQueue[i];
      if (test(item)) {
        currentQueue.value[i] = replacement(item);
        changed = true;
      }
    }
    if (!changed) return;
    currentQueue.refresh();
    await onQueueChanged();
  }

  int removeRangeFromQueue(int start, int end) {
    final boundedStart = start.clamp(0, currentQueue.length);
    final boundedEnd = end.clamp(boundedStart, currentQueue.length);
    final removed = boundedEnd - boundedStart;
    if (removed == 0) return 0;
    currentQueue.removeRange(boundedStart, boundedEnd);
    currentIndex.value = currentIndex.value.clamp(0, currentQueue.isEmpty ? 0 : currentQueue.length - 1);
    onQueueChanged();
    return removed;
  }

  int removeAllPrevious() {
    final removed = currentIndex.value.clamp(0, currentQueue.length);
    if (removed > 0) {
      currentQueue.removeRange(0, removed);
      currentIndex.value = 0;
      onQueueChanged();
    }
    return removed;
  }

  int removeAllNext() {
    final start = (currentIndex.value + 1).clamp(0, currentQueue.length);
    final removed = currentQueue.length - start;
    if (removed > 0) {
      currentQueue.removeRange(start, currentQueue.length);
      onQueueChanged();
    }
    return removed;
  }

  int removeAllExceptCurrent() => removeAllNext() + removeAllPrevious();

  void refreshRxVariables() {
    currentQueue.queueRx.refresh();
    currentIndex.refresh();
    currentItem.refresh();
    currentPositionMS.refresh();
    playWhenReady.refresh();
  }

  void beginEarlyCrossFadeOutIfRequired() {}

  void startCounterToAListen(Q item) {}

  // ---------------- lifecycle

  Future<void> onDispose() async {
    final subscriptions = List<StreamSubscription<dynamic>>.of(_playerSubscriptions);
    _playerSubscriptions.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    final existing = _player;
    _player = null;
    if (existing != null) await existing.dispose();
    isPlaying.value = false;
    currentState.value = ProcessingState.idle;
  }

  @override
  Future<void> stop() async {
    await player.stop();
    playWhenReady.value = false;
    isPlaying.value = false;
    await super.stop();
  }
}
