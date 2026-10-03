import 'package:flutter/material.dart';
import 'package:nampack/nampack.dart';

import 'package:namida/controller/ai_subtitle/ai_subtitle_config.dart';
import 'package:namida/controller/ai_subtitle/ai_translation_service.dart';
import 'package:namida/controller/ai_subtitle/translators/ai_translator.dart';
import 'package:namida/controller/navigator_controller.dart';
import 'package:namida/core/extensions.dart';
import 'package:namida/core/icon_fonts/broken_icons.dart';
import 'package:namida/core/translations/language.dart';
import 'package:namida/ui/widgets/ai_subtitle_widgets.dart';
import 'package:namida/ui/widgets/custom_widgets.dart';
import 'package:namida/ui/widgets/settings_card.dart';

/// Translation settings: provider, target language and the style prompt.
class AiSubtitleTranslationPage extends StatefulWidget {
  const AiSubtitleTranslationPage({super.key});

  @override
  State<AiSubtitleTranslationPage> createState() => _AiSubtitleTranslationPageState();
}

class _AiSubtitleTranslationPageState extends State<AiSubtitleTranslationPage> {
  final _isTesting = false.obs;
  final _testResult = Rxn<String>();
  final _testFailed = false.obs;

  Future<void> _test() async {
    _isTesting.value = true;
    _testResult.value = null;

    try {
      await AiTranslationService().testConnection(AiSubtitleConfig.inst.translationSettings);
      _testResult.value = lang.aiSubtitleConnectionSucceeded;
      _testFailed.value = false;
    } catch (e) {
      _testResult.value = e.toString();
      _testFailed.value = true;
    } finally {
      _isTesting.value = false;
    }
  }
  @override
  Widget build(BuildContext context) {
    return AiSubtitlePage(
      standalone: true,
      title: lang.aiSubtitleTranslation,
      subtitle: lang.aiSubtitleTranslationSubtitle,
      icon: Broken.translate,
      children: [
        _providerCard(),
        const SizedBox(height: 12.0),
        _traditionalCard(),
        const SizedBox(height: 12.0),
        _languageCard(),
        const SizedBox(height: 12.0),
        _styleCard(),
      ],
    );
  }

  Widget _providerCard() {
    return SettingsCard(
      title: 'Translation provider',
      subtitle: 'OpenAI compatible, Gemini',
      icon: Broken.cloud,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ObxO(
        rx: AiSubtitleConfig.inst.revision,
        builder: (context, _) => AiSubtitlePills<AiApiProvider>(
                values: AiApiProvider.values,
                selected: AiSubtitleConfig.inst.translationProvider.value,
                labelOf: (e) => e.label,
                onSelected: (value) {
                  AiSubtitleConfig.inst.applyTranslationProvider(value);
                  AiSubtitleConfig.inst.save();
                },
              )),
          const SizedBox(height: 12.0),
          ObxO(
            rx: AiSubtitleConfig.inst.translationApiKey,
            builder: (context, String key) => CustomListTile(
              icon: Broken.key,
              title: lang.aiSubtitleApiKey,
              subtitle: key.isEmpty ? 'not set' : '••••••••${key.length > 4 ? key.substring(key.length - 4) : ''}',
              onTap: () => showAiSubtitleTextDialog(
                title: lang.aiSubtitleApiKey,
                label: lang.aiSubtitleApiKey,
                obscure: true,
                initialValue: key,
                onSubmit: (value) {
                  AiSubtitleConfig.inst.translationApiKey.save(value);
                  AiSubtitleConfig.inst.save();
                },
              ),
            ),
          ),
          ObxO(
            rx: AiSubtitleConfig.inst.translationModel,
            builder: (context, String model) => CustomListTile(
              icon: Broken.check,
              title: lang.aiSubtitleModelName,
              subtitle: model,
              onTap: () => showAiSubtitleTextDialog(
                title: lang.aiSubtitleModelName,
                label: 'Model',
                hintText: 'gpt-4o-mini',
                initialValue: model,
                onSubmit: (value) {
                  AiSubtitleConfig.inst.translationModel.save(value);
                  AiSubtitleConfig.inst.save();
                },
              ),
            ),
          ),
          ObxO(
            rx: AiSubtitleConfig.inst.translationBaseUrl,
            builder: (context, String baseUrl) => CustomListTile(
              icon: Broken.link,
              title: lang.aiSubtitleBaseUrl,
              subtitle: baseUrl.isEmpty ? AiSubtitleConfig.inst.translationProvider.value.defaultBaseUrl : baseUrl,
              onTap: () => showAiSubtitleTextDialog(
                title: lang.aiSubtitleBaseUrl,
                label: lang.aiSubtitleBaseUrl,
                hintText: AiSubtitleConfig.inst.translationProvider.value.defaultBaseUrl,
                subtitle: lang.aiSubtitleBaseUrlSubtitle,
                initialValue: baseUrl,
                onSubmit: (value) {
                  AiSubtitleConfig.inst.translationBaseUrl.save(value);
                  AiSubtitleConfig.inst.save();
                },
              ),
            ),
          ),
          const SizedBox(height: 8.0),
          Row(
            children: [
              ObxO(
                rx: _isTesting,
                builder: (context, isTesting) => NamidaButton(
                  text: lang.aiSubtitleTranslation,
                  isLoading: isTesting,
                  enabled: !isTesting,
                  onTap: () {
                    AiSubtitleConfig.inst.save();
                    _test();
                  },
                ),
              ),
              const SizedBox(width: 8.0),
              ObxO(
                rx: _isTesting,
                builder: (context, isTesting) => NamidaButton(
                  text: lang.aiSubtitleTestConnection,
                  enabled: !isTesting,
                  onTap: _test,
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
        ],
      ),
    );
  }
  /// 显示传统引擎开关，并让已启用项按拖动顺序保存优先级。
  Widget _traditionalCard() {
    return SettingsCard(
      title: '传统',
      subtitle: '无需 API Key，列表顺序就是优先级',
      icon: Broken.translate,
      child: ObxO(
        rx: AiSubtitleConfig.inst.enabledTraditionalEngines,
        builder: (context, List<AiTranslatorId> enabled) {
          final active = enabled.toList();
          final inactive = AiTranslatorId.values.where((engine) => !active.contains(engine)).toList();

          void save(List<AiTranslatorId> value) {
            AiSubtitleConfig.inst.enabledTraditionalEngines.replace(value);
            AiSubtitleConfig.inst.save();
          }

          return Column(
            children: [
              if (active.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text('未启用传统引擎，当前将使用 API 翻译。', style: context.textTheme.bodySmall),
                  ),
                ),
              if (active.isNotEmpty)
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: active.length,
                  buildDefaultDragHandles: false,
                  onReorder: (oldIndex, newIndex) {
                    if (newIndex > oldIndex) newIndex--;
                    final reordered = active.toList();
                    final moved = reordered.removeAt(oldIndex);
                    reordered.insert(newIndex, moved);
                    save(reordered);
                  },
                  itemBuilder: (context, index) {
                    final engine = active[index];
                    return _traditionalEngineTile(
                      key: ValueKey('traditional-${engine.id}'),
                      engine: engine,
                      subtitle: '优先级 ${index + 1}',
                      value: true,
                      trailing: ReorderableDragStartListener(
                        index: index,
                        child: const Icon(Broken.menu),
                      ),
                      onChanged: (value) {
                        if (!value) save(active.toList()..remove(engine));
                      },
                    );
                  },
                ),
              for (final engine in inactive)
                _traditionalEngineTile(
                  key: ValueKey('traditional-${engine.id}'),
                  engine: engine,
                  subtitle: '未启用',
                  value: false,
                  onChanged: (value) {
                    if (value) save([...active, engine]);
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  /// 构建单个传统引擎开关行。
  Widget _traditionalEngineTile({
    required Key key,
    required AiTranslatorId engine,
    required String subtitle,
    required bool value,
    required void Function(bool value) onChanged,
    Widget? trailing,
  }) {
    return CustomListTile(
      key: key,
      icon: Broken.translate,
      title: engine.label,
      subtitle: subtitle,
      trailingRaw: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailing != null) ...[
            trailing,
            const SizedBox(width: 8.0),
          ],
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
  Widget _languageCard() {
    return SettingsCard(
      title: lang.aiSubtitleTargetLanguage,
      subtitle: 'Simplified Chinese, English, Japanese...',
      icon: Broken.translate,
      child: ObxO(
        rx: AiSubtitleConfig.inst.targetLanguage,
        builder: (context, AiSubtitleTargetLanguage language) => AiSubtitlePills<AiSubtitleTargetLanguage>(
          values: AiSubtitleTargetLanguage.values,
          selected: language,
          labelOf: (e) => e.label,
          onSelected: (value) {
            AiSubtitleConfig.inst.targetLanguage.save(value);
            AiSubtitleConfig.inst.save();
          },
        ),
      ),
    );
  }

  Widget _styleCard() {
    return SettingsCard(
      title: lang.aiSubtitleStylePrompt,
      subtitle: lang.aiSubtitleStylePromptSubtitle,
      icon: Broken.sms_edit,
      child: Column(
        children: [
          ObxO(
            rx: AiSubtitleConfig.inst.translationStylePrompt,
            builder: (context, String prompt) => CustomListTile(
              icon: Broken.text,
              title: lang.aiSubtitleStylePrompt,
              subtitle: prompt.isEmpty ? 'empty' : prompt,
              onTap: () => showAiSubtitleTextDialog(
                title: lang.aiSubtitleStylePrompt,
                label: 'Style',
                maxLines: 4,
                hintText: 'casual, short lines, keep the tone of the song',
                subtitle: lang.aiSubtitleStyleFormatNote,
                initialValue: prompt,
                onSubmit: (value) {
                  AiSubtitleConfig.inst.translationStylePrompt.save(value);
                  AiSubtitleConfig.inst.save();
                },
              ),
            ),
          ),
          ObxO(
            rx: AiSubtitleConfig.inst.saveLocation,
            builder: (context, AiSubtitleSaveLocation location) => CustomListTile(
              icon: Broken.save_2,
              title: lang.aiSubtitleSaveLocation,
              trailingText: location.label,
              onTap: () => NamidaNavigator.inst.navigateDialog(
                dialog: CustomBlurryDialog(
                  title: lang.aiSubtitleSaveLocation,
                  normalTitleStyle: true,
                  actions: const [DoneButton()],
                  child: SizedBox(
                    width: context.width,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final option in AiSubtitleSaveLocation.values)
                          ObxO(
                            rx: AiSubtitleConfig.inst.saveLocation,
                            builder: (context, AiSubtitleSaveLocation current) => ListTileWithCheckMark(
                              title: option.label,
                              active: current == option,
                              onTap: () {
                                AiSubtitleConfig.inst.saveLocation.save(option);
                                AiSubtitleConfig.inst.save();
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          ObxO(
            rx: AiSubtitleConfig.inst.translateAfterRecognition,
            builder: (context, bool value) => CustomSwitchListTile(
              icon: Broken.play,
              title: 'Translate right after recognition',
              subtitle: 'The translation runs as soon as the cues exist',
              value: value,
              onChanged: (isTrue) {
                AiSubtitleConfig.inst.translateAfterRecognition.save(!isTrue);
                AiSubtitleConfig.inst.save();
              },
            ),
          ),
        ],
      ),
    );
  }
}
