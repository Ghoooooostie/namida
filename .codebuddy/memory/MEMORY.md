# MEMORY — namida 项目长期记忆

## 环境与构建（跨会话稳定事实）
- Flutter 不在 PATH：`D:\Program_Files\Flutter\flutter\bin`。运行前 `$env:PATH += ";D:\Program_Files\Flutter\flutter\bin"`。
- **`flutter build apk` 在本机会失败**（报错信息被截断成 `25.0.3`）：Flutter 优先用 Android Studio 自带的 JDK 25，
  而 Gradle/AGP 只支持 17。正确做法：
  ```powershell
  cd android; $env:JAVA_HOME = "D:\Program Files\Java\jdk-17.0.18"; .\gradlew.bat assembleDebug
  ```
  产物：`build/app/outputs/flutter-apk/app-debug.apk`，包名 `com.msob7y.namida.debug`。
- 分析：`flutter analyze > analyze_log.txt 2>&1`（项目仍有约 2000 条 issues，属精简构建的既有状态）。
- 设备：魅族 `381QYGEM226CZ`（Android 10, 1080x2400）。抓应用日志：
  `adb pull /storage/emulated/0/Android/data/com.msob7y.namida.debug/files/Logs/logs_<version>_<code>.txt`

## 精简构建的 stub 约定（重要）
- YouTube/youtipie/namico 已被 stub（`lib/youtube/_stubs_base.dart`、`external/shims/*/lib/_stubs_base.dart`），
  成员默认 `=> null`；`lib/youtube/_stubs_base.debug.dart` **没有任何引用，是死文件**。
- `gen_stub_ext.ps1` 会 **先删掉所有 `// === AUTO ... ===` 块再重新注入**。因此：
  - 手写的真实实现**不能放在 AUTO 块内**（会被抹掉）。
  - 要保留，必须放在 AUTO 块外，且用脚本能识别的**完全一致**的写法：
    `static dynamic get x => ...;` / `dynamic get x => ...;` —— 脚本的 `$present` 扫描靠这个正则跳过已声明成员。
    写成 `final x = ...` 或 `Rx<int> get x` 会被判为"未声明"而重复注入，导致 duplicate member 编译错误。
- stub 成员的三类踩坑（都会导致运行时红屏）：
  1. **链式解引用**：`Stub.a.b.c` → 第一跳返回 null 就 NPE（需 `?.` 或给真实占位对象）。
  2. **参与运算**：`null / 2`、`null + x` → `NoSuchMethodError: The method '/'/'+' was called on null`。
  3. **当作 Rx 用**：`ObxO(rx: Stub.x)` → `type 'Null' is not a subtype of type 'RxBaseCore<dynamic>'`。
     这类必须给真实 Rx 占位值（如 `_stubRawDownloadsCountRx`）。
- 相反，`await [ ... ].whereType<Future<void>>()` 里的 stub 调用返回 null **是安全的**（会被过滤掉）。

## 启动流程约定
- `Player._audioHandler` 是 `late` 字段，整棵组件树一构建就读它 → 任何启动失败都会红屏。
  - `Player.inst.initializePlayer()` **必须**放在独立 try/catch 里，不能被前面无关失败跳过。
  - `Player.isInitialized`（在给 `_audioHandler` 赋值处置 true）用于给依赖 Player 的后续初始化做守卫。
- 启动相关文件：`lib/main.dart`（`_mainAppInitialization` / `_secondaryAppInitialization`）、
  `lib/base/audio_handler.dart`（`NamidaAudioVideoHandler` 构造函数）、`lib/controller/player_controller.dart`。

## 排查方法（有效）
- 设备日志 + `adb exec-out screencap -p > x.png` 组合，一轮就能定位到下一个红屏点。
- `search_content`(ripgrep) 会跳过被 .gitignore 的 stub 文件，查 stub 内容要用
  PowerShell `Select-String -Path lib\youtube\_stubs_base.dart`。
- 用户习惯：改动后希望直接构建 + 装机 + 抓日志验证，不要只给建议。
