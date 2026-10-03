import 'package:flutter/material.dart';
import 'package:nampack/nampack.dart';

import 'package:namida/controller/navigator_controller.dart';
import 'package:namida/class/route.dart';
import 'package:namida/controller/player_controller.dart';
import 'package:namida/core/enums.dart';
import 'package:namida/core/extensions.dart';
import 'package:namida/core/icon_fonts/broken_icons.dart';
import 'package:namida/core/themes.dart';
import 'package:namida/podcast/class/podcast.dart';
import 'package:namida/podcast/controller/podcast_controller.dart';
import 'package:namida/podcast/controller/podcast_downloads_controller.dart';
import 'package:namida/podcast/pages/podcast_show_page.dart';
import 'package:namida/ui/widgets/custom_widgets.dart';

// ---------------------------------------------------------------------------
// Playback helpers
// ---------------------------------------------------------------------------

/// 用一批单集替换当前队列并从 [index] 开始播放。
Future<void> playPodcastEpisodes(
  List<PodcastEpisode> episodes, {
  int index = 0,
  QueueSourceBase? source,
}) async {
  if (episodes.isEmpty) return;
  final playable = episodes.where((e) => e.isPlayable).toList();
  if (playable.isEmpty) {
    snackyy(message: 'No playable episode', isError: true);
    return;
  }
  final safeIndex = index.clampInt(0, playable.length - 1);
  await Player.inst.playOrPause(
    safeIndex,
    playable,
    source ?? QueueSourcePodcast.playerQueue,
    startPlaying: true,
  );
}

Future<void> playPodcastEpisode(PodcastEpisode episode, {QueueSourceBase? source}) {
  return playPodcastEpisodes([episode], source: source);
}

/// 把节目单全部加入队列尾部。
Future<void> addPodcastEpisodesToQueue(List<PodcastEpisode> episodes) async {
  await Player.inst.addToQueue(episodes.where((e) => e.isPlayable).toList());
}

// ---------------------------------------------------------------------------
// Artwork
// ---------------------------------------------------------------------------

class PodcastArtwork extends StatelessWidget {
  final String url;
  final double? size;
  final double borderRadius;

  /// [size] 传 `null` 表示填满父级约束（配合 [Expanded] 用，避免固定高度导致溢出）。
  const PodcastArtwork({
    super.key,
    required this.url,
    required this.size,
    this.borderRadius = 12.0,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius.multipliedRadius);
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.theme.cardColor,
        borderRadius: radius,
      ),
      child: Icon(
        Broken.headphones,
        size: (size ?? 48.0) * 0.4,
        color: context.theme.textTheme.displaySmall?.color,
      ),
    );

    if (url.isEmpty) return placeholder;

    final image = Image.network(
      url,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => placeholder,
      loadingBuilder: (context, child, progress) => progress == null ? child : placeholder,
    );

    if (size == null) return image;
    return ClipRRect(borderRadius: radius, child: image);
  }
}

// ---------------------------------------------------------------------------
// Show tiles
// ---------------------------------------------------------------------------

class PodcastShowTile extends StatelessWidget {
  final PodcastShow show;
  final VoidCallback? onTap;

  const PodcastShowTile({super.key, required this.show, this.onTap});

  @override
  Widget build(BuildContext context) {
    final textTheme = context.theme.textTheme;

    return InkWell(
      borderRadius: BorderRadius.circular(16.0.multipliedRadius),
      onTap: onTap ?? () => PodcastShowPage(show: show).navigate(),
      child: Padding(
        padding: const EdgeInsets.all(6.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          // -- 封面吃掉剩余高度, 文本固定在底部, 这样换任何屏幕宽度都不会溢出。
          children: [
            Expanded(
              child: PodcastArtwork(url: show.artworkUrl, size: null, borderRadius: 16.0),
            ),
            const SizedBox(height: 8.0),
            Text(
              show.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (show.author.isNotEmpty)
              Text(
                show.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.displaySmall,
              ),
          ],
        ),
      ),
    );
  }
}

/// 横向的节目行（订阅页用）。
class PodcastShowRow extends StatelessWidget {
  final PodcastShow show;
  final int? newEpisodes;

  const PodcastShowRow({super.key, required this.show, this.newEpisodes});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final textTheme = theme.textTheme;

    return InkWell(
      onTap: () => PodcastShowPage(show: show).navigate(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
        child: Row(
          children: [
            PodcastArtwork(url: show.artworkUrl, size: 60.0),
            const SizedBox(width: 12.0),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(show.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  if (show.author.isNotEmpty)
                    Text(show.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.displaySmall),
                  const SizedBox(height: 4.0),
                  ObxO(
                    rx: PodcastController.inst.subscriptions,
                    builder: (context, _) {
                      if (!PodcastController.inst.isSubscribed(show.id)) return const SizedBox.shrink();
                      return Row(
                        children: [
                          Icon(Broken.tick_circle, size: 14.0, color: theme.colorScheme.primary),
                          const SizedBox(width: 4.0),
                          Text('Subscribed', style: textTheme.displaySmall?.copyWith(color: theme.colorScheme.primary)),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            if (newEpisodes != null && newEpisodes! > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
                decoration: BoxDecoration(color: theme.colorScheme.primary, borderRadius: BorderRadius.circular(10.0)),
                child: Text(
                  newEpisodes.toString(),
                  style: textTheme.displaySmall?.copyWith(color: theme.colorScheme.onPrimary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Episode tile
// ---------------------------------------------------------------------------

class PodcastEpisodeTile extends StatelessWidget {
  final PodcastEpisode episode;
  final List<PodcastEpisode> allEpisodes;
  final int indexInQueue;
  final VoidCallback? onPlay;
  final VoidCallback? onShowTap;
  final QueueSourceBase? source;

  const PodcastEpisodeTile({
    super.key,
    required this.episode,
    required this.allEpisodes,
    required this.indexInQueue,
    this.onPlay,
    this.onShowTap,
    this.source,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final textTheme = theme.textTheme;
    final downloads = PodcastDownloadsController.inst;

    final pubDate = episode.pubDateMS > 0 ? episode.pubDateMS.dateFormatted : '';
    final meta = [
      if (pubDate.isNotEmpty) pubDate,
      if (episode.durationMS > 0) episode.durationMS.milliSecondsLabel,
      if (episode.fileSize > 0) episode.fileSize.fileSizeFormatted,
    ].join('  •  ');

    return InkWell(
      onTap: onPlay ?? () => playPodcastEpisodes(allEpisodes, index: indexInQueue, source: source ?? QueueSourcePodcast.show(episode.showTitle)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (onShowTap != null)
              InkWell(
                onTap: onShowTap,
                borderRadius: BorderRadius.circular(6.0),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4.0),
                  child: Text(
                    episode.showTitle.isEmpty ? 'Podcast' : episode.showTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.displaySmall?.copyWith(color: theme.colorScheme.primary),
                  ),
                ),
              ),
            Text(
              episode.title.isEmpty ? 'Untitled' : episode.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6.0),
            Row(
              children: [
                Expanded(
                  child: Text(
                    meta.isEmpty ? ' ' : meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.displaySmall,
                  ),
                ),
                ObxO(
                  rx: PodcastController.inst.favourites,
                  builder: (context, _) {
                    final isFav = PodcastController.inst.isFavourite(episode);
                    return NamidaIconButton(
                      icon: isFav ? Broken.heart_tick : Broken.heart,
                      iconSize: 20.0,
                      horizontalPadding: 6.0,
                      onPressed: () => PodcastController.inst.toggleFavourite(episode),
                    );
                  },
                ),
                ObxO(
                  rx: downloads.tasks,
                  builder: (context, _) {
                    final isDone = downloads.isDownloaded(episode.id) || episode.isDownloaded;
                    final task = downloads.taskFor(episode.id);
                    final isDownloading = downloads.isDownloading(episode.id);

                    if (isDownloading) {
                      return SizedBox(
                        width: 24.0,
                        height: 24.0,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.0,
                          value: task != null && task.totalBytes > 0 ? task.progress : null,
                        ),
                      );
                    }

                    // -- 已下载/未下载必须用不同图标, 否则用户点了看不出有没有生效。
                    return NamidaIconButton(
                      icon: isDone ? Broken.tick_circle : Broken.document_download,
                      iconSize: 20.0,
                      horizontalPadding: 6.0,
                      onPressed: isDone ? () => downloads.remove(episode.id) : () => downloads.download(episode),
                    );
                  },
                ),
              ],
            ),
            ObxO(
              rx: PodcastController.inst.positions,
              builder: (context, positions) {
                final position = positions[episode.id] ?? 0;
                if (position <= 0 || episode.durationMS <= 0) return const SizedBox.shrink();
                final progress = (position / episode.durationMS).clamp(0.0, 1.0);
                return Padding(
                  padding: const EdgeInsets.only(top: 6.0),
                  child: LinearProgressIndicator(value: progress, minHeight: 3.0),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}