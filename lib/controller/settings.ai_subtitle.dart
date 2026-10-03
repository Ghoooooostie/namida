part of 'settings_controller.dart';

/// AI subtitle recognition & translation.
///
/// The keys live here instead of inside [AiSubtitleConfig] so they are covered by
/// the regular backup & sync, while the api keys stay out of the synced payload
/// (`sync: false`) like every other credential in the app.
class _AiSubtitleSettings extends _SettingsKeysWriter {
  _AiSubtitleSettings._internal();

  // -- recognition

  late final recognitionMode = _keyEnum(
    'aiSubtitleRecognitionMode',
    AiSubtitleRecognitionMode.api,
    AiSubtitleRecognitionMode.values,
  );

  late final localEngine = _keyEnum(
    'aiSubtitleLocalEngine',
    AiLocalAsrEngine.vosk,
    AiLocalAsrEngine.values,
  );

  late final asrProvider = _keyEnum(
    'aiSubtitleAsrProvider',
    AiApiProvider.openAi,
    AiApiProvider.values,
  );

  late final asrBaseUrl = _key('aiSubtitleAsrBaseUrl', '');

  late final asrModel = _key('aiSubtitleAsrModel', 'whisper-1');

  /// never synced, it is a credential.
  late final asrApiKey = _key('aiSubtitleAsrApiKey', '', sync: false);

  late final recognitionPrompt = _key('aiSubtitlePrompt', '');

  /// empty means "let the provider decide".
  late final languageCode = _key('aiSubtitleLanguageCode', '');

  // -- translation

  /// Traditional engines are stored in priority order; an empty list keeps the API path.
  late final enabledTraditionalEngines = _keyEnumList(
    'aiSubtitleEnabledTraditionalEngines',
    const <AiTranslatorId>[],
    AiTranslatorId.values,
  );

  late final translationProvider = _keyEnum(
    'aiSubtitleTranslationProvider',
    AiApiProvider.openAi,
    AiApiProvider.values,
  );

  late final translationBaseUrl = _key('aiSubtitleTranslationBaseUrl', '');

  late final translationModel = _key('aiSubtitleTranslationModel', 'gpt-4o-mini');

  /// never synced, it is a credential.
  late final translationApiKey = _key('aiSubtitleTranslationApiKey', '', sync: false);

  late final targetLanguage = _keyEnum(
    'aiSubtitleTargetLanguage',
    AiSubtitleTargetLanguage.simplifiedChinese,
    AiSubtitleTargetLanguage.values,
  );

  late final translationStylePrompt = _key('aiSubtitleStylePrompt', '');

  // -- output

  late final saveLocation = _keyEnum(
    'aiSubtitleSaveLocation',
    AiSubtitleSaveLocation.trackFolder,
    AiSubtitleSaveLocation.values,
    sync: false,
  );

  late final voskModelName = _key('aiSubtitleVoskModel', AiLocalAsrEngine.vosk.defaultModelName ?? '', sync: false);

  late final translateAfterRecognition = _key('aiSubtitleTranslateAfter', true);

  @override
  Set<String> get sensitiveKeys => const {
        'aiSubtitleAsrApiKey',
        'aiSubtitleTranslationApiKey',
      };

  @override
  String get filePath => AppPaths.SETTINGS_AI_SUBTITLE;
}