// 音频处理器的持久化配置、队列状态和通知栏模型。
import 'dart:collection';

import 'package:audio_service/audio_service.dart';
import 'package:nampack/nampack.dart';

import 'parametric_equalizer.dart';

enum PlayerConfigModificationScale { none, main, alt }

class PlayerConfig {
  static const bool isSkipSilenceSupported = true;
  static const bool isEqualizerSupported = true;
  static const bool isLoudnessEnhancerSupported = true;
  static const _unset = Object();

  static const initial = PlayerConfig();

  final double volume;
  final double speed;
  final double pitch;
  final bool skipSilence;
  final bool loudnessEnhancerEnabled;
  final double loudnessEnhancer;
  final bool equalizerEnabled;
  final ParametricEqualizer equalizer;
  final EqualizerPreset? preset;
  final int modifiedDate;

  const PlayerConfig({
    this.volume = 1.0,
    this.speed = 1.0,
    this.pitch = 1.0,
    this.skipSilence = false,
    this.loudnessEnhancerEnabled = false,
    this.loudnessEnhancer = 0.0,
    this.equalizerEnabled = false,
    this.equalizer = ParametricEqualizer.flat,
    this.preset,
    this.modifiedDate = 0,
  });

  /// 从数据库映射恢复播放器配置。
  factory PlayerConfig.fromMap(Map<String, dynamic> map) {
    return PlayerConfig(
      volume: (map['volume'] as num?)?.toDouble() ?? 1.0,
      speed: (map['speed'] as num?)?.toDouble() ?? 1.0,
      pitch: (map['pitch'] as num?)?.toDouble() ?? 1.0,
      skipSilence: map['skipSilence'] as bool? ?? false,
      loudnessEnhancerEnabled: map['loudnessEnhancerEnabled'] as bool? ?? false,
      loudnessEnhancer: (map['loudnessEnhancer'] as num?)?.toDouble() ?? 0.0,
      equalizerEnabled: map['equalizerEnabled'] as bool? ?? false,
      equalizer: ParametricEqualizer.fromMap(map['equalizer']) ?? ParametricEqualizer.flat,
      preset: EqualizerPreset.fromMap(map['preset']),
      modifiedDate: (map['modifiedDate'] as num?)?.toInt() ?? 0,
    );
  }

  /// 生成只替换指定字段的新配置。
  PlayerConfig copyWith({
    double? volume,
    double? speed,
    double? pitch,
    bool? skipSilence,
    bool? loudnessEnhancerEnabled,
    double? loudnessEnhancer,
    bool? equalizerEnabled,
    ParametricEqualizer? equalizer,
    Object? preset = _unset,
    int? modifiedDate,
  }) {
    return PlayerConfig(
      volume: volume ?? this.volume,
      speed: speed ?? this.speed,
      pitch: pitch ?? this.pitch,
      skipSilence: skipSilence ?? this.skipSilence,
      loudnessEnhancerEnabled: loudnessEnhancerEnabled ?? this.loudnessEnhancerEnabled,
      loudnessEnhancer: loudnessEnhancer ?? this.loudnessEnhancer,
      equalizerEnabled: equalizerEnabled ?? this.equalizerEnabled,
      equalizer: equalizer ?? this.equalizer,
      preset: identical(preset, _unset) ? this.preset : preset as EqualizerPreset?,
      modifiedDate: modifiedDate ?? this.modifiedDate,
    );
  }

  /// 更新均衡器和预设的便捷方法。
  PlayerConfig copyWithEqualizer(ParametricEqualizer equalizer, EqualizerPreset? preset) => copyWith(equalizer: equalizer, preset: preset);

  /// 返回供数据库和设备同步使用的稳定映射。
  Map<String, dynamic> toMap() => {
    'volume': volume,
    'speed': speed,
    'pitch': pitch,
    'skipSilence': skipSilence,
    'loudnessEnhancerEnabled': loudnessEnhancerEnabled,
    'loudnessEnhancer': loudnessEnhancer,
    'equalizerEnabled': equalizerEnabled,
    'equalizer': equalizer.toMap(),
    'preset': preset?.toMap(),
    'modifiedDate': modifiedDate,
  };

  /// 判断当前声音修改应使用哪类提示图标。
  PlayerConfigModificationScale getModificationScale() {
    if (volume != 1.0 || speed != 1.0 || pitch != 1.0 || skipSilence) {
      return PlayerConfigModificationScale.main;
    }
    if (loudnessEnhancerEnabled || loudnessEnhancer != 0.0 || equalizerEnabled || equalizer != ParametricEqualizer.flat) {
      return PlayerConfigModificationScale.alt;
    }
    return PlayerConfigModificationScale.none;
  }

  @override
  bool operator ==(Object other) {
    return other is PlayerConfig &&
        volume == other.volume &&
        speed == other.speed &&
        pitch == other.pitch &&
        skipSilence == other.skipSilence &&
        loudnessEnhancerEnabled == other.loudnessEnhancerEnabled &&
        loudnessEnhancer == other.loudnessEnhancer &&
        equalizerEnabled == other.equalizerEnabled &&
        equalizer == other.equalizer &&
        preset == other.preset &&
        modifiedDate == other.modifiedDate;
  }

  @override
  int get hashCode => Object.hash(volume, speed, pitch, skipSilence, loudnessEnhancerEnabled, loudnessEnhancer, equalizerEnabled, equalizer, preset, modifiedDate);
}

class SleepTimerConfig {
  final bool enableSleepAfterItems;
  final bool enableSleepAfterMins;
  final int sleepAfterMin;
  final int sleepAfterItems;

  const SleepTimerConfig({
    this.enableSleepAfterItems = false,
    this.enableSleepAfterMins = false,
    this.sleepAfterMin = 0,
    this.sleepAfterItems = 0,
  });

  /// 生成更新后的睡眠定时配置。
  SleepTimerConfig copyWith({bool? enableSleepAfterItems, bool? enableSleepAfterMins, int? sleepAfterMin, int? sleepAfterItems}) {
    return SleepTimerConfig(
      enableSleepAfterItems: enableSleepAfterItems ?? this.enableSleepAfterItems,
      enableSleepAfterMins: enableSleepAfterMins ?? this.enableSleepAfterMins,
      sleepAfterMin: sleepAfterMin ?? this.sleepAfterMin,
      sleepAfterItems: sleepAfterItems ?? this.sleepAfterItems,
    );
  }
}

class PlayerQueue<Q> extends ListBase<Q> {
  final Rx<List<Q>> queueRx = Rx<List<Q>>(<Q>[]);
  List<int>? originalIndices;

  List<Q> get value => queueRx.value;

  @override
  int get length => value.length;

  @override
  set length(int value) {
    this.value.length = value;
    originalIndices = null;
    queueRx.refresh();
  }

  @override
  Q operator [](int index) => value[index];

  @override
  void operator []=(int index, Q item) {
    value[index] = item;
    originalIndices = null;
    queueRx.refresh();
  }

  /// 用新队列和可选的原始索引一次性替换当前状态。
  void assign(Iterable<Q> items, {List<int>? originalIndices}) {
    queueRx.value = List<Q>.of(items);
    this.originalIndices = originalIndices == null ? null : List<int>.of(originalIndices);
  }

  @override
  void clear() => assign(const []);

  @override
  void addAll(Iterable<Q> iterable) {
    value.addAll(iterable);
    originalIndices = null;
    queueRx.refresh();
  }

  @override
  void insertAll(int index, Iterable<Q> iterable) {
    value.insertAll(index, iterable);
    originalIndices = null;
    queueRx.refresh();
  }

  @override
  Q removeAt(int index) {
    final removed = value.removeAt(index);
    originalIndices = null;
    queueRx.refresh();
    return removed;
  }

  @override
  void removeRange(int start, int end) {
    value.removeRange(start, end);
    originalIndices = null;
    queueRx.refresh();
  }

  /// 在批量原地修改完成后统一通知监听者。
  void refresh({bool preserveOriginalIndices = false}) {
    if (!preserveOriginalIndices) originalIndices = null;
    queueRx.refresh();
  }
}

class MediaControlsProvider {
  final List<MediaAction> actions;
  final List<int>? compactActions;

  const MediaControlsProvider({this.actions = const [MediaAction.playPause], this.compactActions});

  /// 返回传统通知栏的上一首、播放暂停和下一首操作。
  factory MediaControlsProvider.main() => const MediaControlsProvider(
    actions: [MediaAction.skipToPrevious, MediaAction.playPause, MediaAction.skipToNext],
    compactActions: [0, 1, 2],
  );

  /// 返回 Android 13 媒体通知使用的操作布局。
  factory MediaControlsProvider.android13plus() => const MediaControlsProvider(
    actions: [MediaAction.skipToPrevious, MediaAction.playPause, MediaAction.skipToNext],
    compactActions: [0, 1, 2],
  );
}
