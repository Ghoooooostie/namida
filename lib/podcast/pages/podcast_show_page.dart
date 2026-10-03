import 'package:flutter/material.dart';
import 'package:nampack/nampack.dart';

import 'package:namida/controller/navigator_controller.dart';
import 'package:namida/class/route.dart';
import 'package:namida/core/enums.dart';
import 'package:namida/core/extensions.dart';
import 'package:namida/core/icon_fonts/broken_icons.dart';
import 'package:namida/core/themes.dart';
import 'package:namida/podcast/class/podcast.dart';
import 'package:namida/podcast/controller/podcast_api.dart';
import 'package:namida/podcast/controller/podcast_controller.dart';
import 'package:namida/podcast/widgets/podcast_widgets.dart';
import 'package:namida/ui/widgets/custom_widgets.dart';

enum _EpisodeSort {
  newestFirst,
  oldestFirst;

  String get text => switch (this) {
    _EpisodeSort.newestFirst => 'Newest first',
    _EpisodeSort.oldestFirst => 'Oldest first',
  };
}

class PodcastShowPage extends StatefulWidget with NamidaRouteWidget {
  @override
  RouteType get route => RouteType.PODCAST_SHOW_SUBPAGE;

  @override
  String? get name => show.title;

  final PodcastShow show;

  const PodcastShowPage({super.key, required this.show});

  @override
  State<PodcastShowPage> createState() => _PodcastShowPageState();
}

class _PodcastShowPageState extends State<PodcastShowPage> {
  _EpisodeSort _sort = _EpisodeSort.newestFirst;

  @override
  void initState() {
    super.initState();
    // -- 必须**同步**触发: getEpisodes 在第一个 await 之前就会把 fetchingEpisodes 置位。
    // -- 若放到 postFrameCallback, 首次 build 时缓存和 fetching 都还是空,
    // -- 会先闪一下 "No episodes found" 再切回加载中(用户反馈的"经常出现 no episode")。
    PodcastController.inst.getEpisodes(widget.show).ignoreError();
  }

  Future<void> _onSubscribePressed() async {
    final wasSubscribed = PodcastController.inst.isSubscribed(widget.show.id);
    await PodcastController.inst.toggleSubscribe(widget.show);
    if (!mounted) return;
    snackyy(
      message: wasSubscribed ? 'Unsubscribed from ${widget.show.title}' : 'Subscribed to ${widget.show.title}',
    );
  }

  Future<void> _onAddByFeedUrl() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add podcast by RSS'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'https://example.com/feed.xml'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Add')),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;

    snackyy(title: 'Fetching feed...', message: 'Reading RSS feed...');
    final show = await PodcastApi.inst.resolveShowFromFeed(url);
    if (show == null) {
      snackyy(message: 'Could not read that RSS feed', isError: true);
      return;
    }
    await PodcastController.inst.subscribe(show);
    if (mounted) PodcastShowPage(show: show).navigate();
  }

  List<PodcastEpisode> _sortedEpisodes(List<PodcastEpisode> episodes) {
    final copy = List<PodcastEpisode>.from(episodes);
    copy.sort((a, b) => _sort == _EpisodeSort.newestFirst ? b.pubDateMS.compareTo(a.pubDateMS) : a.pubDateMS.compareTo(b.pubDateMS));
    return copy;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final textTheme = theme.textTheme;
    final show = widget.show;

    final header = Container(
      padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PodcastArtwork(url: show.artworkUrl, size: 110.0, borderRadius: 16.0),
              const SizedBox(width: 14.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(show.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: textTheme.titleMedium),
                    if (show.author.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(show.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.bodySmall),
                      ),
                    if (show.genres.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6.0),
                        child: Text(show.genres.take(3).join(' • '), maxLines: 2, style: textTheme.displaySmall),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12.0),
          ObxO(
            rx: PodcastController.inst.subscriptions,
            builder: (context, _) {
              final isSubscribed = PodcastController.inst.isSubscribed(show.id);
              return Row(
                children: [
                  Expanded(
                    child: NamidaButton(
                      icon: isSubscribed ? Broken.tick_circle : Broken.add_circle,
                      text: isSubscribed ? 'Subscribed' : 'Subscribe',
                      onTap: _onSubscribePressed,
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  NamidaIconButton(
                    icon: Broken.radio,
                    iconSize: 22.0,
                    onPressed: _onAddByFeedUrl,
                  ),
                ],
              );
            },
          ),
          if (show.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: Text(show.description, maxLines: 6, overflow: TextOverflow.ellipsis, style: textTheme.bodySmall),
            ),
        ],
      ),
    );

    return BackgroundWrapper(
      child: SmoothCustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: header),
          ObxO(
            rx: PodcastController.inst.episodesCache,
            builder: (context, cache) {
              final episodes = _sortedEpisodes(cache[show.id] ?? const []);
              final isFetching = PodcastController.inst.fetchingEpisodes.value.contains(show.id);

              if (episodes.isEmpty) {
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: isFetching
                        ? const CircularProgressIndicator()
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Broken.headphones, size: 48.0, color: textTheme.displaySmall?.color),
                              const SizedBox(height: 12.0),
                              Text('No episodes found', style: textTheme.bodySmall),
                              const SizedBox(height: 12.0),
                              NamidaButton(
                                icon: Broken.refresh,
                                text: 'Retry',
                                onTap: () => PodcastController.inst.getEpisodes(show, forceRefresh: true),
                              ),
                            ],
                          ),
                  ),
                );
              }

              return SliverMainAxisGroup(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${episodes.length} episodes  •  ${_sort.text}',
                              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          NamidaIconButton(
                            icon: Broken.play_circle,
                            iconSize: 24.0,
                            onPressed: () => playPodcastEpisodes(episodes, source: QueueSourcePodcast.show(show.title)),
                          ),
                          NamidaIconButton(
                            icon: Broken.play_add,
                            iconSize: 24.0,
                            onPressed: () => addPodcastEpisodesToQueue(episodes),
                          ),
                          NamidaIconButton(
                            icon: Broken.sort,
                            iconSize: 24.0,
                            onPressed: () {
                              setState(() {
                                _sort = _sort == _EpisodeSort.newestFirst ? _EpisodeSort.oldestFirst : _EpisodeSort.newestFirst;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverList.builder(
                    itemCount: episodes.length,
                    itemBuilder: (context, i) {
                      final episode = episodes[i];
                      return ObxO(
                        rx: PodcastController.inst.favourites,
                        builder: (context, _) => ObxO(
                          rx: PodcastController.inst.positions,
                          builder: (context, _) => PodcastEpisodeTile(
                            key: ValueKey(episode.id),
                            episode: episode,
                            allEpisodes: episodes,
                            indexInQueue: i,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
          SliverToBoxAdapter(child: SizedBox(height: context.height * 0.2)),
        ],
      ),
    );
  }
}