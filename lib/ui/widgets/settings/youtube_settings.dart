import 'package:flutter/material.dart';

import 'package:namida/base/setting_subpage_provider.dart';
import 'package:namida/controller/settings_search_controller.dart';
import 'package:namida/core/enums.dart';

/// YouTube 功能已移除，设置页保留空壳以维持设置导航契约。
class YoutubeSettings extends SettingSubpageProvider {
  const YoutubeSettings({super.key, super.initialItem});

  @override
  SettingSubpageEnum get settingPage => SettingSubpageEnum.youtube;

  @override
  Map<SettingKeysBase, List<String>> buildLookupMap() => const {};

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();

  /// 保留数据节省配置入口，但在移除功能的构建中不执行操作。
  static void openDataSaverConfigureDialog() {}
}
