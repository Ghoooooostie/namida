import 'package:flutter/material.dart';
import 'package:nampack/nampack.dart';

import 'package:namida/controller/ai_subtitle/ai_subtitle_config.dart';
import 'package:namida/controller/ai_subtitle/ai_subtitle_models.dart';
import 'package:namida/controller/navigator_controller.dart';
import 'package:namida/core/icon_fonts/broken_icons.dart';
import 'package:namida/core/translations/language.dart';
import 'package:namida/packages/three_arched_circle.dart';
import 'package:namida/ui/widgets/ai_subtitle_widgets.dart';
import 'package:namida/ui/widgets/custom_widgets.dart';
import 'package:namida/ui/widgets/settings_card.dart';

/// Downloads & removes the local recognition models.
///
/// Two runtimes side by side: the vosk plugin models (zip from alphacephei) and
/// the sherpa-onnx ones (individual files from huggingface, hf-mirror.com as the
/// fallback channel). Picking a model also switches the engine that runs it.
class AiSubtitleModelsPage extends StatefulWidget {
  const AiSubtitleModelsPage({super.key});

  @override
  State<AiSubtitleModelsPage> createState() => _AiSubtitleModelsPageState();
}

class _AiSubtitleModelsPageState extends State<AiSubtitleModelsPage> {
  final _installed = <String>{}.obs;
  final _sizes = <String, String>{}.obs;
  var _isBusy = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final installed = await AiSubtitleModels.installedModelNames();
    final sizes = <String, String>{};
    for (final name in installed) {
      sizes[name] = await AiSubtitleModels.modelSizeText(name);
    }

    if (!mounted) return;
    setState(() {
      _installed.value = installed;
      _sizes.value = sizes;
      _isBusy = false;
    });
  }

  Future<void> _downloadVosk(VoskModelInfo info) async {
    final path = await AiSubtitleModels.downloadVoskModel(info);
    await _refresh();

    if (!mounted) return;
    snackyy(
      message: path == null ? (AiSubtitleModels.downloadError.value ?? 'download failed') : '${info.label} is ready',
      isError: path == null,
    );
  }

  Future<void> _downloadSherpa(AiLocalModelInfo info) async {
    final path = await AiSubtitleModels.downloadSherpaModel(info);
    await _refresh();

    if (!mounted) return;
    snackyy(
      message: path == null ? (AiSubtitleModels.downloadError.value ?? 'download failed') : '${info.label} is ready',
      isError: path == null,
    );
  }

  Future<void> _delete(String name) async {
    final ok = await AiSubtitleModels.deleteModel(name);
    await _refresh();
    if (!mounted) return;
    if (!ok) snackyy(message: lang.aiSubtitleDeleteFailed, isError: true);
  }

  void _useModel(String name, AiLocalAsrEngine engine) {
    final config = AiSubtitleConfig.inst;
    config.localEngine.save(engine);
    config.localModelName.save(name);
    config.save();
  }

  @override
  Widget build(BuildContext context) {
    return AiSubtitlePage(
      standalone: true,
      title: lang.aiSubtitleLocalModels,
      icon: Broken.document_download,
      children: [
        ObxO(
          rx: AiSubtitleModels.isDownloading,
          builder: (context, isDownloading) => isDownloading
              ? ObxO(
                  rx: AiSubtitleModels.downloadProgress,
                  builder: (context, progress) => Padding(
                    padding: const EdgeInsets.only(bottom: 4.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LinearProgressIndicator(value: progress > 0 ? progress : null),
                        const SizedBox(height: 4.0),
                        ObxO(
                          rx: AiSubtitleModels.downloadingModelName,
                          builder: (context, name) => Text(
                            '${(progress * 100).round()}% · $name',
                            style: context.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        ObxO(
          rx: AiSubtitleModels.downloadError,
          builder: (context, error) => error == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Text(
                    error,
                    style: context.textTheme.bodySmall?.copyWith(color: context.theme.colorScheme.error),
                  ),
                ),
        ),
        _isBusy
            ? Padding(
                padding: const EdgeInsets.all(24.0),
                child: Center(
                  child: ThreeArchedCircle(color: context.theme.primaryColor, size: 32.0),
                ),
              )
            : ObxO(
                rx: _installed,
                builder: (context, Set<String> installed) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ..._section(context, 'sherpa-onnx'),
                    for (final info in AiSubtitleModels.sherpaModels) ...[
                      _ModelTile(
                        label: info.label,
                        note: info.note,
                        engine: info.engine,
                        isInstalled: installed.contains(info.name),
                        isSelected: AiSubtitleConfig.inst.localModelName.value == info.name,
                        sizeText: _sizes[info.name] ?? info.sizeText,
                        onDownload: () => _downloadSherpa(info),
                        onDelete: () => _delete(info.name),
                        onUse: () => _useModel(info.name, info.engine),
                      ),
                      const SizedBox(height: 8.0),
                    ],
                    ..._section(context, 'Vosk'),
                    for (final info in AiSubtitleModels.voskModels) ...[
                      _ModelTile(
                        label: info.label,
                        note: info.note,
                        engine: AiLocalAsrEngine.vosk,
                        isInstalled: installed.contains(info.name),
                        isSelected: AiSubtitleConfig.inst.localModelName.value == info.name,
                        sizeText: _sizes[info.name] ?? info.sizeText,
                        onDownload: () => _downloadVosk(info),
                        onDelete: () => _delete(info.name),
                        onUse: () => _useModel(info.name, AiLocalAsrEngine.vosk),
                      ),
                      const SizedBox(height: 8.0),
                    ],
                  ],
                ),
              ),
        const SizedBox(height: 8.0),
        Text(
          'SenseVoice & Paraformer models are fetched from huggingface (hf-mirror.com as a fallback), '
          'vosk models from alphacephei.com. Everything unpacks into the app data folder.',
          style: context.textTheme.bodySmall,
        ),
      ],
    );
  }

  List<Widget> _section(BuildContext context, String title) {
    return [
      Padding(
        padding: const EdgeInsets.only(top: 6.0, bottom: 2.0),
        child: Text(title, style: context.textTheme.titleSmall),
      ),
      const SizedBox(height: 6.0),
    ];
  }
}

class _ModelTile extends StatelessWidget {
  final String label;
  final String? note;
  final AiLocalAsrEngine engine;
  final bool isInstalled;
  final bool isSelected;
  final String sizeText;
  final VoidCallback onDownload;
  final VoidCallback onDelete;
  final VoidCallback onUse;

  const _ModelTile({
    required this.label,
    required this.note,
    required this.engine,
    required this.isInstalled,
    required this.isSelected,
    required this.sizeText,
    required this.onDownload,
    required this.onDelete,
    required this.onUse,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      isInstalled ? 'installed${sizeText.isEmpty ? '' : ' · $sizeText'}' : sizeText,
      if (isSelected) 'in use' else null,
      if (note != null) note!,
    ].whereType<String>().join(' · ');

    return SettingsCard(
      title: label,
      subtitle: subtitle,
      icon: isInstalled ? Broken.check : Broken.document_download,
      child: Row(
        children: [
          if (isInstalled)
            NamidaButton(text: lang.aiSubtitleReDownload, onTap: onDownload)
          else
            NamidaButton(text: lang.aiSubtitleDownload, onTap: onDownload),
          const SizedBox(width: 8.0),
          if (isInstalled) NamidaButton(text: lang.aiSubtitleDelete, onTap: onDelete),
          if (isInstalled && !isSelected) ...[
            const SizedBox(width: 8.0),
            NamidaButton(
              text: lang.aiSubtitleUse,
              onTap: onUse,
            ),
          ],
        ],
      ),
    );
  }
}
