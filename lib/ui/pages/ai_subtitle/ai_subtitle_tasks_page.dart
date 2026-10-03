import 'package:flutter/material.dart';
import 'package:nampack/nampack.dart';

import 'package:namida/controller/ai_subtitle/ai_subtitle_tasks.dart';
import 'package:namida/controller/navigator_controller.dart';
import 'package:namida/core/icon_fonts/broken_icons.dart';
import 'package:namida/core/translations/language.dart';
import 'package:namida/ui/pages/ai_subtitle/ai_subtitle_recognition_page.dart';
import 'package:namida/ui/widgets/ai_subtitle_widgets.dart';
import 'package:namida/ui/widgets/custom_widgets.dart';
import 'package:namida/ui/widgets/settings_card.dart';

/// The queue: what is pending, what failed, and where the results landed.
class AiSubtitleTasksPage extends StatelessWidget {
  const AiSubtitleTasksPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AiSubtitlePage(
      standalone: true,
      title: lang.aiSubtitleTaskList,
      icon: Broken.music_playlist,
      children: [
        _controlsCard(),
        const SizedBox(height: 12.0),
        ObxO(
          rx: AiSubtitleTasksController.inst.tasks,
          builder: (context, _) {
            final all = AiSubtitleTasksController.inst.allTasks;
            if (all.isEmpty) {
              return SettingsCard(
                title: lang.aiSubtitleNothingQueued,
                subtitle: lang.aiSubtitleNothingQueuedSubtitle,
                icon: Broken.music_playlist,
                child: const SizedBox.shrink(),
              );
            }

            return Column(
              children: [
                for (final task in all) ...[
                  _TaskTile(task: task),
                  const SizedBox(height: 8.0),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _controlsCard() {
    return ObxO(
      // -- the queue's observables are also created outside of any builder, so
      // -- they have to be subscribed explicitly (see AiSubtitleConfig.save).
      rx: AiSubtitleTasksController.inst.isRunning,
      builder: (context, isRunning) {
        final controller = AiSubtitleTasksController.inst;
        final hasPending = controller.pendingTasks.isNotEmpty;
        final blockReason = controller.blockReason.value;

        return SettingsCard(
          title: lang.aiSubtitleQueue,
          subtitle: '${controller.pendingTasks.length} pending · ${controller.doneCount} done · ${controller.failedCount} failed',
          icon: Broken.document_download,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // -- without this the tasks just sit at 0% and look like they are working.
              if (blockReason != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        blockReason,
                        style: context.textTheme.bodySmall?.copyWith(color: context.theme.colorScheme.error),
                      ),
                      const SizedBox(height: 8.0),
                      NamidaTextButton(
                        text: lang.aiSubtitleRecognitionSettings,
                        onTap: () => NamidaNavigator.inst.navigateToRoot(
                          const AiSubtitleRecognitionPage(),
                          transition: Transition.native,
                        ),
                      ),
                    ],
                  ),
                ),
              Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                children: [
                  NamidaButton(
                    text: isRunning ? lang.aiSubtitleWorking : lang.aiSubtitleStart,
                    icon: Broken.play,
                    isLoading: isRunning,
                    enabled: hasPending && !isRunning,
                    onTap: () => controller.run(),
                  ),
                  NamidaButton(
                    text: lang.aiSubtitleCancel,
                    icon: Broken.close_circle,
                    enabled: isRunning,
                    onTap: controller.cancel,
                  ),
                  NamidaButton(
                    text: lang.aiSubtitleClearFinished,
                    icon: Broken.profile_delete,
                    enabled: !isRunning,
                    onTap: controller.clearFinished,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TaskTile extends StatelessWidget {
  final AiSubtitleTask task;
  const _TaskTile({required this.task});

  @override
  Widget build(BuildContext context) {
    // -- two explicit subscriptions: the state drives the label, the progress
    // -- drives the bar. a bare `Obx` would miss both, they are created when the
    // -- task is built, outside of any builder.
    return ObxO(
      rx: task.state,
      builder: (context, state) => ObxO(
        rx: task.progress,
        builder: (context, progress) {
          final label = switch (state) {
            AiSubtitleTaskState.queued => (lang.aiSubtitleStateQueued, Broken.clock),
            AiSubtitleTaskState.running => (lang.aiSubtitleStateRunning, Broken.document_download),
            AiSubtitleTaskState.done => (lang.aiSubtitleStateDone, Broken.check),
            AiSubtitleTaskState.failed => (lang.aiSubtitleStateFailed, Broken.danger),
            AiSubtitleTaskState.cancelled => (lang.aiSubtitleStateCancelled, Broken.close_circle),
          };

          final savedPath = task.savedFile.value?.path;
          final error = task.errorMessage.value;
          final isActive = state == AiSubtitleTaskState.queued || state == AiSubtitleTaskState.running;

          return SettingsCard(
            title: task.title,
            subtitle: [
              task.translateOnly ? lang.aiSubtitleTranslatingExisting : label.$1,
              if (savedPath != null) lang.aiSubtitleSavedNextToTrack,
              if (error != null) error,
            ].whereType<String>().join(' · '),
            icon: label.$2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 10.0),
                Row(
                  children: [
                    Text('${(progress * 100).round()}%', style: context.textTheme.bodySmall),
                    const Spacer(),
                    if (!isActive)
                      NamidaButton(
                        text: lang.delete,
                        icon: Broken.profile_delete,
                        onTap: () => AiSubtitleTasksController.inst.remove(task),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
