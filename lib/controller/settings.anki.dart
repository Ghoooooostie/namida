part of 'settings_controller.dart';

/// Anki 制卡配置。
///
/// 主体是一个 key（`config`），因为它内部结构会随功能演进，拆成几十个 key 反而要写一堆迁移。
/// 牌组/卡片类型缓存也在这份里，换设备同步时一并带过去。
///
/// AnkiConnect 的 API key 单独放在一个 key 上，这样备份里的敏感字段脱敏机制能直接生效。
class _AnkiSettings extends _SettingsKeysWriter {
  _AnkiSettings._internal();

  late final config = _keyObject<AnkiSettings>(
    'config',
    _defaultAnkiSettings(),
    AnkiSettings.fromJson,
    (value) => value.toJson(),
    sync: false,
  );

  late final ankiConnectApiKey = _key('ankiConnectApiKey', '', sync: false);

  @override
  Set<String> get sensitiveKeys => const {'ankiConnectApiKey'};

  @override
  String get filePath => AppPaths.SETTINGS_ANKI;

  /// 第一次用时给一套默认模板，省得用户面对空白页不知道从哪填起。
  ///
  /// 字段名按 Anki 默认的 Basic/基本类型猜，用户在设置页一改就好。
  static AnkiSettings _defaultAnkiSettings() {
    return AnkiSettings(
      // -- 手机上默认走 AnkiDroid：AnkiConnect 监听在电脑上，手机里的 127.0.0.1 指向自己。
      backendKind: AnkiBackendKind.platformDefault,
      cardFormats: [
        AnkiCardFormat(
          id: 'default',
          name: 'Default',
          fieldMappings: {
            'Front': '{expression}',
            'Back': '{glossary}',
            'Sentence': '{sentence}',
            'Audio': '{audio-clip}',
          },
        ),
      ],
    );
  }
}
