import 'package:flutter/material.dart';
import 'package:nampack/nampack.dart';

import 'package:namida/controller/ai_subtitle/ai_asr_factory.dart';
import 'package:namida/controller/ai_subtitle/ai_subtitle_config.dart';
import 'package:namida/controller/logs_controller.dart';
import 'package:namida/controller/navigator_controller.dart';
import 'package:namida/core/extensions.dart';
import 'package:namida/core/icon_fonts/broken_icons.dart';
import 'package:namida/core/translations/language.dart';
import 'package:namida/ui/pages/ai_subtitle/ai_subtitle_models_page.dart';
import 'package:namida/ui/widgets/ai_subtitle_widgets.dart';
import 'package:namida/ui/widgets/custom_widgets.dart';
import 'package:namida/ui/widgets/settings_card.dart';
import 'package:namida/ui/dialogs/edit_tags_dialog.dart' show CustomTagTextField;

/// Recognition settings, laid out like the reference design:
///
///   识别方式            [本地识别] [API 识别]   + 就绪状态
///   本地识别引擎 / API 识别   (随模式切换)
///     服务商 pills + 内联输入框 + 保存 / 测试连接
///
/// The provider & engine choice is **local state** first: tapping a pill flips
/// it immediately, and only then gets written to the settings. Going through the
/// settings observable alone made a tap look like it did nothing, and any
/// failure was silent.
class AiSubtitleRecognitionPage extends StatelessWidget {
  const AiSubtitleRecognitionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AiSubtitlePage(
      standalone: true,
      title: lang.aiSubtitleRecognition,
      subtitle: lang.aiSubtitleRecognitionSubtitle,
      icon: Broken.microphone,
      children: const [
        _ModeCard(),
        SizedBox(height: 12.0),
        _EngineCard(),
        SizedBox(height: 12.0),
        _TranslateAfterCard(),
      ],
    );
  }
}

/// 识别方式 + 就绪状态
class _ModeCard extends StatelessWidget {
  const _ModeCard();

  @override
  Widget build(BuildContext context) {
    return ObxO(
      rx: AiSubtitleConfig.inst.revision,
      builder: (context, _) {
      final config = AiSubtitleConfig.inst;
      final mode = config.recognitionMode.value;
      final ready = mode.isLocal ? true : config.isAsrConfigured;

      return SettingsCard(
        title: lang.aiSubtitleRecognitionMode,
        subtitle: lang.aiSubtitleRecognitionSubtitle,
        icon: Broken.microphone,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AiSubtitlePills<AiSubtitleRecognitionMode>(
              values: AiSubtitleRecognitionMode.values,
              selected: mode,
              labelOf: (e) => e.isLocal ? lang.aiSubtitleOnDevice : lang.aiSubtitleViaApi,
              onSelected: (value) {
                try {
                  config.recognitionMode.save(value);
                  config.save();
                } catch (e, st) {
                  logger.error('ai recognition: switching mode', e: e, st: st);
                  snackyy(message: '$e', isError: true);
                }
              },
            ),
            const SizedBox(height: 10.0),
            Text(
              mode.isLocal ? lang.aiSubtitleReady : (ready ? lang.aiSubtitleReady : lang.aiSubtitleAsrMissing),
              style: context.textTheme.bodySmall?.copyWith(
                color: ready ? null : context.theme.colorScheme.error,
              ),
            ),
          ],
        ),
      );
    });
  }
}

/// 本地识别引擎 or API 识别，随模式切换
class _EngineCard extends StatelessWidget {
  const _EngineCard();

  @override
  Widget build(BuildContext context) {
    return ObxO(
      rx: AiSubtitleConfig.inst.revision,
      builder: (context, _) {
      final isLocal = AiSubtitleConfig.inst.recognitionMode.value.isLocal;
      return isLocal ? const _LocalCard() : const _ApiCard();
    });
  }
}

/// 本地识别引擎 + 本地识别提示词
class _LocalCard extends StatelessWidget {
  const _LocalCard();

  @override
  Widget build(BuildContext context) {
    return ObxO(
      rx: AiSubtitleConfig.inst.revision,
      builder: (context, _) {
      final config = AiSubtitleConfig.inst;
      final engine = config.localEngine.value;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SettingsCard(
            title: lang.aiSubtitleLocalEngine,
            subtitle: lang.aiSubtitleLocalEngineSubtitle,
            icon: Broken.document_download,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AiSubtitlePills<AiLocalAsrEngine>(
                  values: AiLocalAsrEngine.values,
                  selected: engine,
                  labelOf: (e) => e.label,
                  onSelected: (value) {
                    try {
                      config.localEngine.save(value);
                      final modelName = value.defaultModelName;
                      if (modelName != null) config.localModelName.save(modelName);
                      config.save();
                    } catch (e, st) {
                      logger.error('ai recognition: switching engine', e: e, st: st);
                      snackyy(message: '$e', isError: true);
                    }
                  },
                  descriptionOf: (e) => e.isAvailable ? lang.aiSubtitleLocalEngineNote : lang.aiSubtitleEngineNotReady,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12.0),
          _LocalPromptCard(engine: engine),
        ],
      );
    });
  }
}

/// 本地识别提示词 + 语言代码 + 保存 / 管理本地模型
class _LocalPromptCard extends StatefulWidget {
  final AiLocalAsrEngine engine;
  const _LocalPromptCard({required this.engine});

  @override
  State<_LocalPromptCard> createState() => _LocalPromptCardState();
}

class _LocalPromptCardState extends State<_LocalPromptCard> {
  late final _prompt = TextEditingController(text: AiSubtitleConfig.inst.recognitionPrompt.value);
  late final _language = TextEditingController(text: AiSubtitleConfig.inst.languageCode.value);

  @override
  void dispose() {
    _prompt.dispose();
    _language.dispose();
    super.dispose();
  }

  void _save() {
    final config = AiSubtitleConfig.inst;
    try {
      config.recognitionPrompt.save(_prompt.text.trim());
      config.languageCode.save(_language.text.trim());
      config.save();
      snackyy(message: lang.done);
    } catch (e, st) {
      logger.error('ai recognition: saving local prompt', e: e, st: st);
      snackyy(message: '$e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      title: lang.aiSubtitleLocalPromptCard,
      subtitle: lang.aiSubtitleLocalPromptCardSubtitle,
      icon: Broken.sms_edit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomTagTextField(
            controller: _prompt,
            labelText: lang.aiSubtitleLocalPrompt,
            hintText: lang.aiSubtitleLocalPrompt,
            maxLines: 4,
          ),
          const SizedBox(height: 12.0),
          CustomTagTextField(
            controller: _language,
            labelText: lang.aiSubtitleLanguageCode,
            hintText: 'zh, en, ja...',
          ),
          const SizedBox(height: 16.0),
          Row(
            children: [
              Expanded(
                child: NamidaButton(
                  text: lang.save,
                  onTap: _save,
                ),
              ),
              const SizedBox(width: 10.0),
              Expanded(
                child: NamidaTextButton(
                  text: lang.aiSubtitleManageModels,
                  onTap: () => NamidaNavigator.inst.navigateToRoot(
                    const AiSubtitleModelsPage(),
                    transition: Transition.native,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 服务商 + API Key / 识别模型 / 识别提示词 + 保存 / 测试连接 / 高级设置
class _ApiCard extends StatefulWidget {
  const _ApiCard();

  @override
  State<_ApiCard> createState() => _ApiCardState();
}

class _ApiCardState extends State<_ApiCard> {
  /// local mirror of the provider, so a tap always shows up instantly.
  late AiApiProvider _provider = AiSubtitleConfig.inst.asrProvider.value;
  late final _apiKey = TextEditingController(text: AiSubtitleConfig.inst.asrApiKey.value);
  late final _model = TextEditingController(text: AiSubtitleConfig.inst.asrModel.value);
  late final _baseUrl = TextEditingController(text: AiSubtitleConfig.inst.asrBaseUrl.value);
  late final _prompt = TextEditingController(text: AiSubtitleConfig.inst.recognitionPrompt.value);

  final _isTesting = false.obs;
  final _testResult = Rxn<String>();
  final _testFailed = false.obs;

  @override
  void dispose() {
    _apiKey.dispose();
    _model.dispose();
    _baseUrl.dispose();
    _prompt.dispose();
    super.dispose();
  }

  void _selectProvider(AiApiProvider value) {
    // -- flip the UI first, persist second: a failed write must not swallow the tap.
    setState(() => _provider = value);
    try {
      AiSubtitleConfig.inst.applyAsrProvider(value);
      AiSubtitleConfig.inst.save();
    } catch (e, st) {
      logger.error('ai recognition: selecting provider $value', e: e, st: st);
      snackyy(message: '$e', isError: true);
    }
  }

  void _save() {
    final config = AiSubtitleConfig.inst;
    try {
      config.asrApiKey.save(_apiKey.text.trim());
      config.asrModel.save(_model.text.trim());
      config.asrBaseUrl.save(_baseUrl.text.trim());
      config.recognitionPrompt.save(_prompt.text.trim());
      config.save();
      snackyy(message: lang.done);
    } catch (e, st) {
      logger.error('ai recognition: saving api settings', e: e, st: st);
      snackyy(message: '$e', isError: true);
    }
  }

  Future<void> _test() async {
    _isTesting.value = true;
    _testResult.value = null;

    try {
      // -- test what is on screen, not what is still sitting in the settings.
      final base = AiSubtitleConfig.inst.asrSettings;
      final typedBaseUrl = _baseUrl.text.trim();

      final settings = AiAsrSettings(
        mode: base.mode,
        engine: base.engine,
        provider: _provider,
        baseUrl: typedBaseUrl.isEmpty ? _provider.defaultBaseUrl : typedBaseUrl,
        model: _model.text.trim(),
        apiKey: _apiKey.text.trim(),
        languageCode: base.languageCode,
        prompt: _prompt.text.trim(),
        localModelName: base.localModelName,
      );

      final engine = AiAsrEngineFactory.create(settings);
      await engine.testConnection(settings);
      _testFailed.value = false;
      _testResult.value = lang.aiSubtitleConnectionSucceeded;
    } catch (e, st) {
      logger.error('ai recognition: test connection', e: e, st: st);
      _testFailed.value = true;
      _testResult.value = '$e';
    } finally {
      _isTesting.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      title: lang.aiSubtitleApiRecognition,
      subtitle: lang.aiSubtitleApiRecognitionSubtitle,
      icon: Broken.cloud,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(lang.aiSubtitleServiceProvider, style: context.textTheme.titleMedium),
          const SizedBox(height: 10.0),
          AiSubtitlePills<AiApiProvider>(
            values: AiApiProvider.values,
            selected: _provider,
            labelOf: (e) => e.label,
            onSelected: _selectProvider,
          ),
          const SizedBox(height: 16.0),
          CustomTagTextField(
            controller: _apiKey,
            labelText: lang.aiSubtitleApiKey,
            hintText: lang.aiSubtitleApiKey,
            obscureText: true,
            // -- an obscured field must be single line, Flutter asserts otherwise.
            maxLines: 1,
          ),
          const SizedBox(height: 12.0),
          CustomTagTextField(
            controller: _model,
            labelText: lang.aiSubtitleModelName,
            hintText: _provider.defaultModelHint,
          ),
          const SizedBox(height: 12.0),
          CustomTagTextField(
            controller: _prompt,
            labelText: lang.aiSubtitlePrompt,
            hintText: lang.aiSubtitlePrompt,
            maxLines: 4,
          ),
          if (_provider.needsBaseUrl) ...[
            const SizedBox(height: 12.0),
            CustomTagTextField(
              controller: _baseUrl,
              labelText: lang.aiSubtitleBaseUrl,
              hintText: 'https://...',
            ),
          ],
          const SizedBox(height: 10.0),
          Text(
            lang.aiSubtitleRecognitionPromptNote,
            style: context.textTheme.bodySmall,
          ),
          const SizedBox(height: 16.0),
          Row(
            children: [
              Expanded(
                child: NamidaButton(
                  text: lang.save,
                  onTap: _save,
                ),
              ),
              const SizedBox(width: 10.0),
              Expanded(
                child: ObxO(
                  rx: _isTesting,
                  builder: (context, isTesting) => NamidaTextButton(
                    text: lang.aiSubtitleTestConnection,
                    enabled: !isTesting,
                    onTap: _test,
                  ),
                ),
              ),
            ],
          ),
          ObxO(
            rx: _testResult,
            builder: (context, result) => result == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 10.0),
                    child: Text(
                      result,
                      style: context.textTheme.bodySmall?.copyWith(
                        color: _testFailed.value ? context.theme.colorScheme.error : null,
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 4.0),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: NamidaTextButton(
              text: lang.advanced,
              onTap: () => showAiSubtitleTextDialog(
                title: lang.aiSubtitleBaseUrl,
                label: lang.aiSubtitleBaseUrl,
                subtitle: lang.aiSubtitleBaseUrlSubtitle,
                initialValue: _baseUrl.text,
                onSubmit: (value) {
                  _baseUrl.text = value;
                  _save();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 识别后翻译
class _TranslateAfterCard extends StatelessWidget {
  const _TranslateAfterCard();

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      title: lang.aiSubtitleTranslateAfter,
      subtitle: lang.aiSubtitleTranslateAfterSubtitle,
      icon: Broken.translate,
      child: ObxO(
        rx: AiSubtitleConfig.inst.translateAfterRecognition,
        builder: (context, bool value) => CustomSwitchListTile(
          icon: Broken.translate,
          title: lang.aiSubtitleTranslateAfter,
          value: value,
          onChanged: (isTrue) {
            AiSubtitleConfig.inst.translateAfterRecognition.save(!isTrue);
            AiSubtitleConfig.inst.save();
          },
        ),
      ),
    );
  }
}
