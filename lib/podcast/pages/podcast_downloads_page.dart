import 'package:flutter/material.dart';
import 'package:nampack/nampack.dart';

import 'package:namida/controller/navigator_controller.dart';
import 'package:namida/class/route.dart';
import 'package:namida/core/enums.dart';
import 'package:namida/core/extensions.dart';
import 'package:namida/core/icon_fonts/broken_icons.dart';
import 'package:namida/core/themes.dart';
import 'package:namida/podcast/class/podcast.dart';
import 'package:namida/podcast/controller/podcast_downloads_controller.dart';
import 'package:namida/podcast/pages/podcast_settings_page.dart';
import 'package:namida/podcast/widgets/podcast_widgets.dart';
import 'package:namida/ui/widgets/custom_widgets.dart';

/// 下载/离线列表的内容部分。可直接嵌进 Tab，也可用 [PodcastDownloadsPage] 单独开页面。
class PodcastDownloadsView extends StatelessWidget {
  const PodcastDownloadsView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final textTheme = theme.textTheme;
    final downloads = PodcastDownloadsController.inst;

    return ObxO(
      rx: downloads.tasks,
      builder: (context, _) {
        final tasks = downloads.allTasks;

        if (tasks.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Broken.document_download, size: 44.0, color: textTheme.displaySmall?.color),
                const SizedBox(height: 12.0),
                Text('Nothing downloaded yet', style: textTheme.bodySmall),
                const SizedBox(height: 4.0),
                Text(
                  'Tap the download icon on any episode to keep it offline',
                  textAlign: TextAlign.center,
                  style: textTheme.displaySmall,
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 10.0, 6.0, 2.0),
              child: Row(
                children: [
                  Expanded(child: Text('${tasks.length} downloads', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
                  // -- 播放全部（按下载列表顺序拼成队列）
                  NamidaIconButton(
                    icon: Broken.play_circle,
                    iconSize: 22.0,
                    onPressed: () {
                      final episodes = _downloadedEpisodes();
                      if (episodes.isEmpty) {
                        snackyy(message: 'Nothing downloaded to play yet', isError: true);
                        return;
                      }
                      playPodcastEpisodes(episodes, source: QueueSourcePodcast.downloads);
                    },
                  ),
                  // -- 全部加入队列（不打断当前播放）
                  NamidaIconButton(
                    icon: Broken.play_add,
                    iconSize: 22.0,
                    onPressed: () {
                      final episodes = _downloadedEpisodes();
                      if (episodes.isEmpty) {
                        snackyy(message: 'Nothing downloaded to queue yet', isError: true);
                        return;
                      }
                      addPodcastEpisodesToQueue(episodes);
                    },
                  ),
                  NamidaIconButton(
                    icon: Broken.settings,
                    iconSize: 20.0,
                    onPressed: () => const PodcastSettingsPage().navigate(),
                  ),
                  NamidaIconButton(
                    icon: Broken.trash,
                    iconSize: 20.0,
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Remove all downloads?'),
                          content: const Text('Downloaded files will be deleted from this device.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
                          ],
                        ),
                      );
                      if (confirmed == true) await downloads.removeAllCompleted();
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.only(bottom: 120.0),
                itemCount: tasks.length,
                separatorBuilder: (_, __) => const Divider(height: 1.0, indent: 20.0),
                itemBuilder: (context, i) => _row(tasks[i], theme, textTheme),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 已下载完成的单集，按下载列表的显示顺序（即加入下载的先后）。
  List<PodcastEpisode> _downloadedEpisodes() {
    return PodcastDownloadsController.inst.completedTasks.map((t) => t.toEpisode()).where((e) => e.isPlayable).toList();
  }

  /// 播放全部时定位到被点击的那一集，让上下文（前后单集）也能连续播。
  List<PodcastEpisode> _allPlayable(String episodeId) {
    final all = _downloadedEpisodes();
    final index = all.indexWhere((e) => e.id == episodeId);
    if (index < 0) return all;
    return [
      all[index],
      ...all.sublist(0, index),
      ...all.sublist(index + 1),
    ];
  }

  Widget _row(PodcastDownloadInfo task, ThemeData theme, TextTheme textTheme) {
    final downloads = PodcastDownloadsController.inst;

    final statusText = switch (task.state) {
      PodcastDownloadState.downloading => '${(task.progress * 100).round()}%  •  ${task.downloadedBytes.fileSizeFormatted} / ${task.totalBytes.fileSizeFormatted}',
      PodcastDownloadState.done => '${task.totalBytes.fileSizeFormatted}  •  offline',
      PodcastDownloadState.failed => 'Failed: ${task.errorText ?? 'unknown'}',
      PodcastDownloadState.none => task.localPath ?? 'pending',
    };

    final episode = task.toEpisode();
    final playable = task.state == PodcastDownloadState.done && episode.isPlayable;

    return ListTile(
      // -- 点一下直接用本地文件播放（已下载的走离线）。
      onTap: playable ? () => playPodcastEpisodes(_allPlayable(task.episodeId), source: QueueSourcePodcast.downloads) : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
      title: Text(task.episodeTitle.isEmpty ? 'Untitled' : task.episodeTitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: textTheme.bodyMedium),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (task.showTitle.isNotEmpty)
            Text(task.showTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.displaySmall),
          const SizedBox(height: 4.0),
          Text(statusText, style: textTheme.displaySmall?.copyWith(color: task.state == PodcastDownloadState.failed ? theme.colorScheme.error : null)),
          if (task.state == PodcastDownloadState.downloading)
            Padding(
              padding: const EdgeInsets.only(top: 6.0),
              child: LinearProgressIndicator(value: task.totalBytes > 0 ? task.progress : null, minHeight: 3.0),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (task.state == PodcastDownloadState.downloading)
            NamidaIconButton(icon: Broken.close_square, iconSize: 20.0, onPressed: () => downloads.cancel(task.episodeId))
          else if (task.state == PodcastDownloadState.failed)
            NamidaIconButton(icon: Broken.refresh, iconSize: 20.0, onPressed: () => downloads.retry(task.episodeId))
          else
            NamidaIconButton(icon: Broken.trash, iconSize: 20.0, onPressed: () => downloads.remove(task.episodeId)),
        ],
      ),
    );
  }
}

class PodcastDownloadsPage extends StatelessWidget with NamidaRouteWidget {
  @override
  RouteType get route => RouteType.PODCAST_DOWNLOADS_SUBPAGE;

  @override
  String? get name => 'Downloads';

  const PodcastDownloadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const BackgroundWrapper(child: PodcastDownloadsView());
  }
}