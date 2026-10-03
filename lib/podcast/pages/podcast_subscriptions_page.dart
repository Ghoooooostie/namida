import 'package:flutter/material.dart';
import 'package:nampack/nampack.dart';

import 'package:namida/controller/navigator_controller.dart';
import 'package:namida/class/route.dart';
import 'package:namida/core/enums.dart';
import 'package:namida/core/extensions.dart';
import 'package:namida/core/icon_fonts/broken_icons.dart';
import 'package:namida/core/themes.dart';
import 'package:namida/podcast/controller/podcast_controller.dart';
import 'package:namida/podcast/widgets/podcast_widgets.dart';
import 'package:namida/ui/widgets/custom_widgets.dart';

/// 订阅列表的内容部分。可直接嵌进 Tab，也可用 [PodcastSubscriptionsPage] 单独开页面。
class PodcastSubscriptionsView extends StatelessWidget {
  const PodcastSubscriptionsView({super.key});

  Future<void> _refresh() => PodcastController.inst.refreshSubscriptions(force: true);

  @override
  Widget build(BuildContext context) {
    final textTheme = context.theme.textTheme;

    return BackgroundWrapper(
      child: ObxO(
        rx: PodcastController.inst.subscriptions,
        builder: (context, subs) {
          final shows = subs.values.toList()..sort((a, b) => a.title.compareTo(b.title));

          if (shows.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Broken.radio, size: 48.0, color: textTheme.displaySmall?.color),
                  const SizedBox(height: 12.0),
                  Text('No subscriptions yet', style: textTheme.bodySmall),
                ],
              ),
            );
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 12.0, 6.0, 4.0),
                child: Row(
                  children: [
                    Expanded(child: Text('Subscriptions', style: textTheme.titleLarge)),
                    NamidaIconButton(icon: Broken.refresh, iconSize: 20.0, onPressed: _refresh),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.only(bottom: 120.0),
                  itemCount: shows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1.0, indent: 86.0),
                  itemBuilder: (context, i) {
                    final show = shows[i];
                    return ObxO(
                      rx: PodcastController.inst.episodesCache,
                      builder: (context, _) => Dismissible(
                        key: ValueKey(show.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 22.0),
                          color: context.theme.colorScheme.errorContainer,
                          child: Icon(Broken.trash, color: context.theme.colorScheme.onErrorContainer),
                        ),
                        onDismissed: (_) {
                          PodcastController.inst.unsubscribe(show.id);
                          snackyy(message: 'Unsubscribed');
                        },
                        child: PodcastShowRow(
                          show: show,
                          newEpisodes: PodcastController.inst.newEpisodesCountFor(show.id),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class PodcastSubscriptionsPage extends StatelessWidget with NamidaRouteWidget {
  @override
  RouteType get route => RouteType.PODCAST_SUBSCRIPTIONS_SUBPAGE;

  @override
  String? get name => 'Subscriptions';

  const PodcastSubscriptionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PodcastSubscriptionsView();
  }
}

class PodcastFavouritesPage extends StatelessWidget with NamidaRouteWidget {
  @override
  RouteType get route => RouteType.PODCAST_FAVOURITES_SUBPAGE;

  @override
  String? get name => 'Podcast Favourites';

  const PodcastFavouritesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = context.theme.textTheme;

    return BackgroundWrapper(
      child: ObxO(
        rx: PodcastController.inst.favourites,
        builder: (context, episodes) {
          if (episodes.isEmpty) {
            return Center(child: Text('No saved episodes', style: textTheme.bodySmall));
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 12.0, 6.0, 4.0),
                child: Row(
                  children: [
                    Expanded(child: Text('Favourites', style: textTheme.titleLarge)),
                    NamidaIconButton(
                      icon: Broken.play_circle,
                      iconSize: 22.0,
                      onPressed: () => playPodcastEpisodes(episodes, source: QueueSourcePodcast.favourites),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.only(bottom: 120.0),
                  itemCount: episodes.length,
                  separatorBuilder: (_, __) => const Divider(height: 1.0, indent: 20.0),
                  itemBuilder: (context, i) => PodcastEpisodeTile(
                    key: ValueKey(episodes[i].id),
                    episode: episodes[i],
                    allEpisodes: episodes,
                    indexInQueue: i,
                    source: QueueSourcePodcast.favourites,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}