import 'package:nampack/nampack.dart';

import 'package:namida/controller/settings_controller.dart';
import 'package:namida/controller/ai_subtitle/translators/ai_translator.dart';

/// How the audio gets turned into cues.
enum AiSubtitleRecognitionMode {
  local,
  api;

  bool get isLocal => this == AiSubtitleRecognitionMode.local;
}

/// On device engines.
///
/// [vosk] runs on the vosk plugin, every other engine runs on the sherpa-onnx
/// ffi runtime, each with its own downloadable model (see [AiSubtitleModels]).
enum AiLocalAsrEngine {
  vosk('Vosk', 'vosk-model-small-cn-0.22'),
  whisper('Whisper', 'sherpa-onnx-whisper-tiny.en'),
  senseVoice('SenseVoice', 'sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17'),
  paraformer('Paraformer', 'sherpa-onnx-paraformer-zh-2024-03-09'),
  moonshine('Moonshine', 'sherpa-onnx-moonshine-tiny-en-int8');

  const AiLocalAsrEngine(this.label, this.defaultModelName);

  final String label;

  /// the model dir this engine starts with.
  final String? defaultModelName;

  bool get usesVoskRuntime => this == AiLocalAsrEngine.vosk;
  bool get usesSherpaRuntime => !usesVoskRuntime;

  bool get isAvailable => true;
  bool get isComingSoon => !isAvailable;
}

/// OpenAI compatible endpoints, plus gemini which has its own REST shape.
enum AiApiProvider {
  openAi('GPT / OpenAI', 'https://api.openai.com/v1'),
  gemini('Google Gemini', 'https://generativelanguage.googleapis.com/v1beta'),
  groq('Groq Whisper', 'https://api.groq.com/openai/v1'),
  deepSeek('DeepSeek', 'https://api.deepseek.com/v1'),
  custom('Custom', '');

  const AiApiProvider(this.label, this.defaultBaseUrl);

  final String label;
  final String defaultBaseUrl;

  /// shown as the field hint, so the user knows what to type before touching it.
  String get defaultModelHint => switch (this) {
        AiApiProvider.openAi => 'whisper-1',
        AiApiProvider.gemini => 'gemini-2.0-flash',
        AiApiProvider.groq => 'whisper-large-v3',
        AiApiProvider.deepSeek => 'deepseek-chat',
        AiApiProvider.custom => 'whisper-1',
      };

  /// gemini does not speak the OpenAI shape, everything else does.
  bool get isOpenAiCompatible => this != AiApiProvider.gemini;
  bool get needsBaseUrl => this == AiApiProvider.custom;
}

enum AiSubtitleTargetLanguage {
  simplifiedChinese('简体中文', 'zh'),
  traditionalChinese('繁體中文', 'zh-Hant'),
  english('English', 'en'),
  japanese('日本語', 'ja'),
  korean('한국어', 'ko'),
  spanish('Español', 'es'),
  french('Français', 'fr'),
  german('Deutsch', 'de'),
  russian('Русский', 'ru'),
  portuguese('Português', 'pt'),
  italian('Italiano', 'it');

  const AiSubtitleTargetLanguage(this.label, this.code);

  final String label;
  final String code;

  /// ISO 639-1, the subtitles controller matches tracks by this.
  String get shortCode => code.split('-').first;

  static AiSubtitleTargetLanguage fromCode(String? code) {
    if (code == null || code.isEmpty) return simplifiedChinese;
    final lower = code.toLowerCase();
    for (final e in values) {
      if (e.code.toLowerCase() == lower) return e;
      if (e.shortCode.toLowerCase() == lower) return e;
    }
    return simplifiedChinese;
  }
}

/// Where a generated `.srt` is written.
enum AiSubtitleSaveLocation {
  trackFolder('Next to the track'),
  appCache('App cache');

  const AiSubtitleSaveLocation(this.label);

  final String label;
}

/// Everything the AI subtitle feature needs, persisted on its own instead of
/// through `settings` so the feature stays self contained.
///
/// TODO: fold these into `settings_controller.dart` (as `late final` keys) once
/// the tree is stable, the API key in particular should end up in the synced
/// settings with `sync: false`.
/// A thin facade over [settings.aiSubtitle], so the feature has one place to
/// reach its values from while the values themselves stay regular settings keys
/// (backup & sync aware, api keys excluded).
class AiSubtitleConfig {
  static final inst = AiSubtitleConfig._();

  AiSubtitleConfig._();

  // -- the settings class is library private, so it is reached by inference.
  dynamic get _s => settings.aiSubtitle;

  dynamic get recognitionMode => _s.recognitionMode;
  dynamic get localEngine => _s.localEngine;
  dynamic get languageCode => _s.languageCode;
  dynamic get recognitionPrompt => _s.recognitionPrompt;

  dynamic get asrProvider => _s.asrProvider;
  dynamic get asrBaseUrl => _s.asrBaseUrl;
  dynamic get asrModel => _s.asrModel;
  dynamic get asrApiKey => _s.asrApiKey;

  dynamic get enabledTraditionalEngines => _s.enabledTraditionalEngines;
  dynamic get translationProvider => _s.translationProvider;
  dynamic get translationBaseUrl => _s.translationBaseUrl;
  dynamic get translationModel => _s.translationModel;
  dynamic get translationApiKey => _s.translationApiKey;
  dynamic get targetLanguage => _s.targetLanguage;
  dynamic get translationStylePrompt => _s.translationStylePrompt;

  dynamic get saveLocation => _s.saveLocation;

  /// vosk model dir name, see [AiLocalAsrEngine.defaultModelName].
  dynamic get voskModelName => _s.voskModelName;

  /// the selected local model dir, whichever engine it belongs to.
  /// Same settings key as [voskModelName], the friendlier read site name.
  dynamic get localModelName => _s.voskModelName;

  /// when false, a recognized track is translated right away.
  dynamic get translateAfterRecognition => _s.translateAfterRecognition;

  String get asrResolvedBaseUrl {
    final custom = asrBaseUrl.value.trim();
    if (custom.isNotEmpty) return custom;
    return asrProvider.value.defaultBaseUrl;
  }

  String get translationResolvedBaseUrl {
    final custom = translationBaseUrl.value.trim();
    if (custom.isNotEmpty) return custom;
    return translationProvider.value.defaultBaseUrl;
  }

  /// api key + model are the minimum for a request to be worth attempting.
  bool get isAsrConfigured => asrApiKey.value.trim().isNotEmpty && asrModel.value.trim().isNotEmpty;

  bool get isTranslationConfigured =>
      enabledTraditionalEngines.value.isNotEmpty || (translationApiKey.value.trim().isNotEmpty && translationModel.value.trim().isNotEmpty);

  /// A copy of the recognition config, used to start a job.
  AiAsrSettings get asrSettings => AiAsrSettings(
        mode: recognitionMode.value,
        engine: localEngine.value,
        provider: asrProvider.value,
        baseUrl: asrResolvedBaseUrl,
        model: asrModel.value.trim(),
        apiKey: asrApiKey.value.trim(),
        languageCode: languageCode.value.trim(),
        prompt: recognitionPrompt.value.trim(),
        localModelName: localModelName.value.trim().isEmpty ? localEngine.value.defaultModelName ?? '' : localModelName.value.trim(),
      );

  AiTranslationSettings get translationSettings => AiTranslationSettings(
        enabledTraditionalEngines: List<AiTranslatorId>.unmodifiable(enabledTraditionalEngines.value),
        provider: translationProvider.value,
        baseUrl: translationResolvedBaseUrl,
        model: translationModel.value.trim(),
        apiKey: translationApiKey.value.trim(),
        targetLanguage: targetLanguage.value,
        stylePrompt: translationStylePrompt.value.trim(),
      );

  /// Settings persist on their own, this only exists so the call sites read as
  /// "make sure the user choice is kept" without knowing that.
  ///
  /// It also **notifies** on purpose: a `_SettingsKey` is created the first time
  /// it is touched, which for the settings happens at startup (`prepareAllSettings`),
  /// long before any `Obx` exists. nampack's `RxAutoManager.pullObservers` only
  /// registers a builder while one is building, so those keys can never be
  /// auto-tracked and a plain `Obx(() => settings.x.value)` would never rebuild.
  /// Use `ObxO(rx: AiSubtitleConfig.inst.revision, ...)` for anything that shows
  /// these values, and call this after changing one.
  void save() {
    for (final key in _allKeys) {
      key.refresh();
    }
    revision.value++;
  }

  /// Bumped by [save], subscribe to it to show any of the values above.
  final revision = 0.obs;

  List<dynamic> get _allKeys => [
        recognitionMode,
        localEngine,
        asrProvider,
        asrBaseUrl,
        asrModel,
        asrApiKey,
        recognitionPrompt,
        languageCode,
        enabledTraditionalEngines,
        translationProvider,
        translationBaseUrl,
        translationModel,
        translationApiKey,
        targetLanguage,
        translationStylePrompt,
        saveLocation,
        voskModelName,
        translateAfterRecognition,
      ];

  void applyAsrProvider(AiApiProvider provider) {
    asrProvider.save(provider);
    if (!provider.needsBaseUrl) asrBaseUrl.save('');
  }

  void applyTranslationProvider(AiApiProvider provider) {
    translationProvider.save(provider);
    if (!provider.needsBaseUrl) translationBaseUrl.save('');
  }
}

/// A snapshot of the recognition config, so a queued job is not affected by
/// the user changing the settings halfway through a batch.
class AiAsrSettings {
  final AiSubtitleRecognitionMode mode;
  final AiLocalAsrEngine engine;
  final AiApiProvider provider;
  final String baseUrl;
  final String model;
  final String apiKey;
  final String languageCode;
  final String prompt;

  /// the local model dir name, for whichever local engine is selected.
  final String localModelName;

  const AiAsrSettings({
    required this.mode,
    required this.engine,
    required this.provider,
    required this.baseUrl,
    required this.model,
    required this.apiKey,
    required this.languageCode,
    required this.prompt,
    required this.localModelName,
  });

  bool get isLocal => mode.isLocal;
}

/// A snapshot of the translation config.
class AiTranslationSettings {
  /// Enabled traditional engines in priority order. The first one is used.
  final List<AiTranslatorId> enabledTraditionalEngines;
  final AiApiProvider provider;
  final String baseUrl;
  final String model;
  final String apiKey;
  final AiSubtitleTargetLanguage targetLanguage;
  final String stylePrompt;

  const AiTranslationSettings({
    required this.enabledTraditionalEngines,
    required this.provider,
    required this.baseUrl,
    required this.model,
    required this.apiKey,
    required this.targetLanguage,
    required this.stylePrompt,
  });
}
