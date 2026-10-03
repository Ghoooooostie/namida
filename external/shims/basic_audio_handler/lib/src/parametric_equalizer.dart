// 参数均衡器的数据模型、序列化和频响计算，供播放器与设置页共同使用。
import 'dart:math' as math;

enum EqualizerBandType {
  peak,
  lowShelf,
  highShelf,
  lowPass,
  highPass,
  bandPass,
  notch,
  allPass;

  bool get hasGain => this == peak || this == lowShelf || this == highShelf;
  bool get hasOrder => this == lowPass || this == highPass;
}

enum EqualizerChannel { all, left, right }

class EqualizerBand {
  static const double kMinGain = -30.0;
  static const double kMaxGain = 30.0;
  static const double kMinQ = 0.1;
  static const double kMaxQ = 30.0;
  static const double kDefaultQ = 0.7071067811865476;
  static const double kMinFrequency = 10.0;
  static const double kMaxFrequency = 24000.0;
  static const List<int> kOrders = [2, 4, 6, 8];

  final int id;
  final EqualizerBandType type;
  final double frequency;
  final double gain;
  final double q;
  final int order;
  final EqualizerChannel channel;
  final bool enabled;

  const EqualizerBand({
    required this.id,
    this.type = EqualizerBandType.peak,
    required this.frequency,
    this.gain = 0.0,
    this.q = kDefaultQ,
    this.order = 2,
    this.channel = EqualizerChannel.all,
    this.enabled = true,
  });

  /// 返回实现当前滤波器阶数所需的二阶节数量。
  int get sectionCount => type.hasOrder ? math.max(1, order ~/ 2) : 1;

  /// 返回巴特沃斯高低通指定二阶节的 Q 值，其他滤波器沿用用户配置。
  double sectionQ(int section) {
    if (!type.hasOrder) return q;
    if (section < 0 || section >= sectionCount) {
      throw RangeError.range(section, 0, sectionCount - 1, 'section');
    }
    return 1 / (2 * math.cos((2 * section + 1) * math.pi / (2 * order)));
  }

  EqualizerBand copyWith({
    int? id,
    EqualizerBandType? type,
    double? frequency,
    double? gain,
    double? q,
    int? order,
    EqualizerChannel? channel,
    bool? enabled,
  }) {
    return EqualizerBand(
      id: id ?? this.id,
      type: type ?? this.type,
      frequency: frequency ?? this.frequency,
      gain: gain ?? this.gain,
      q: q ?? this.q,
      order: order ?? this.order,
      channel: channel ?? this.channel,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'type': type.name,
    'frequency': frequency,
    'gain': gain,
    'q': q,
    'order': order,
    'channel': channel.name,
    'enabled': enabled,
  };

  static EqualizerBand? fromMap(dynamic value) {
    if (value is! Map) return null;
    final frequency = value['frequency'];
    if (frequency is! num) return null;
    final typeName = value['type']?.toString();
    final channelName = value['channel']?.toString();
    return EqualizerBand(
      id: (value['id'] as num?)?.toInt() ?? 0,
      type: EqualizerBandType.values.firstWhere(
        (item) => item.name == typeName,
        orElse: () => EqualizerBandType.peak,
      ),
      frequency: frequency.toDouble(),
      gain: (value['gain'] as num?)?.toDouble() ?? 0.0,
      q: (value['q'] as num?)?.toDouble() ?? kDefaultQ,
      order: (value['order'] as num?)?.toInt() ?? 2,
      channel: EqualizerChannel.values.firstWhere(
        (item) => item.name == channelName,
        orElse: () => EqualizerChannel.all,
      ),
      enabled: value['enabled'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is EqualizerBand &&
        id == other.id &&
        type == other.type &&
        frequency == other.frequency &&
        gain == other.gain &&
        q == other.q &&
        order == other.order &&
        channel == other.channel &&
        enabled == other.enabled;
  }

  @override
  int get hashCode => Object.hash(id, type, frequency, gain, q, order, channel, enabled);
}

class ParametricEqualizer {
  static const double kMinPreamp = -30.0;
  static const double kMaxPreamp = 30.0;
  static const List<double> graphic5Frequencies = [60.0, 230.0, 910.0, 3600.0, 14000.0];
  static const List<double> graphic10Frequencies = [31.0, 62.0, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0];
  static const List<double> graphic15Frequencies = [25.0, 40.0, 63.0, 100.0, 160.0, 250.0, 400.0, 630.0, 1000.0, 1600.0, 2500.0, 4000.0, 6300.0, 10000.0, 16000.0];
  static const List<double> graphic31Frequencies = [
    20.0,
    25.0,
    31.5,
    40.0,
    50.0,
    63.0,
    80.0,
    100.0,
    125.0,
    160.0,
    200.0,
    250.0,
    315.0,
    400.0,
    500.0,
    630.0,
    800.0,
    1000.0,
    1250.0,
    1600.0,
    2000.0,
    2500.0,
    3150.0,
    4000.0,
    5000.0,
    6300.0,
    8000.0,
    10000.0,
    12500.0,
    16000.0,
    20000.0,
  ];

  static const flat = ParametricEqualizer();

  final List<EqualizerBand> bands;
  final double preamp;
  final bool autoPreamp;
  final bool limiter;

  const ParametricEqualizer({
    this.bands = const [],
    this.preamp = 0.0,
    this.autoPreamp = true,
    this.limiter = true,
  });

  ParametricEqualizer copyWith({List<EqualizerBand>? bands, double? preamp, bool? autoPreamp, bool? limiter}) {
    return ParametricEqualizer(
      bands: bands ?? this.bands,
      preamp: preamp ?? this.preamp,
      autoPreamp: autoPreamp ?? this.autoPreamp,
      limiter: limiter ?? this.limiter,
    );
  }

  ParametricEqualizer withBand(EqualizerBand band) {
    final result = List<EqualizerBand>.of(bands);
    final index = result.indexWhere((item) => item.id == band.id);
    if (index < 0) {
      result.add(band);
    } else {
      result[index] = band;
    }
    return copyWith(bands: result);
  }

  ParametricEqualizer withoutBand(int id) => copyWith(bands: bands.where((item) => item.id != id).toList());

  int getNextBandId() => bands.fold<int>(-1, (value, item) => math.max(value, item.id)) + 1;

  List<EqualizerBand> getActiveBands() {
    return bands.where((band) => band.enabled && (!band.type.hasGain || band.gain != 0.0)).toList();
  }

  bool hasChannelSpecificBands() => getActiveBands().any((band) => band.channel != EqualizerChannel.all);

  double responseDb(double frequency, {EqualizerChannel channel = EqualizerChannel.all}) {
    var total = 0.0;
    for (final band in getActiveBands()) {
      if (channel != EqualizerChannel.all && band.channel != EqualizerChannel.all && band.channel != channel) continue;
      total += _bandResponseDb(band, frequency);
    }
    return total;
  }

  List<double> responseCurve(List<double> frequencies, {EqualizerChannel channel = EqualizerChannel.all}) {
    return frequencies.map((frequency) => responseDb(frequency, channel: channel)).toList();
  }

  double computeEffectivePreamp() {
    if (!autoPreamp) return preamp;
    final frequencies = logFrequencies(EqualizerBand.kMinFrequency, EqualizerBand.kMaxFrequency, 512);
    var maximum = 0.0;
    for (final channel in const [EqualizerChannel.left, EqualizerChannel.right]) {
      for (final frequency in frequencies) {
        maximum = math.max(maximum, responseDb(frequency, channel: channel));
      }
    }
    return -maximum;
  }

  Map<String, dynamic> toMap() => {
    'bands': bands.map((band) => band.toMap()).toList(),
    'preamp': preamp,
    'autoPreamp': autoPreamp,
    'limiter': limiter,
  };

  static ParametricEqualizer? fromMap(dynamic value) {
    if (value is! Map) return null;
    final bandsRaw = value['bands'];
    final bands = <EqualizerBand>[];
    if (bandsRaw is List) {
      for (final item in bandsRaw) {
        final band = EqualizerBand.fromMap(item);
        if (band != null) bands.add(band);
      }
    }
    return ParametricEqualizer(
      bands: bands,
      preamp: (value['preamp'] as num?)?.toDouble() ?? 0.0,
      autoPreamp: value['autoPreamp'] as bool? ?? true,
      limiter: value['limiter'] as bool? ?? true,
    );
  }

  static ParametricEqualizer fromLegacyGains(Map<double, double> gains) {
    var id = 0;
    final entries = gains.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return ParametricEqualizer(
      bands: [for (final entry in entries) EqualizerBand(id: id++, frequency: entry.key, gain: entry.value)],
    );
  }

  static ParametricEqualizer graphic(List<double> frequencies) {
    return ParametricEqualizer(
      bands: [for (var i = 0; i < frequencies.length; i++) EqualizerBand(id: i, frequency: frequencies[i])],
    );
  }

  static List<double> logFrequencies(double minimum, double maximum, int count) {
    if (count <= 0 || minimum <= 0 || maximum < minimum) return const [];
    if (count == 1) return [minimum];
    final ratio = math.pow(maximum / minimum, 1 / (count - 1)).toDouble();
    return List<double>.generate(count, (index) => minimum * math.pow(ratio, index).toDouble());
  }

  static ParametricEqualizer? fromEqualizerApo(String text) {
    final bands = <EqualizerBand>[];
    var preamp = 0.0;
    var channel = EqualizerChannel.all;
    final preampPattern = RegExp(r'^\s*Preamp\s*:\s*([-+]?\d+(?:\.\d+)?)', caseSensitive: false);
    final channelPattern = RegExp(r'^\s*Channel\s*:\s*(L|R|ALL)', caseSensitive: false);
    final filterPattern = RegExp(r'^\s*Filter\s+\d+\s*:\s*(ON|OFF)\s+(PK|LSC?|HSC?|LP|HP|BP|NO|AP)\s+(.+)$', caseSensitive: false);
    for (final line in text.split(RegExp(r'\r?\n'))) {
      final preampMatch = preampPattern.firstMatch(line);
      if (preampMatch != null) {
        preamp = double.parse(preampMatch.group(1)!);
        continue;
      }
      final channelMatch = channelPattern.firstMatch(line);
      if (channelMatch != null) {
        channel = switch (channelMatch.group(1)!.toUpperCase()) {
          'L' => EqualizerChannel.left,
          'R' => EqualizerChannel.right,
          _ => EqualizerChannel.all,
        };
        continue;
      }
      final filterMatch = filterPattern.firstMatch(line);
      if (filterMatch == null) continue;
      final args = filterMatch.group(3)!;
      final frequency = _apoNumber(args, 'Fc');
      if (frequency == null) continue;
      final type = switch (filterMatch.group(2)!.toUpperCase()) {
        'LS' || 'LSC' => EqualizerBandType.lowShelf,
        'HS' || 'HSC' => EqualizerBandType.highShelf,
        'LP' => EqualizerBandType.lowPass,
        'HP' => EqualizerBandType.highPass,
        'BP' => EqualizerBandType.bandPass,
        'NO' => EqualizerBandType.notch,
        'AP' => EqualizerBandType.allPass,
        _ => EqualizerBandType.peak,
      };
      var q = _apoNumber(args, 'Q') ?? EqualizerBand.kDefaultQ;
      final bandwidth = _apoNumber(args, r'BW(?:\s+Oct)?');
      if (bandwidth != null) q = 1 / (2 * _sinh(math.ln2 * bandwidth / 2));
      bands.add(
        EqualizerBand(
          id: bands.length,
          type: type,
          frequency: frequency,
          gain: _apoNumber(args, 'Gain') ?? 0.0,
          q: q,
          channel: channel,
          enabled: filterMatch.group(1)!.toUpperCase() == 'ON',
        ),
      );
    }
    if (bands.isEmpty) return null;
    return ParametricEqualizer(bands: bands, preamp: preamp, autoPreamp: false);
  }

  String toEqualizerApo() {
    final output = <String>['Preamp: ${computeEffectivePreamp().toStringAsFixed(2)} dB'];
    EqualizerChannel? writtenChannel;
    for (var i = 0; i < bands.length; i++) {
      final band = bands[i];
      if (band.channel != writtenChannel) {
        writtenChannel = band.channel;
        output.add(
          'Channel: ${switch (band.channel) {
            EqualizerChannel.left => 'L',
            EqualizerChannel.right => 'R',
            EqualizerChannel.all => 'ALL',
          }}',
        );
      }
      final type = switch (band.type) {
        EqualizerBandType.peak => 'PK',
        EqualizerBandType.lowShelf => 'LSC',
        EqualizerBandType.highShelf => 'HSC',
        EqualizerBandType.lowPass => 'LP',
        EqualizerBandType.highPass => 'HP',
        EqualizerBandType.bandPass => 'BP',
        EqualizerBandType.notch => 'NO',
        EqualizerBandType.allPass => 'AP',
      };
      final gain = band.type.hasGain ? ' Gain ${band.gain.toStringAsFixed(2)} dB' : '';
      output.add('Filter ${i + 1}: ${band.enabled ? 'ON' : 'OFF'} $type Fc ${band.frequency.toStringAsFixed(2)} Hz$gain Q ${band.q.toStringAsFixed(4)}');
    }
    return output.join('\n');
  }

  static double? _apoNumber(String text, String namePattern) {
    final match = RegExp('(?:^|\\s)$namePattern\\s+([-+]?\\d+(?:\\.\\d+)?)', caseSensitive: false).firstMatch(text);
    return match == null ? null : double.tryParse(match.group(1)!);
  }

  static double _sinh(double value) => (math.exp(value) - math.exp(-value)) / 2;

  static double _bandResponseDb(EqualizerBand band, double frequency) {
    if (frequency <= 0 || band.frequency <= 0) return 0.0;
    if (band.type.hasOrder && band.order > 2) {
      final ratio = band.type == EqualizerBandType.highPass ? band.frequency / frequency : frequency / band.frequency;
      return -10.0 * math.log(1 + math.pow(ratio, 2 * band.order)) / math.ln10;
    }
    const sampleRate = 96000.0;
    final omega = 2 * math.pi * frequency.clamp(0.0, sampleRate / 2 - 1) / sampleRate;
    final omega0 = 2 * math.pi * band.frequency.clamp(1.0, sampleRate / 2 - 1) / sampleRate;
    final cosine = math.cos(omega0);
    final sine = math.sin(omega0);
    final q = band.q.clamp(EqualizerBand.kMinQ, EqualizerBand.kMaxQ);
    final alpha = sine / (2 * q);
    final a = math.pow(10, band.gain / 40).toDouble();
    late final List<double> coefficients;
    switch (band.type) {
      case EqualizerBandType.peak:
        coefficients = [1 + alpha * a, -2 * cosine, 1 - alpha * a, 1 + alpha / a, -2 * cosine, 1 - alpha / a];
      case EqualizerBandType.lowShelf:
        final shelfAlpha = sine / math.sqrt(2);
        final beta = 2 * math.sqrt(a) * shelfAlpha;
        coefficients = [
          a * ((a + 1) - (a - 1) * cosine + beta),
          2 * a * ((a - 1) - (a + 1) * cosine),
          a * ((a + 1) - (a - 1) * cosine - beta),
          (a + 1) + (a - 1) * cosine + beta,
          -2 * ((a - 1) + (a + 1) * cosine),
          (a + 1) + (a - 1) * cosine - beta,
        ];
      case EqualizerBandType.highShelf:
        final shelfAlpha = sine / math.sqrt(2);
        final beta = 2 * math.sqrt(a) * shelfAlpha;
        coefficients = [
          a * ((a + 1) + (a - 1) * cosine + beta),
          -2 * a * ((a - 1) + (a + 1) * cosine),
          a * ((a + 1) + (a - 1) * cosine - beta),
          (a + 1) - (a - 1) * cosine + beta,
          2 * ((a - 1) - (a + 1) * cosine),
          (a + 1) - (a - 1) * cosine - beta,
        ];
      case EqualizerBandType.lowPass:
        coefficients = [(1 - cosine) / 2, 1 - cosine, (1 - cosine) / 2, 1 + alpha, -2 * cosine, 1 - alpha];
      case EqualizerBandType.highPass:
        coefficients = [(1 + cosine) / 2, -(1 + cosine), (1 + cosine) / 2, 1 + alpha, -2 * cosine, 1 - alpha];
      case EqualizerBandType.bandPass:
        coefficients = [alpha, 0, -alpha, 1 + alpha, -2 * cosine, 1 - alpha];
      case EqualizerBandType.notch:
        coefficients = [1, -2 * cosine, 1, 1 + alpha, -2 * cosine, 1 - alpha];
      case EqualizerBandType.allPass:
        coefficients = [1 - alpha, -2 * cosine, 1 + alpha, 1 + alpha, -2 * cosine, 1 - alpha];
    }
    final magnitude = _biquadMagnitude(coefficients, omega);
    return magnitude <= 0 ? -120.0 : 20 * math.log(magnitude) / math.ln10;
  }

  static double _biquadMagnitude(List<double> c, double omega) {
    final cos1 = math.cos(omega);
    final sin1 = math.sin(omega);
    final cos2 = math.cos(2 * omega);
    final sin2 = math.sin(2 * omega);
    final numeratorReal = c[0] + c[1] * cos1 + c[2] * cos2;
    final numeratorImag = -c[1] * sin1 - c[2] * sin2;
    final denominatorReal = c[3] + c[4] * cos1 + c[5] * cos2;
    final denominatorImag = -c[4] * sin1 - c[5] * sin2;
    return math.sqrt((numeratorReal * numeratorReal + numeratorImag * numeratorImag) / (denominatorReal * denominatorReal + denominatorImag * denominatorImag));
  }

  @override
  bool operator ==(Object other) {
    if (other is! ParametricEqualizer || preamp != other.preamp || autoPreamp != other.autoPreamp || limiter != other.limiter || bands.length != other.bands.length) return false;
    for (var i = 0; i < bands.length; i++) {
      if (bands[i] != other.bands[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(bands), preamp, autoPreamp, limiter);
}

class EqualizerPreset {
  static final List<EqualizerPreset> allDefaults = [
    EqualizerPreset(name: 'Flat', equalizer: ParametricEqualizer.flat),
  ];

  final String name;
  final ParametricEqualizer equalizer;

  const EqualizerPreset({required this.name, required this.equalizer});

  EqualizerPreset copyWith({String? name, ParametricEqualizer? equalizer}) {
    return EqualizerPreset(name: name ?? this.name, equalizer: equalizer ?? this.equalizer);
  }

  Map<String, dynamic> toMap() => {'name': name, 'equalizer': equalizer.toMap()};

  static EqualizerPreset? fromMap(dynamic value) {
    if (value is! Map || value['name'] is! String) return null;
    final equalizer = ParametricEqualizer.fromMap(value['equalizer']);
    if (equalizer != null) return EqualizerPreset(name: value['name'] as String, equalizer: equalizer);
    final gains = value['gains'];
    if (gains is! List) return null;
    final frequencies = switch (gains.length) {
      5 => ParametricEqualizer.graphic5Frequencies,
      10 => ParametricEqualizer.graphic10Frequencies,
      15 => ParametricEqualizer.graphic15Frequencies,
      31 => ParametricEqualizer.graphic31Frequencies,
      _ => const <double>[],
    };
    if (frequencies.isEmpty) return null;
    final map = <double, double>{};
    for (var i = 0; i < frequencies.length; i++) {
      final gain = gains[i];
      if (gain is! num) return null;
      map[frequencies[i]] = gain.toDouble();
    }
    return EqualizerPreset(name: value['name'] as String, equalizer: ParametricEqualizer.fromLegacyGains(map));
  }

  @override
  bool operator ==(Object other) => other is EqualizerPreset && name == other.name && equalizer == other.equalizer;

  @override
  int get hashCode => Object.hash(name, equalizer);
}
