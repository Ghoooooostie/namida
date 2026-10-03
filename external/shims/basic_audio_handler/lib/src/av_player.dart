// 播放器平台抽象以及 just_audio 的强类型适配器。
import 'package:just_audio/just_audio.dart';

import 'parametric_equalizer.dart';

class ItemPrepareConfig<Q, S extends UriSource> {
  final S source;
  final int index;
  final Duration? initialPosition;
  final VideoSourceOptions? videoOptions;
  final String? audioTrackId;
  final Q? item;
  final bool itemExists;
  final bool keepOldVideoSource;

  const ItemPrepareConfig(
    this.source, {
    required this.index,
    required this.initialPosition,
    required this.videoOptions,
    required this.audioTrackId,
    this.item,
    this.itemExists = true,
    this.keepOldVideoSource = false,
  });
}

class ItemPreparedPlayerInfo<Q> {
  final ItemPrepareConfig<Q, UriSource> config;
  final Duration? duration;

  const ItemPreparedPlayerInfo({required this.config, this.duration});

  Q? get item => config.item;
}

abstract class AVPlayer {
  Stream<PlaybackEvent> get playbackEventStream;
  Stream<Duration> get positionStream;
  Stream<Duration> get bufferedPositionStream;
  Stream<Duration?> get durationStream;
  Stream<ProcessingState> get processingStateStream;
  Stream<bool> get playingStream;
  Stream<double> get volumeStream;
  Stream<double> get speedStream;
  Stream<double> get pitchStream;
  Stream<List<AudioTrack>?> get audioTracksStream;
  Stream<List<TextTrack>?> get textTracksStream;
  Stream<String?> get subtitleTextStream;
  Stream<VideoInfoData> get videoInfoStream;

  Duration get position;
  Duration get bufferedPosition;
  Duration? get duration;
  bool get playing;
  double get volume;
  double get speed;
  double get pitch;
  ProcessingState get processingState;
  UriSource? get audioSource;
  bool get isDisposed;
  bool get hasVideoOptions;
  bool get rendersSubtitlesInternally;
  int? get androidAudioSessionId;

  Future<Duration?> setSource<T>(ItemPrepareConfig<T, UriSource> config);
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> freePlayer();
  Future<void> seek(Duration? position);
  Future<void> setVolume(double volume);
  Future<void> setSpeed(double speed);
  Future<void> setPitch(double pitch);
  Future<void> setSkipSilenceEnabled(bool enabled);
  Future<void> setVideo(VideoSourceOptions? video);
  Future<void> setAudioTrack(String? trackId);
  Future<void> setTextTrack(String? trackId);
  Future<bool> setExternalSubtitle(String? subtitlePath);
  Future<void> setEqualizer(ParametricEqualizer? equalizer);
  Future<void> setLoudnessEnhancerEnabled(bool enabled);
  Future<void> setLoudnessEnhancerGain(double gainDb);
  Future<bool> addMediaNext<T>(ItemPrepareConfig<T, UriSource> config);
  Future<void> removeAllMediaNext();
  Future<void> setAudioOutput(String? deviceId, {required bool bitPerfect, required bool mono});
  Future<void> dispose();
}

class CustomAudioPlayer implements AVPlayer {
  final AudioPlayer player;

  CustomAudioPlayer(this.player);

  @override
  Stream<PlaybackEvent> get playbackEventStream => player.playbackEventStream;
  @override
  Stream<Duration> get positionStream => player.positionStream;
  @override
  Stream<Duration> get bufferedPositionStream => player.bufferedPositionStream;
  @override
  Stream<Duration?> get durationStream => player.durationStream;
  @override
  Stream<ProcessingState> get processingStateStream => player.processingStateStream;
  @override
  Stream<bool> get playingStream => player.playingStream;
  @override
  Stream<double> get volumeStream => player.volumeStream;
  @override
  Stream<double> get speedStream => player.speedStream;
  @override
  Stream<double> get pitchStream => player.pitchStream;
  @override
  Stream<List<AudioTrack>?> get audioTracksStream => player.audioTracksStream;
  @override
  Stream<List<TextTrack>?> get textTracksStream => player.textTracksStream;
  @override
  Stream<String?> get subtitleTextStream => player.subtitleTextStream;
  @override
  Stream<VideoInfoData> get videoInfoStream => player.videoInfoStream;

  @override
  Duration get position => player.position;
  @override
  Duration get bufferedPosition => player.bufferedPosition;
  @override
  Duration? get duration => player.duration;
  @override
  bool get playing => player.playing;
  @override
  double get volume => player.volume;
  @override
  double get speed => player.speed;
  @override
  double get pitch => player.pitch;
  @override
  ProcessingState get processingState => player.processingState;
  @override
  UriSource? get audioSource => player.audioSource as UriSource?;
  @override
  bool get isDisposed => player.isDisposed;
  @override
  bool get hasVideoOptions => player.videoOptions != null;
  @override
  bool get rendersSubtitlesInternally => false;
  @override
  int? get androidAudioSessionId => player.androidAudioSessionId;

  /// 把统一加载配置转交给 just_audio。
  @override
  Future<Duration?> setSource<T>(ItemPrepareConfig<T, UriSource> config) {
    return player.setSource(
      config.source,
      initialPosition: config.initialPosition,
      videoOptions: config.videoOptions,
      audioTrackId: config.audioTrackId,
      keepOldVideoSource: config.keepOldVideoSource,
    );
  }

  @override
  Future<void> play() => player.play();
  @override
  Future<void> pause() => player.pause();
  @override
  Future<void> stop() => player.stop();
  @override
  Future<void> freePlayer() => player.freePlayer();
  @override
  Future<void> seek(Duration? position) => player.seek(position);
  @override
  Future<void> setVolume(double volume) => player.setVolume(volume);
  @override
  Future<void> setSpeed(double speed) => player.setSpeed(speed);
  @override
  Future<void> setPitch(double pitch) => player.setPitch(pitch);
  @override
  Future<void> setSkipSilenceEnabled(bool enabled) => player.setSkipSilenceEnabled(enabled);
  @override
  Future<void> setVideo(VideoSourceOptions? video) => player.setVideo(video);
  @override
  Future<void> setAudioTrack(String? trackId) => player.setAudioTrack(trackId);
  @override
  Future<void> setTextTrack(String? trackId) => player.setTextTrack(trackId);

  /// just_audio 当前不支持外部字幕，明确返回加载失败。
  @override
  Future<bool> setExternalSubtitle(String? subtitlePath) async => subtitlePath == null;

  /// Android 参数均衡器由 AudioPipeline 中的效果器应用。
  @override
  Future<void> setEqualizer(ParametricEqualizer? equalizer) async {}

  /// Android 响度开关由 AudioPipeline 中的效果器应用。
  @override
  Future<void> setLoudnessEnhancerEnabled(bool enabled) async {}

  /// Android 响度增益由 AudioPipeline 中的效果器应用。
  @override
  Future<void> setLoudnessEnhancerGain(double gainDb) async {}

  /// just_audio 单源模式不预加载下一项。
  @override
  Future<bool> addMediaNext<T>(ItemPrepareConfig<T, UriSource> config) async => false;

  /// just_audio 单源模式没有待移除的预加载项。
  @override
  Future<void> removeAllMediaNext() async {}

  /// 默认输出使用系统路由；非默认请求必须由支持该能力的播放器处理。
  @override
  Future<void> setAudioOutput(String? deviceId, {required bool bitPerfect, required bool mono}) async {
    if (deviceId != null || bitPerfect || mono) {
      throw UnsupportedError('just_audio does not support selecting this audio output');
    }
  }

  @override
  Future<void> dispose() => player.dispose();
}
