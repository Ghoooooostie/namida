import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nampack/nampack.dart';

import 'package:namida/controller/navigator_controller.dart';
import 'package:namida/controller/settings_controller.dart';
import 'package:namida/core/enums.dart';
import 'package:namida/class/route.dart';
import 'package:namida/core/extensions.dart';
import 'package:namida/core/icon_fonts/broken_icons.dart';
import 'package:namida/core/themes.dart';
import 'package:namida/podcast/controller/podcast_api.dart';
import 'package:namida/podcast/controller/podcast_controller.dart';
import 'package:namida/podcast/controller/podcast_downloads_controller.dart';
import 'package:namida/podcast/pages/podcast_downloads_page.dart';
import 'package:namida/podcast/pages/podcast_downloads_page.dart';
import 'package:namida/podcast/pages/podcast_subscriptions_page.dart';
import 'package:namida/podcast/otomekoe/otomekoe_view.dart';
import 'package:namida/podcast/widgets/podcast_widgets.dart';
import 'package:namida/ui/widgets/custom_widgets.dart';

class PodcastHomeView extends StatefulWidget with NamidaRouteWidget {
  @override
  RouteType get route => RouteType.PODCAST_HOME;

  const PodcastHomeView({super.key});

  @override
  State<PodcastHomeView> createState() => _PodcastHomeViewState();
}

class _PodcastHomeViewState extends State<PodcastHomeView> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // -- 同步触发, 让 isTopLoading 在首次 build 前就为 true,
    // -- 否则会先闪一下 "Could not load charts" 再切成加载中。
    if (PodcastController.inst.topShows.isEmpty) {
      PodcastController.inst.fetchTopShows(PodcastGenre.all.first.id);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      PodcastController.inst.clearSearch();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () {
      PodcastController.inst.search(
        value,
        includeEpisodes: settings.podcast.searchEpisodesToo.value,
      );
    });
  }

  void _refreshTop() {
    final current = PodcastController.inst.lastTopGenreId ?? PodcastGenre.all.first.id;
    PodcastController.inst.fetchTopShows(current, force: true);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = context.theme.textTheme;

    final searchField = Padding(
      padding: const EdgeInsets.fromLTRB(14.0, 10.0, 14.0, 6.0),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search podcasts & episodes',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14.0)),
          isDense: true,
        ),
      ),
    );

    final regionPicker = SizedBox(
      height: 38.0,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14.0),
        itemCount: PodcastRegion.all.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8.0),
        itemBuilder: (context, i) {
          final region = PodcastRegion.all[i];
          return ObxO(
            rx: PodcastController.inst.currentRegion,
            builder: (context, current) => ChoiceChip(
              label: Text(region.name),
              selected: current.country == region.country,
              onSelected: (_) => PodcastController.inst.setRegion(region),
            ),
          );
        },
      ),
    );

    return DefaultTabController(
      length: 4,
      child: BackgroundWrapper(
        child: Column(
          children: [
            searchField,
            regionPicker,
            _buildTabBar(context),
            Expanded(
              child: TabBarView(
                children: [
                  // -- 发现
                  ObxO(
                    rx: PodcastController.inst.searchResults,
                    builder: (context, _) {
                      if (PodcastController.inst.lastSearchTerm.value.isNotEmpty) return _buildSearchResults();
                      return _buildDiscovery();
                    },
                  ),
                  // -- 订阅
                  const PodcastSubscriptionsView(),
                  // -- 下载
                  const PodcastDownloadsView(),
                  // -- OtomeKoe 站抓取
                  const OtomekoeView(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 三个明确标签（发现 / 订阅 / 下载），带数量角标。
  /// 之前只在标题栏放两个 22px 无标签图标，用户根本找不到订阅列表。
  Widget _buildTabBar(BuildContext context) {
    final textTheme = context.theme.textTheme;
    final primary = context.theme.colorScheme.primary;

    // -- 用 Text.rich 而不是 Row+Container: isScrollable 的 Tab 里 FittedBox 拿到的约束是
    // -- 无界的, 不会真的缩放; 而 Text 永远只会省略号, 绝不会触发 RenderFlex overflow。
    Widget tab(String label, int count) {
      return Tab(
        height: 42.0,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0),
          child: Center(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: label, style: textTheme.bodyMedium),
                  if (count > 0)
                    TextSpan(
                      text: ' ${count > 99 ? '99+' : count}',
                      style: textTheme.displaySmall?.copyWith(color: primary, fontSize: 12.0),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return TabBar(
      // -- 固定宽度铺满时三个标签在窄屏必溢出("Subscriptions" 尤其长), 改成可滚动即彻底规避。
      // -- isScrollable 时默认就是左对齐, 不需要 tabAlignment(旧版 Flutter 无该参数)。
      isScrollable: true,
      padding: EdgeInsets.zero,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: Colors.transparent,
      tabs: [
        tab('Discover', 0),
        ObxO(rx: PodcastController.inst.subscriptions, builder: (context, subs) => tab('Subs', subs.length)),
        ObxO(rx: PodcastDownloadsController.inst.tasks, builder: (context, tasks) => tab('Downloads', tasks.length)),
        tab('OtomeKoe', 0),
      ],
    );
  }

  Widget _buildSearchResults() {
    final textTheme = context.theme.textTheme;

    return ObxO(
      rx: PodcastController.inst.isSearching,
      builder: (context, isSearching) {
        final shows = PodcastController.inst.searchResults.value;
        final episodes = PodcastController.inst.searchEpisodesResults.value;
        final error = PodcastController.inst.searchError.value;

        if (isSearching && shows.isEmpty && episodes.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (shows.isEmpty && episodes.isEmpty) {
          final msg = error != null ? 'Search failed: $error' : 'Nothing found';
          return Center(child: Text(msg, style: textTheme.bodySmall));
        }

        return SmoothCustomScrollView(
          slivers: [
            if (shows.isNotEmpty) ...[
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(14.0, 12.0, 14.0, 4.0),
                  child: Text('Podcasts', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220.0,
                    mainAxisExtent: 200.0,
                    crossAxisSpacing: 4.0,
                    mainAxisSpacing: 4.0,
                  ),
                  itemCount: shows.length,
                  itemBuilder: (context, i) => PodcastShowTile(show: shows[i]),
                ),
              ),
            ],
            if (episodes.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14.0, 16.0, 14.0, 4.0),
                  child: Text('Episodes', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                ),
              ),
              SliverList.builder(
                itemCount: episodes.length,
                itemBuilder: (context, i) => PodcastEpisodeTile(
                  key: ValueKey(episodes[i].id),
                  episode: episodes[i],
                  allEpisodes: episodes,
                  indexInQueue: i,
                  source: QueueSourcePodcast.search,
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 120.0)),
          ],
        );
      },
    );
  }

  Widget _buildDiscovery() {
    final textTheme = context.theme.textTheme;

    final genres = SizedBox(
      height: 34.0,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14.0),
        itemCount: PodcastGenre.all.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8.0),
        itemBuilder: (context, i) {
          final genre = PodcastGenre.all[i];
          return ActionChip(
            label: Text(genre.name, style: textTheme.displaySmall),
            onPressed: () => PodcastController.inst.fetchTopShows(genre.id, force: true),
          );
        },
      ),
    );

    return SmoothCustomScrollView(
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 8.0)),
        SliverToBoxAdapter(child: genres),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14.0, 14.0, 6.0, 6.0),
            child: Row(
              children: [
                Expanded(child: Text('Top Podcasts', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
                NamidaIconButton(icon: Broken.refresh, iconSize: 20.0, onPressed: _refreshTop),
              ],
            ),
          ),
        ),
        ObxO(
          rx: PodcastController.inst.topShows,
          builder: (context, shows) {
            if (shows.isEmpty) {
              // -- 只有还在请求时才转圈, 否则给可读的错误 + 重试, 避免"一直转圈看不到原因"。
              if (PodcastController.inst.isTopLoading.value) {
                return const SliverToBoxAdapter(
                  child: Padding(padding: EdgeInsets.all(40.0), child: Center(child: CircularProgressIndicator())),
                );
              }
              return SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      Icon(Broken.headphones, size: 40.0, color: textTheme.displaySmall?.color),
                      const SizedBox(height: 12.0),
                      Text(
                        PodcastController.inst.topError.value ?? 'Could not load charts',
                        textAlign: TextAlign.center,
                        style: textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12.0),
                      NamidaButton(icon: Broken.refresh, text: 'Retry', onTap: _refreshTop),
                    ],
                  ),
                ),
              );
            }
            return SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220.0,
                  mainAxisExtent: 200.0,
                  crossAxisSpacing: 4.0,
                  mainAxisSpacing: 4.0,
                ),
                itemCount: shows.length,
                itemBuilder: (context, i) => PodcastShowTile(show: shows[i]),
              ),
            );
          },
        ),
        SliverToBoxAdapter(child: SizedBox(height: context.height * 0.2)),
      ],
    );
  }
}