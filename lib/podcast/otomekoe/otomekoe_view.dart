import 'package:flutter/material.dart';
import 'package:nampack/nampack.dart';

import 'package:namida/controller/navigator_controller.dart';
import 'package:namida/core/enums.dart';
import 'package:namida/core/extensions.dart';
import 'package:namida/core/icon_fonts/broken_icons.dart';
import 'package:namida/podcast/class/podcast.dart';
import 'package:namida/podcast/controller/podcast_downloads_controller.dart';
import 'package:namida/podcast/otomekoe/otomekoe_api.dart';
import 'package:namida/podcast/otomekoe/otomekoe_parse.dart';
import 'package:namida/podcast/widgets/podcast_widgets.dart';
import 'package:namida/ui/widgets/custom_widgets.dart';

/// otomekoe.moe 归档页浏览: 博客式列表, 点条目 → 解析 m3u8 → 播放/下载。
class OtomekoeView extends StatefulWidget {
  const OtomekoeView({super.key});

  @override
  State<OtomekoeView> createState() => _OtomekoeViewState();
}

class _OtomekoeViewState extends State<OtomekoeView> {
  final _posts = <OtomekoePost>[].obs;
  final _isLoading = false.obs;
  final _error = Rx<String?>(null);

  final _resolvedEpisodes = <int, PodcastEpisode>{};
  int _page = 0;
  bool _hasMore = true;

  late final _scrollController = ScrollController()..addListener(_onScroll);

  @override
  void initState() {
    super.initState();
    _loadNextPage();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) _loadNextPage();
  }

  Future<void> _loadNextPage() async {
    if (_isLoading.value || !_hasMore) return;
    _isLoading.value = true;
    _error.value = null;
    final page = _page + 1;
    final posts = await OtomekoeApi.inst.fetchListing(page: page);
    if (!mounted) return;
    if (posts.isEmpty) {
      _hasMore = false;
    } else {
      _page = page;
      _posts.addAll(posts);
    }
    _isLoading.value = false;
  }

  Future<void> _openPost(OtomekoePost post) async {
    var episode = _resolvedEpisodes[post.id];
    if (episode == null) {
      snackyy(message: 'Resolving stream...', top: false);
      episode = await OtomekoeApi.inst.resolveEpisode(post);
      if (episode == null) {
        snackyy(title: 'Error', message: 'No audio stream found on this page', isError: true, top: false);
        return;
      }
      _resolvedEpisodes[post.id] = episode;
    }
    if (!mounted) return;
    await _showEpisodeDialog(episode);
  }

  Future<void> _showEpisodeDialog(PodcastEpisode episode) {
    final downloads = PodcastDownloadsController.inst;
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(episode.title, style: const TextStyle(fontSize: 16.0)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (episode.artworkUrl.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10.0),
                child: PodcastArtwork(url: episode.artworkUrl, size: 150.0),
              ),
            Text(
              [
                'OtomeKoe 乙女声',
                if (episode.pubDateMS > 0) episode.pubDateMS.dateFormatted,
                if (episode.durationMS > 0) episode.durationMS.milliSecondsLabel,
              ].join('  •  '),
              style: context.theme.textTheme.displaySmall,
            ),
          ],
        ),
        actions: [
          ObxO(
            rx: downloads.tasks,
            builder: (context, tasks) {
              final isDownloading = downloads.isDownloading(episode.id);
              final isDone = downloads.isDownloaded(episode.id);
              if (isDownloading) {
                return TextButton(
                  onPressed: () => downloads.cancel(episode.id),
                  child: const Text('Cancel'),
                );
              }
              return TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  if (isDone) {
                    downloads.remove(episode.id);
                  } else {
                    downloads.download(episode);
                  }
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(isDone ? Broken.tick_circle : Broken.document_download, size: 18.0),
                    const SizedBox(width: 6.0),
                    Text(isDone ? 'Delete' : 'Download'),
                  ],
                ),
              );
            },
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              playPodcastEpisode(episode, source: QueueSourcePodcast.show('OtomeKoe'));
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Broken.play, size: 18.0),
                const SizedBox(width: 6.0),
                const Text('Play'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = context.theme.textTheme;

    return RefreshIndicator(
      onRefresh: () async {
        _posts.clear();
        _resolvedEpisodes.clear();
        _page = 0;
        _hasMore = true;
        await _loadNextPage();
      },
      child: ObxO(
        rx: _posts,
        builder: (context, posts) {
          if (posts.isEmpty) {
            if (_isLoading.value) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(
              children: [
                const SizedBox(height: 80.0),
                Center(
                  child: Text(_error.value ?? 'Could not load the archive', style: textTheme.bodySmall),
                ),
                Center(
                  child: NamidaButton(icon: Broken.refresh, text: 'Retry', onTap: _loadNextPage),
                ),
              ],
            );
          }

          return ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.only(bottom: 120.0),
            itemCount: posts.length + 1,
            itemBuilder: (context, i) {
              if (i >= posts.length) {
                return _isLoading.value
                    ? const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : const SizedBox.shrink();
              }
              final post = posts[i];
              return InkWell(
                onTap: () => _openPost(post),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PodcastArtwork(url: post.artworkUrl, size: 64.0, borderRadius: 8.0),
                      const SizedBox(width: 12.0),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              post.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4.0),
                            Text(
                              [
                                if (post.date.isNotEmpty) post.date,
                                ...post.categories.take(3),
                              ].join('  •  '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.displaySmall,
                            ),
                          ],
                        ),
                      ),
                      ObxO(
                        rx: PodcastDownloadsController.inst.tasks,
                        builder: (context, tasks) {
                          final id = 'otomekoe:${post.id}';
                          if (tasks[id]?.state == PodcastDownloadState.downloading) {
                            return const SizedBox(
                              width: 18.0,
                              height: 18.0,
                              child: CircularProgressIndicator(strokeWidth: 2.0),
                            );
                          }
                          final icon = switch (tasks[id]?.state) {
                            PodcastDownloadState.done => Broken.tick_circle,
                            _ => Broken.play,
                          };
                          return Icon(icon, size: 18.0, color: textTheme.displaySmall?.color);
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
