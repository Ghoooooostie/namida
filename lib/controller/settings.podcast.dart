part of 'settings_controller.dart';

class _PodcastSettings extends _SettingsKeysWriter {
  _PodcastSettings._internal();

  /// 播客下载目录。默认与 YouTube 下载一样放在 `Namida/Podcast Downloads`。
  late final downloadLocation = _key('downloadLocation', AppDirs.PODCAST_DOWNLOADS_DEFAULT, sync: false);

  /// 搜索时是否一并搜单集（iTunes 单集搜索较慢，默认关闭）。
  late final searchEpisodesToo = _key('searchEpisodesToo', false);

  /// 订阅列表的自动刷新间隔（分钟）。0 = 只在手动刷新时拉取。
  late final autoRefreshSubscriptionsMinutes = _key('autoRefreshSubscriptionsMinutes', 30);

  @override
  bool get syncable => true;

  @override
  String get filePath => AppPaths.SETTINGS_PODCAST;
}
