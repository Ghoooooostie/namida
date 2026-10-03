import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nampack/nampack.dart';

import 'package:namida/controller/ai_subtitle/ai_subtitle_config.dart';
import 'package:namida/controller/ai_subtitle/ai_subtitle_models.dart';
import 'package:namida/controller/ai_subtitle/ai_subtitle_tasks.dart';
import 'package:namida/controller/file_browser.dart';
import 'package:namida/controller/navigator_controller.dart';
import 'package:namida/controller/platform/namida_storage/namida_storage.dart';
import 'package:namida/core/constants.dart';
import 'package:namida/core/extensions.dart';
import 'package:namida/core/icon_fonts/broken_icons.dart';
import 'package:namida/core/translations/language.dart';
import 'package:namida/ui/pages/ai_subtitle/ai_subtitle_models_page.dart';
import 'package:namida/ui/pages/ai_subtitle/ai_subtitle_recognition_page.dart';
import 'package:namida/ui/pages/ai_subtitle/ai_subtitle_tasks_page.dart';
import 'package:namida/ui/pages/ai_subtitle/ai_subtitle_translation_page.dart';
import 'package:namida/ui/widgets/ai_subtitle_widgets.dart';
import 'package:namida/ui/widgets/custom_widgets.dart';
import 'package:namida/ui/widgets/settings_card.dart';

/// The entry point, mirroring the reference design:
///
///   字幕识别
///     识别设置（Vosk）
///     识别并翻译（本地）
///     识别字幕（本地）
///     翻译字幕
///
/// Every action but the settings one first asks where the audio is, so a single
/// entry covers both "one file" and "a whole folder" (batch).
class AiSubtitleCenterPage extends StatelessWidget {
  const AiSubtitleCenterPage({super.key});

  /// Asks for audio files or a folder, then hands the files to [onPicked].
  static void pickSourceThen(void Function(List<File> files) onPicked) {
    NamidaNavigator.inst.navigateDialog(
      dialogBuilder: (theme) => CustomBlurryDialog(
        theme: theme,
        normalTitleStyle: true,
        title: lang.aiSubtitleSource,
        bodyText: lang.aiSubtitleSourceSubtitle,
        actions: const [
          CancelButton(addMargin: false),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomListTile(
              icon: Broken.audio_square,
              title: lang.aiSubtitlePickAudio,
              subtitle: lang.aiSubtitlePickAudioSubtitle,
              onTap: () async {
                NamidaNavigator.inst.closeDialog();
                final files = await NamidaFileBrowser.pickFiles(
                  note: lang.aiSubtitlePickAudio,
                  memeType: NamidaStorageFileMemeType.audio,
                );
                if (files.isEmpty) return;
                onPicked(files);
              },
            ),
            CustomListTile(
              icon: Broken.folder_open,
              title: lang.aiSubtitlePickFolder,
              subtitle: lang.aiSubtitlePickFolderSubtitle,
              onTap: () async {
                NamidaNavigator.inst.closeDialog();
                onPicked(await _pickFolderFiles());
              },
            ),
          ],
        ),
      ),
    );
  }

  static Future<List<File>> _pickFolderFiles() async {
    final path = await NamidaFileBrowser.getDirectory(note: lang.aiSubtitlePickFolder);
    if (path == null) return const [];

    final dir = Directory(path);
    if (!dir.existsSync()) {
      snackyy(message: lang.aiSubtitleFolderMissing, isError: true);
      return const [];
    }

    final files = <File>[];
    try {
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File) continue;
        if (!NamidaFileExtensionsWrapper.audioAndVideo.isPathValid(entity.path)) continue;
        files.add(entity);
      }
    } catch (e) {
      snackyy(message: '${lang.error}: $e', isError: true);
      return const [];
    }

    if (files.isEmpty) {
      snackyy(message: lang.aiSubtitleNoAudioInFolder, isError: true);
      return const [];
    }

    return files;
  }

  void _run(List<File> files, {required bool translateAfter}) {
    if (files.isEmpty) return;
    AiSubtitleConfig.inst.translateAfterRecognition.save(translateAfter);
    AiSubtitleConfig.inst.save();
    AiSubtitleTasksController.inst.enqueue(files, translateAfter: translateAfter);

    NamidaNavigator.inst.navigateToRoot(
      const AiSubtitleTasksPage(),
      transition: Transition.native,
    );
  }

  void _runTranslation(List<File> files) {
    if (files.isEmpty) return;
    if (!AiSubtitleConfig.inst.isTranslationConfigured) {
      snackyy(message: lang.aiSubtitleSetTranslationKeyFirst, isError: true);
      return;
    }
    AiSubtitleTasksController.inst.enqueueTranslationOf(files);
    NamidaNavigator.inst.navigateToRoot(
      const AiSubtitleTasksPage(),
      transition: Transition.native,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AiSubtitlePage(
      title: lang.aiSubtitles,
      subtitle: lang.aiSubtitleCenterSubtitle,
      icon: Broken.record,
      children: [
        _recognitionCard(),
        const SizedBox(height: 12.0),
        _statusCard(),
        const SizedBox(height: 12.0),
        _queueCard(),
        const SizedBox(height: 12.0),
        _modelsCard(),
      ],
    );
  }

  Widget _recognitionCard() {
    return SettingsCard(
      title: lang.aiSubtitleRecognition,
      subtitle: lang.aiSubtitleRecognitionSubtitle,
      icon: Broken.microphone,
      child: Column(
        children: [
          CustomListTile(
            icon: Broken.settings,
            title: lang.aiSubtitleRecognitionSettings,
            onTap: () => NamidaNavigator.inst.navigateToRoot(
              const AiSubtitleRecognitionPage(),
              transition: Transition.native,
            ),
          ),
          CustomListTile(
            icon: Broken.text,
            title: lang.aiSubtitleActionTranscribeTranslateLocal,
            subtitle: lang.aiSubtitleActionTranscribeTranslateSubtitle,
            onTap: () => pickSourceThen((files) => _run(files, translateAfter: true)),
          ),
          CustomListTile(
            icon: Broken.record,
            title: lang.aiSubtitleActionTranscribeLocal,
            subtitle: lang.aiSubtitleActionTranscribeSubtitle,
            onTap: () => pickSourceThen((files) => _run(files, translateAfter: false)),
          ),
          CustomListTile(
            icon: Broken.translate,
            title: lang.aiSubtitleActionTranslate,
            subtitle: lang.aiSubtitleActionTranslateSubtitle,
            onTap: () => pickSourceThen(_runTranslation),
          ),
        ],
      ),
    );
  }

  Widget _queueCard() {
    return SettingsCard(
      title: lang.aiSubtitleOpenTaskList,
      subtitle: lang.aiSubtitleTaskListSubtitle,
      icon: Broken.music_playlist,
      child: Column(
        children: [
          CustomListTile(
            icon: Broken.play,
            title: lang.aiSubtitleOpenTaskList,
            trailingText: _pendingText(),
            onTap: () => NamidaNavigator.inst.navigateToRoot(
              const AiSubtitleTasksPage(),
              transition: Transition.native,
            ),
          ),
        ],
      ),
    );
  }

  static String _pendingText() {
    final pending = AiSubtitleTasksController.inst.pendingTasks.length;
    if (pending == 0) return lang.aiSubtitleQueueEmpty;
    return '$pending ${lang.aiSubtitleQueueQueued}';
  }

  Widget _statusCard() {
    return ObxO(
      rx: AiSubtitleConfig.inst.revision,
      builder: (context, _) {
      final config = AiSubtitleConfig.inst;
      final isLocal = config.recognitionMode.value.isLocal;
      final ready = isLocal ? true : config.isAsrConfigured;

      return SettingsCard(
        title: lang.aiSubtitleReadiness,
        subtitle: isLocal ? lang.aiSubtitleOnDevice : lang.aiSubtitleApiRecognition,
        icon: ready ? Broken.check : Broken.danger,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isLocal
                  ? '${lang.aiSubtitleEngine}: ${config.localEngine.value.label}'
                      '${config.localEngine.value.isAvailable ? '' : ' (${lang.aiSubtitleNotWiredUp})'}'
                  : '${lang.aiSubtitleProvider}: ${config.asrProvider.value.label}',
              style: context.textTheme.bodySmall,
            ),
            const SizedBox(height: 4.0),
            Text(
              ready ? lang.aiSubtitleReady : lang.aiSubtitleNotConfigured,
              style: context.textTheme.bodySmall?.copyWith(
                color: ready ? null : context.theme.colorScheme.error,
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _modelsCard() {
    return SettingsCard(
      title: lang.aiSubtitleLocalModels,
      subtitle: lang.aiSubtitleSettingsSubtitle,
      icon: Broken.settings,
      child: Column(
        children: [
          CustomListTile(
            icon: Broken.document_download,
            title: lang.aiSubtitleLocalModels,
            trailingText: '${AiSubtitleModels.voskModels.length}',
            onTap: () => NamidaNavigator.inst.navigateToRoot(
              const AiSubtitleModelsPage(),
              transition: Transition.native,
            ),
          ),
          CustomListTile(
            icon: Broken.translate,
            title: lang.aiSubtitleTranslation,
            onTap: () => NamidaNavigator.inst.navigateToRoot(
              const AiSubtitleTranslationPage(),
              transition: Transition.native,
            ),
          ),
        ],
      ),
    );
  }
}
