import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nampack/nampack.dart';

import 'package:namida/class/track.dart';
import 'package:namida/controller/ai_subtitle/ai_subtitle_config.dart';
import 'package:namida/controller/ai_subtitle/ai_subtitle_tasks.dart';
import 'package:namida/controller/navigator_controller.dart';
import 'package:namida/core/constants.dart';
import 'package:namida/core/extensions.dart';
import 'package:namida/core/icon_fonts/broken_icons.dart';
import 'package:namida/core/translations/language.dart';
import 'package:namida/ui/pages/ai_subtitle/ai_subtitle_tasks_page.dart';
import 'package:namida/ui/widgets/custom_widgets.dart';

/// Asks what should be done with the selected tracks, then runs it.
///
/// This is the single entry point used by the track menus: the three actions
/// are mutually exclusive (transcribe, translate what already exists, or both)
/// and putting them in one place keeps the menus from growing three items each.
void showAiSubtitleActionChooser(List<Selectable> tracks) {
  if (tracks.isEmpty) return;

  final files = _localFilesOf(tracks);
  if (files.isEmpty) {
    snackyy(message: lang.aiSubtitleNoLocalAudio, isError: true);
    return;
  }

  NamidaNavigator.inst.navigateDialog(
    dialogBuilder: (theme) => CustomBlurryDialog(
      theme: theme,
      normalTitleStyle: true,
      title: lang.aiSubtitleChooseAction,
      actions: const [
        CancelButton(addMargin: false),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomListTile(
            icon: Broken.record,
            title: lang.aiSubtitleActionTranscribe,
            subtitle: lang.aiSubtitleActionTranscribeSubtitle,
            onTap: () {
              NamidaNavigator.inst.closeDialog();
              enqueueAiSubtitleTasks(tracks, translateAfter: false);
            },
          ),
          CustomListTile(
            icon: Broken.translate,
            title: lang.aiSubtitleActionTranslate,
            subtitle: lang.aiSubtitleActionTranslateSubtitle,
            onTap: () {
              NamidaNavigator.inst.closeDialog();
              enqueueAiSubtitleTranslation(tracks);
            },
          ),
          CustomListTile(
            icon: Broken.text,
            title: lang.aiSubtitleActionTranscribeTranslate,
            subtitle: lang.aiSubtitleActionTranscribeTranslateSubtitle,
            onTap: () {
              NamidaNavigator.inst.closeDialog();
              enqueueAiSubtitleTasks(tracks, translateAfter: true);
            },
          ),
        ],
      ),
    ),
  );
}

/// Shared by the track menu entries: turns tracks into files, drops the ones
/// that are remote (there is no file to transcribe), then shows the queue.
void enqueueAiSubtitleTasks(List<Selectable> tracks, {required bool translateAfter}) {
  final files = _localFilesOf(tracks);
  if (files.isEmpty) {
    snackyy(message: lang.aiSubtitleNoLocalAudio, isError: true);
    return;
  }

  AiSubtitleConfig.inst.translateAfterRecognition.save(translateAfter);
  AiSubtitleTasksController.inst.enqueue(files, translateAfter: translateAfter);

  _openQueue();

  // -- nothing is configured yet, sending the user to the queue would just
  // -- show a failure, the settings say what is missing.
  if (!AiSubtitleConfig.inst.isAsrConfigured && !AiSubtitleConfig.inst.recognitionMode.value.isLocal) {
    snackyy(
      message: lang.aiSubtitleSetApiKeyFirst,
      isError: true,
    );
  }
}

/// Translates the subtitles the track already has, without recognizing again.
void enqueueAiSubtitleTranslation(List<Selectable> tracks) {
  final files = _localFilesOf(tracks);
  if (files.isEmpty) {
    snackyy(message: lang.aiSubtitleNoLocalAudioToTranslate, isError: true);
    return;
  }

  if (!AiSubtitleConfig.inst.isTranslationConfigured) {
    snackyy(message: lang.aiSubtitleSetTranslationKeyFirst, isError: true);
    return;
  }

  AiSubtitleTasksController.inst.enqueueTranslationOf(files);
  _openQueue();
}

List<File> _localFilesOf(List<Selectable> tracks) {
  final files = <File>[];
  for (final track in tracks) {
    final path = track.track.path;
    if (path.isEmpty || path.startsWith('http')) continue;
    files.add(File(path));
  }
  return files;
}

void _openQueue() {
  NamidaNavigator.inst.navigateToRoot(
    const AiSubtitleTasksPage(),
    transition: Transition.native,
  );
}
