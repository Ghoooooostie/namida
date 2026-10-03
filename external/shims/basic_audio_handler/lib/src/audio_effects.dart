// 跨播放器的参数均衡器与响度增强控制器。
import 'dart:math' as math;

import 'package:just_audio/just_audio.dart';
import 'package:nampack/nampack.dart';

import 'av_player.dart';
import 'parametric_equalizer.dart';

class EqualizerExtended {
  final AVPlayer Function() _playerProvider;
  final AndroidEqualizer androidAudioEffect = AndroidEqualizer();
  final Rx<bool> enabled = false.obs;

  EqualizerExtended(this._playerProvider);

  /// 同时更新原生 Android 效果器和支持参数滤波的播放器。
  Future<void> apply(bool enabled, ParametricEqualizer equalizer) async {
    this.enabled.value = enabled;
    await androidAudioEffect.setEnabled(enabled);
    final player = _playerProvider();
    if (player is CustomAudioPlayer) {
      if (!enabled) return;
      final parameters = await androidAudioEffect.parameters;
      if (parameters == null) return;
      for (final band in parameters.bands) {
        final gain = equalizer.responseDb(band.centerFrequency).clamp(parameters.minDecibels, parameters.maxDecibels).toDouble();
        await band.setGain(gain);
      }
      return;
    }
    await player.setEqualizer(enabled ? equalizer : null);
  }

  /// 释放本控制器持有的响应式状态。
  Future<void> dispose() async => enabled.close();
}

class LoudnessEnhancerExtended {
  static const double kMinGain = -20.0;
  static const double kMaxGain = 20.0;

  final AVPlayer Function() _playerProvider;
  final bool Function() _trackEnabled;
  final AndroidLoudnessEnhancer androidAudioEffect = AndroidLoudnessEnhancer();
  final Rx<double> targetGainTrack = 0.0.obs;
  final Rx<double> targetGainUser = 0.0.obs;
  bool _userEnabled = false;

  LoudnessEnhancerExtended(this._playerProvider, this._trackEnabled);

  /// 计算叠加用户增益和回放增益后的实际值。
  double getActualGainFromUser(bool enabled, double userGain) {
    final trackGain = _trackEnabled() ? targetGainTrack.value : 0.0;
    final requested = (enabled ? userGain : 0.0) + trackGain;
    return math.max(kMinGain, math.min(kMaxGain, requested));
  }

  /// 更新用户响度开关并立即应用。
  Future<void> setEnabledUser(bool enabled) async {
    _userEnabled = enabled;
    await refreshEnabled();
  }

  /// 更新曲目回放增益并立即应用。
  Future<void> setTargetGainTrack(double gain) async {
    targetGainTrack.value = gain;
    await _applyGain();
  }

  /// 更新用户响度增益并立即应用。
  Future<void> setTargetGainUser(double gain) async {
    targetGainUser.value = gain;
    await _applyGain();
  }

  /// 按用户设置或回放增益模式刷新效果器启用状态。
  Future<void> refreshEnabled() async {
    final enabled = _userEnabled || _trackEnabled();
    await androidAudioEffect.setEnabled(enabled);
    final player = _playerProvider();
    if (player is! CustomAudioPlayer) await player.setLoudnessEnhancerEnabled(enabled);
    await _applyGain();
  }

  /// 把合成后的响度增益发送给当前播放器。
  Future<void> _applyGain() async {
    final gain = getActualGainFromUser(_userEnabled, targetGainUser.value);
    await androidAudioEffect.setTargetGain(gain);
    final player = _playerProvider();
    if (player is! CustomAudioPlayer) await player.setLoudnessEnhancerGain(gain);
  }
}
