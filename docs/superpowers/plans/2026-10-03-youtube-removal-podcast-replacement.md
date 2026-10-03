# YouTube 移除与播客替换 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 移除 YouTube 在线功能和入口，用现有播客入口替代，同时保留本地视频播放、播客数据和旧 YouTube 文件。

**Architecture:** 先在枚举、设置和启动流程中切断 YouTube 的产品入口，再把队列、播放、备份同步和缓存处理改成只接受本地媒体与播客。最后删除 YouTube 页面、桩代码和专用依赖，并用旧数据跳过策略保证启动不崩溃。播客继续使用独立的 JSON/数据库文件，不读取旧 YouTube 文件。

**Tech Stack:** Flutter/Dart、GetX 风格响应式状态、Android Gradle、现有 Dart tests。

---

### Task 1: 建立 YouTube 到播客的设置迁移

**Files:**
- Modify: `lib/controller/settings_controller.dart`
- Modify: `lib/core/enums.dart`
- Modify: `lib/controller/settings_search_controller.dart`
- Test: `test/youtube_removal_migration_test.dart`

- [ ] **Step 1: 写迁移测试**

覆盖旧 `libraryTabs` 中含 `youtube`、同时含 `podcasts`、只含 `youtube` 三种情况，期望输出只保留一次 `podcasts`，其他标签顺序不变。

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/youtube_removal_migration_test.dart`

Expected: FAIL，因为当前枚举仍包含 YouTube 且没有迁移函数。

- [ ] **Step 3: 实现迁移**

在设置加载后的统一入口增加纯函数，将旧列表中的 `LibraryTab.youtube` 替换为 `LibraryTab.podcasts` 并去重；保留旧设置文件本身，不删除任何文件。删除用户界面可见的 YouTube 设置枚举和搜索索引。

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/youtube_removal_migration_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add lib/controller/settings_controller.dart lib/core/enums.dart lib/controller/settings_search_controller.dart test/youtube_removal_migration_test.dart
git commit -m "refactor: migrate youtube library tab to podcasts"
```

### Task 2: 切断启动、退出、备份和同步入口

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/controller/backup_controller.dart`
- Modify: `lib/controller/storage_cache_manager.dart`
- Modify: `lib/controller/sync_manager/sync_manager.dart`
- Modify: `lib/controller/sync_manager/sync_sender.dart`
- Modify: `lib/controller/sync_manager/sync_messages/sync_messages.dart`
- Modify: `lib/core/constants.dart`
- Modify: `lib/controller/settings_controller.dart`

- [ ] **Step 1: 删除启动与退出调用**

移除 YouTube 初始化、历史/播放列表/订阅/下载任务加载、YouTube 退出释放和 YouTube 账户初始化；保留播客初始化与下载准备。

- [ ] **Step 2: 删除备份与同步项目**

从备份分类、自动备份、发送器和消息分发中移除 YouTube 设置、历史、播放列表、订阅、缩略图、统计和下载任务项目。未知旧同步消息返回跳过结果，不抛异常。

- [ ] **Step 3: 保留旧文件但停止扫描**

保留旧 YouTube 路径常量以便不误删用户文件；移除这些路径在新备份列表、缓存清理和同步列表中的使用。

- [ ] **Step 4: 运行静态分析**

Run: `flutter analyze lib/main.dart lib/controller/backup_controller.dart lib/controller/storage_cache_manager.dart lib/controller/sync_manager lib/core/constants.dart`

Expected: 无新增 YouTube 初始化或备份相关错误。

- [ ] **Step 5: 提交**

```bash
git add lib/main.dart lib/controller/backup_controller.dart lib/controller/storage_cache_manager.dart lib/controller/sync_manager lib/core/constants.dart lib/controller/settings_controller.dart
git commit -m "refactor: stop youtube startup backup and sync"
```

### Task 3: 用播客替换界面入口并删除 YouTube 设置页

**Files:**
- Modify: `lib/ui/pages/main_page.dart`
- Modify: `lib/ui/pages/settings_page.dart`
- Modify: `lib/ui/pages/home_page.dart`
- Modify: `lib/ui/widgets/settings/extra_settings.dart`
- Modify: `lib/ui/widgets/settings/advanced_settings.dart`
- Modify: `lib/ui/widgets/settings/backup_restore_settings.dart`
- Modify: `lib/ui/widgets/server_cache_widgets.dart`
- Delete: `lib/ui/widgets/settings/youtube_settings.dart`
- Delete: `lib/ui/widgets/settings/sponsorblock_settings.dart`
- Delete: `lib/ui/widgets/settings/return_youtube_dislike_settings.dart`
- Test: `test/youtube_removal_ui_test.dart`

- [ ] **Step 1: 写入口测试**

验证默认库标签不包含 YouTube、包含 Podcasts；设置搜索索引不包含 YouTube；播客页面仍可构建。

- [ ] **Step 2: 删除 UI 入口**

删除 YouTube tab、YouTube 搜索类型、YouTube 首页和 YouTube 设置卡片；将旧 tab 迁移后的 Podcasts 作为同位置入口。

- [ ] **Step 3: 删除备份界面分类**

移除 YouTube 备份选项、图标和说明，保留播客备份项。

- [ ] **Step 4: 运行测试**

Run: `flutter test test/youtube_removal_ui_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add lib/ui test/youtube_removal_ui_test.dart
git commit -m "refactor: replace youtube ui with podcasts"
```

### Task 4: 移除 YouTube 类型分支并保留本地视频与播客播放

**Files:**
- Modify: `lib/class/track.dart`
- Modify: `lib/class/video.dart`
- Modify: `lib/class/queue.dart`
- Modify: `lib/core/enums.dart`
- Modify: `lib/controller/queue_controller.dart`
- Modify: `lib/controller/player_controller.dart`
- Modify: `lib/base/audio_handler.dart`
- Modify: `lib/controller/video_controller.dart`
- Modify: `lib/controller/subtitles_controller.dart`
- Modify: `lib/controller/stats_controller.dart`
- Modify: `lib/ui/pages/current_queue_page.dart`
- Modify: `lib/ui/pages/wide_screen_player_page.dart`
- Modify: `lib/ui/widgets/player_transport_controls.dart`
- Modify: `lib/packages/miniplayer.dart`
- Modify: `lib/packages/miniplayer_base.dart`
- Modify: `lib/packages/lyrics_lrc_parsed_view.dart`
- Test: `test/youtube_removal_queue_test.dart`

- [ ] **Step 1: 写旧队列兼容测试**

给定旧 JSON 中的 YouTube playable 条目，恢复函数返回空/跳过；给定 PodcastEpisode 和本地 Track，仍能恢复并播放。

- [ ] **Step 2: 删除 YouTube playable 类型分支**

移除 `YoutubeID`、`QueueSourceYoutubeID`、YouTube 播放历史和 YouTube 专用菜单分支；保留 `PodcastEpisode` 与本地媒体分支。

- [ ] **Step 3: 收窄视频控制器**

保留已缓存/本地文件的视频播放和视频控制 UI；删除从 YouTube 获取流、质量、缩略图和下载任务的路径。

- [ ] **Step 4: 清理字幕、歌词、统计和通知分支**

只保留本地字幕、音频和播客处理；播客进度/历史调用 `PodcastController` 现有接口。

- [ ] **Step 5: 运行针对性测试和分析**

Run: `flutter test test/youtube_removal_queue_test.dart`
Run: `flutter analyze lib/base/audio_handler.dart lib/controller/player_controller.dart lib/controller/queue_controller.dart lib/controller/video_controller.dart`

Expected: 测试通过，分析不再出现 YouTube 类型未定义错误。

- [ ] **Step 6: 提交**

```bash
git add lib/class lib/core/enums.dart lib/controller/queue_controller.dart lib/controller/player_controller.dart lib/base/audio_handler.dart lib/controller/video_controller.dart lib/controller/subtitles_controller.dart lib/controller/stats_controller.dart lib/ui lib/packages test/youtube_removal_queue_test.dart
git commit -m "refactor: remove youtube playable branches"
```

### Task 5: 删除 YouTube 模块、桩和依赖

**Files:**
- Delete: `lib/youtube/`
- Delete: `lib/base/yt_video_like_manager.dart`
- Delete: `lib/controller/settings.youtube.dart`
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Delete or update: `external/shims/youtipie/`
- Delete or update: `external/shims/namico_subscription_manager/`

- [ ] **Step 1: 确认无引用**

Run: `rg -n --hidden -S "package:namida/youtube|YoutubeID|QueueSourceYoutubeID|settings.youtube|package:youtipie|namico_subscription_manager" lib pubspec.yaml`

Expected: 只有待删除文件和明确保留的本地视频兼容字段。

- [ ] **Step 2: 删除文件和依赖**

删除 YouTube Dart 模块、桩层、YouTube 设置文件和不再需要的依赖；不删除用户数据目录中的旧文件。

- [ ] **Step 3: 重新解析依赖**

Run: `flutter pub get`

Expected: 依赖解析成功。

- [ ] **Step 4: 提交**

```bash
git add lib pubspec.yaml pubspec.lock external/shims
git commit -m "refactor: remove youtube module and dependencies"
```

### Task 6: 播客兼容与文档收口

**Files:**
- Modify: `lib/podcast/class/podcast.dart`
- Modify: `lib/podcast/controller/podcast_controller.dart`
- Modify: `docs/CONTEXT.md`
- Modify: `docs/TIMELINE.md`
- Modify: `docs/README.md` if present
- Test: `test/podcast_compatibility_test.dart`

- [ ] **Step 1: 写播客旧值兼容测试**

旧 JSON 的 `sourceType: "youtube"` 读取为 `manual`，播客历史、订阅、收藏和进度文件路径保持不变。

- [ ] **Step 2: 实现兼容读取**

移除 YouTube 来源枚举值；读取未知或旧 YouTube 值时映射为 manual RSS 来源，不迁移 YouTube 文件。

- [ ] **Step 3: 更新项目文档**

记录 YouTube 已移除、播客接替入口、旧 YouTube 文件保留但停用。

- [ ] **Step 4: 运行测试**

Run: `flutter test test/podcast_compatibility_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add lib/podcast docs test/podcast_compatibility_test.dart
git commit -m "refactor: preserve podcast data after youtube removal"
```

### Task 7: 全量验证与 Android 安装

**Files:**
- Modify: only files required by verification failures.

- [ ] **Step 1: 运行完整 Dart 验证**

Run: `flutter analyze`
Run: `flutter test`

Expected: 分析无错误，测试通过。

- [ ] **Step 2: 构建并安装 Android Debug**

Run: `./gradlew.bat :app:installDebug`

Expected: 构建和安装成功；若无设备则使用 `./gradlew.bat :app:assembleDebug`。

- [ ] **Step 3: 检查关键行为**

启动应用，确认库标签显示播客、YouTube 设置和入口消失、播客可以搜索/打开、本地视频可以播放，旧 YouTube 文件未被删除。

- [ ] **Step 4: 更新现场文档**

更新 `docs/CONTEXT.md`、`docs/TIMELINE.md`，记录验证结果和下一步。

- [ ] **Step 5: 提交验证修复**

```bash
git add .
git commit -m "chore: verify youtube removal and podcast replacement"
```

