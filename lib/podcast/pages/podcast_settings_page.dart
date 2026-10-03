import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nampack/nampack.dart';

import 'package:namida/class/route.dart';
import 'package:namida/controller/navigator_controller.dart';
import 'package:namida/controller/settings_controller.dart';
import 'package:namida/core/constants.dart';
import 'package:namida/core/enums.dart';
import 'package:namida/core/extensions.dart';
import 'package:namida/core/icon_fonts/broken_icons.dart';
import 'package:namida/core/themes.dart';
import 'package:namida/podcast/controller/podcast_downloads_controller.dart';
import 'package:namida/ui/widgets/custom_widgets.dart';

/// 播客设置页（下载目录等）。从 Podcasts 页右上角进入。
class PodcastSettingsPage extends StatelessWidget with NamidaRouteWidget {
  @override
  RouteType get route => RouteType.PODCAST_SETTINGS_SUBPAGE;

  @override
  String? get name => 'Podcast Settings';

  const PodcastSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final textTheme = theme.textTheme;

    return BackgroundWrapper(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 4.0),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text('Podcast Settings', style: textTheme.titleLarge),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 120.0),
              children: [
                _DownloadLocationTile(),
                ObxO(
                  rx: settings.podcast.searchEpisodesToo,
                  builder: (context, value) => SwitchListTile(
                    title: const Text('Search episodes too'),
                    subtitle: const Text('Also search individual episodes, not just shows'),
                    value: value,
                    onChanged: (v) => settings.podcast.searchEpisodesToo.save(v),
                  ),
                ),
                ObxO(
                  rx: settings.podcast.autoRefreshSubscriptionsMinutes,
                  builder: (context, value) => ListTile(
                    title: const Text('Auto-refresh subscriptions'),
                    subtitle: Text(value == 0 ? 'Manual only' : 'Every $value minute(s)'),
                    trailing: const Icon(Broken.refresh),
                    onTap: () => _pickInterval(context, value),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickInterval(BuildContext context, int current) async {
    final options = [0, 15, 30, 60, 180, 360, 1440];
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Auto-refresh subscriptions'),
        children: options
            .map(
              (e) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, e),
                child: Text(e == 0 ? 'Manual only' : 'Every $e minute(s)'),
              ),
            )
            .toList(),
      ),
    );
    if (picked != null) settings.podcast.autoRefreshSubscriptionsMinutes.save(picked);
  }
}

class _DownloadLocationTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ObxO(
      rx: settings.podcast.downloadLocation,
      builder: (context, value) => ListTile(
        title: const Text('Download location'),
        subtitle: Text(value.isEmpty ? AppDirs.PODCAST_DOWNLOADS_DEFAULT : value, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Broken.folder),
        onTap: () => _edit(context, value),
      ),
    );
  }

  Future<void> _edit(BuildContext context, String current) async {
    final controller = TextEditingController(text: current.isEmpty ? AppDirs.PODCAST_DOWNLOADS_DEFAULT : current);

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Download location'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(controller: controller, autofocus: true, decoration: const InputDecoration(hintText: '/storage/emulated/0/Namida/Podcast Downloads')),
            const SizedBox(height: 10.0),
            Wrap(
              spacing: 8.0,
              children: [
                for (final preset in _presets())
                  ActionChip(
                    label: Text(preset.$1, style: context.theme.textTheme.displaySmall),
                    onPressed: () => controller.text = preset.$2,
                  ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('Reset')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );

    if (result == null) return;
    final trimmed = result.trim();
    settings.podcast.downloadLocation.save(trimmed);

    // -- 换了目录后已在旧目录的任务仍在, 提示一下即可(不自动搬文件, 避免误删)。
    if (trimmed.isNotEmpty) {
      snackyy(title: 'Saved', message: 'New downloads will go to the selected folder.');
    }
  }

  /// 常用目录快捷选项, 省得在手机上敲路径。
  List<(String, String)> _presets() {
    final result = <(String, String)>[];
    final internal = AppDirs.INTERNAL_STORAGE;
    if (internal.isNotEmpty) {
      result.add(('Namida', '$internal/Podcast Downloads/'));
    }
    result.add(('Downloads', '/storage/emulated/0/Download/Podcasts/'));
    result.add(('Music', '/storage/emulated/0/Music/Podcasts/'));
    result.add(('SD card', '/storage/sdcard1/Podcasts/'));
    return result;
  }
}
