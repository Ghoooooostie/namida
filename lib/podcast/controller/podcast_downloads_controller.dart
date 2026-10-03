import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nampack/nampack.dart';

import 'package:namida/class/file_parts.dart';
import 'package:namida/controller/ffmpeg_controller.dart';
import 'package:namida/controller/directory_index.dart';
import 'package:namida/controller/files_download_manager.dart';
import 'package:namida/controller/logs_controller.dart';
import 'package:namida/controller/navigator_controller.dart';
import 'package:namida/controller/settings_controller.dart';
import 'package:namida/core/constants.dart';
import 'package:namida/podcast/class/podcast.dart';
import 'package:namida/podcast/controller/podcast_controller.dart';
import 'package:namida/podcast/controller/podcast_library_sync.dart';
import 'package:namida/podcast/otomekoe/otomekoe_parse.dart';

class PodcastDownloadInfo {
  final String episodeId;
  final String showId;
  final String showTitle;
  final String episodeTitle;
  final String artworkUrl;
  final String remoteUrl;
  final String refererUrl;
  final int totalBytes;
  final int downloadedBytes;
  final PodcastDownloadState state;
  final String? localPath;
  final String? errorText;
  final int dateAdded;

  const PodcastDownloadInfo({
    required this.episodeId,
    required this.showId,
    this.showTitle = '',
    this.episodeTitle = '',
    this.artworkUrl = '',
    required this.remoteUrl,
    this.refererUrl = '',
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    this.state = PodcastDownloadState.none,
    this.localPath,
    this.errorText,
    this.dateAdded = 0,
  });

  double get progress {
    if (totalBytes <= 0) return 0;
    return (downloadedBytes / totalBytes).clamp(0.0, 1.0);
  }

  PodcastDownloadInfo copyWith({
    int? totalBytes,
    int? downloadedBytes,
    PodcastDownloadState? state,
    String? localPath,
    String? errorText,
    bool clearError = false,
  }) {
    return PodcastDownloadInfo(
      episodeId: episodeId,
      showId: showId,
      showTitle: showTitle,
      episodeTitle: episodeTitle,
      artworkUrl: artworkUrl,
      remoteUrl: remoteUrl,
      refererUrl: refererUrl,
      totalBytes: totalBytes ?? this.totalBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      state: state ?? this.state,
      localPath: localPath ?? this.localPath,
      errorText: clearError ? null : (errorText ?? this.errorText),
      dateAdded: dateAdded,
    );
  }

  factory PodcastDownloadInfo.fromEpisode(PodcastEpisode ep) {
    return PodcastDownloadInfo(
      episodeId: ep.id,
      showId: ep.showId,
      showTitle: ep.showTitle,
      episodeTitle: ep.title,
      artworkUrl: ep.artworkUrl,
      remoteUrl: ep.audioUrl,
      refererUrl: ep.refererUrl,
      totalBytes: ep.fileSize,
      state: ep.isDownloaded ? PodcastDownloadState.done : PodcastDownloadState.none,
      localPath: ep.downloadedPath,
      dateAdded: DateTime.now().millisecondsSinceEpoch,
    );
  }

  factory PodcastDownloadInfo.fromJson(Map<String, dynamic> json) {
    return PodcastDownloadInfo(
      episodeId: json['id'] as String? ?? '',
      showId: json['showId'] as String? ?? '',
      showTitle: json['showTitle'] as String? ?? '',
      episodeTitle: json['episodeTitle'] as String? ?? '',
      artworkUrl: json['artworkUrl'] as String? ?? '',
      remoteUrl: json['url'] as String? ?? '',
      refererUrl: json['ref'] as String? ?? '',
      totalBytes: json['total'] as int? ?? 0,
      downloadedBytes: json['downloaded'] as int? ?? 0,
      state: PodcastDownloadState.fromName(json['state'] as String?),
      localPath: json['path'] as String?,
      errorText: json['error'] as String?,
      dateAdded: json['dateAdded'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': episodeId,
    'showId': showId,
    'showTitle': showTitle,
    'episodeTitle': episodeTitle,
    'artworkUrl': artworkUrl,
    'url': remoteUrl,
    if (refererUrl.isNotEmpty) 'ref': refererUrl,
    'total': totalBytes,
    'downloaded': downloadedBytes,
    'state': state.name,
    if (localPath != null) 'path': localPath,
    if (errorText != null) 'error': errorText,
    'dateAdded': dateAdded,
  };

  /// 从任务信息反推单集，用于让已下载的单集在重启后依然显示为离线 / 直接播放。
  ///
  /// 优先回 [PodcastController.episodesCache] 里取**完整**单集（带时长、描述），
  /// 取不到才降级用任务自身的信息 —— 否则播放时进度条和通知会没有时长。
  PodcastEpisode toEpisode() {
    for (final list in PodcastController.inst.episodesCache.value.values) {
      for (final e in list) {
        if (e.id == episodeId) return e.copyWith(downloadedPath: localPath);
      }
    }
    return PodcastEpisode(
      id: episodeId,
      showId: showId,
      showTitle: showTitle,
      title: episodeTitle,
      artworkUrl: artworkUrl,
      audioUrl: remoteUrl,
      refererUrl: refererUrl,
      downloadedPath: localPath,
    );
  }
}

/// 播客离线下载任务。复用 [FilesDownloadManager]（多线程分块 + 断点续传）。
class PodcastDownloadsController {
  PodcastDownloadsController._internal();

  static final PodcastDownloadsController inst = PodcastDownloadsController._internal();

  // -- 注意: 这是**文件**路径, 结尾不能加 pathSeparator, 否则会被当成目录创建
  // -- (表现为 `podcast_downloads.json/` 变成目录, 之后每次保存都抛 FileSystemException)。
  static final _tasksFilePath = '${AppDirs.PODCAST_MAIN_DIRECTORY}podcast_downloads.json';

  /// episodeId -> 任务。
  final tasks = <String, PodcastDownloadInfo>{}.obs;

  final activeCount = 0.obs;

  List<PodcastDownloadInfo> get allTasks => tasks.values.toList()..sort((a, b) => b.dateAdded.compareTo(a.dateAdded));

  List<PodcastDownloadInfo> get downloadingTasks => allTasks.where((e) => e.state == PodcastDownloadState.downloading).toList();

  List<PodcastDownloadInfo> get completedTasks => allTasks.where((e) => e.state == PodcastDownloadState.done).toList();

  PodcastDownloadInfo? taskFor(String episodeId) => tasks[episodeId];

  bool isDownloaded(String episodeId) {
    final task = tasks[episodeId];
    return task != null && task.state == PodcastDownloadState.done && (task.localPath?.isNotEmpty ?? false);
  }

  bool isDownloading(String episodeId) {
    final task = tasks[episodeId];
    return task != null && task.state == PodcastDownloadState.downloading;
  }

  String? localPathFor(String episodeId) {
    final task = tasks[episodeId];
    if (task == null || task.state != PodcastDownloadState.done) return null;
    return task.localPath;
  }

  /// 播客单集标题往往超长且带非法字符，文件名需要单独清理。
  static final _illegalFilenameChars = RegExp(r'[\\/:*?"<>|\x00-\x1F]');

  String _sanitize(String value, int maxLength) {
    final cleaned = value.replaceAll(_illegalFilenameChars, '_').trim();
    if (cleaned.length <= maxLength) return cleaned;
    return cleaned.substring(0, maxLength).trim();
  }

  String _filenameFor(PodcastEpisode ep) {
    final show = ep.showTitle.isNotEmpty ? ep.showTitle : ep.showId;
    final sanitized = _sanitize('$show - ${ep.title}', 100);
    return sanitized.isEmpty ? _sanitize(ep.id, 60) : sanitized;
  }

  String _destinationFor(PodcastEpisode ep, {String? extension}) {
    final showDir = _sanitize(ep.showId, 50);
    // -- 用 AppDirs.PODCAST_DOWNLOADS(可由设置项改), 而不是写死的 PODCAST_DOWNLOADS_DEFAULT。
    final dir = Directory('${AppDirs.PODCAST_DOWNLOADS}$showDir/');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    // -- 注意 `Directory.path` 返回的路径**不带**尾斜杠, 直接拼文件名会粘成
    // -- `12345某个节目.mp3` 这种, 所以这里必须显式补一个分隔符。
    return '${dir.path}${_sanitize(_filenameFor(ep), 80)}.${extension ?? ep.extension}';
  }

  Future<void> prepare() async {
    // -- episodes must be indexed by the library scanner without the user
    // -- manually adding the download folder (which may be a custom location).
    try {
      final current = settings.directoriesToScan.value;
      final covered = ensureDirectoryCovered(current, DirectoryIndexLocal(AppDirs.PODCAST_DOWNLOADS));
      if (covered.length != current.length) settings.directoriesToScan.replace(covered);
    } catch (e, st) {
      logger.error('podcast downloads dir sync failed', e: e, st: st);
    }

    try {
      final file = File(_tasksFilePath);
      if (!await file.exists()) return;
      final content = await file.readAsString();
      if (content.trim().isEmpty) return;
      final decoded = jsonDecode(content);
      if (decoded is! List) return;

      final restored = <String, PodcastDownloadInfo>{};
      for (final raw in decoded.whereType<Map>()) {
        final info = PodcastDownloadInfo.fromJson(raw.cast<String, dynamic>());
        if (info.episodeId.isEmpty) continue;

        // -- 文件可能已被用户手动删掉。
        final localPath = info.localPath;
        if (info.state == PodcastDownloadState.done && (localPath == null || !await File(localPath).exists())) {
          restored[info.episodeId] = info.copyWith(state: PodcastDownloadState.none, clearError: true);
        } else if (info.state == PodcastDownloadState.downloading) {
          // -- 上次进程被杀时留下的"下载中", isolate 早没了。
          // -- 但字节可能已全部落盘, 所以先按真实文件情况判定, 免得白让用户重下。
          var size = 0;
          final stalledPath = info.localPath;
          if (stalledPath != null) {
            try {
              final f = File(stalledPath);
              if (await f.exists()) size = await f.length();
            } catch (_) {}
          }

          restored[info.episodeId] = size > 0
              ? info.copyWith(
                  state: PodcastDownloadState.done,
                  downloadedBytes: size,
                  totalBytes: info.totalBytes > size ? info.totalBytes : size,
                  clearError: true,
                )
              : info.copyWith(
                  state: PodcastDownloadState.failed,
                  errorText: 'Interrupted (app was closed)',
                );
        } else {
          restored[info.episodeId] = info;
        }
      }
      tasks.assignAll(restored);
      _refreshActiveCount();
    } catch (e, st) {
      logger.error('podcast downloads load failed', e: e, st: st);
    }
  }

  Future<void> _save() async {
    try {
      final file = File(_tasksFilePath);
      await file.create(recursive: true);
      await file.writeAsString(jsonEncode(allTasks.map((e) => e.toJson()).toList()), flush: true);
    } catch (e, st) {
      logger.error('podcast downloads save failed', e: e, st: st);
    }
  }

  Future<void> download(PodcastEpisode episode) async {
    if (episode.audioUrl.isEmpty) return;
    if (isDownloading(episode.id)) return;
    if (isDownloaded(episode.id)) return;

    final url = Uri.tryParse(episode.audioUrl);
    if (url == null) return;

    // -- HLS 是"播放列表+分片", 分块 Range 下载器完全用不上, 走 ffmpeg remux。
    if (url.path.toLowerCase().endsWith('.m3u8')) {
      return _downloadHls(episode);
    }

    final destination = _destinationFor(episode);
    final file = File(destination);

    final info = PodcastDownloadInfo.fromEpisode(episode).copyWith(
      state: PodcastDownloadState.downloading,
      downloadedBytes: 0,
      clearError: true,
    );
    tasks[episode.id] = info;
    _refreshActiveCount();
    unawaited(_save());

    // -- 共享下载器只在「拿到响应后」才有停滞超时, 连接建立阶段(被墙/DNS 慢)会无限挂起,
    // -- 表现为任务永远停在 downloading 且 0 字节。所以这里自己加一个「无进度超时」。
    var lastProgressAt = DateTime.now();
    var lastReportedBytes = 0;
    final stallTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      final task = tasks[episode.id];
      if (task == null || task.state != PodcastDownloadState.downloading) {
        timer.cancel();
        return;
      }
      final idleFor = DateTime.now().difference(lastProgressAt);
      final noBytes = task.downloadedBytes == lastReportedBytes;
      if (idleFor.inSeconds >= 30 && noBytes) {
        timer.cancel();

        // -- 先看文件: 有时字节已全部落盘, 只是 isolate 那边 Future 没返回,
        // -- 这时直接判成功, 否则用户会看到"文件在但状态是失败/一直转圈"。
        var size = 0;
        try {
          if (await file.exists()) size = await file.length();
        } catch (_) {}

        if (size > 0) {
          tasks[episode.id] = task.copyWith(
            state: PodcastDownloadState.done,
            downloadedBytes: size,
            totalBytes: task.totalBytes > size ? task.totalBytes : size,
            localPath: destination,
            clearError: true,
          );
          PodcastController.inst.onEpisodeDownloaded(episode, destination);
        } else {
          await FilesDownloadManager.inst.stopDownload(file: file);
          tasks[episode.id] = task.copyWith(
            state: PodcastDownloadState.failed,
            errorText: 'Server unreachable (no data for 30s)',
          );
          snackyy(
            title: 'Download failed',
            message: 'Server unreachable. This episode host may be blocked on your network.',
            isError: true,
          );
        }

        _refreshActiveCount();
        unawaited(_save());
      }
    });

    Object? result;
    try {
      result = await FilesDownloadManager.inst.download(
        url: url,
        file: file,
        totalBytes: episode.fileSize,
        threads: episode.fileSize > 0 ? 4 : 1,
        downloadingStream: (bytesDelta) {
          final current = tasks[episode.id];
          if (current == null) return;
          final downloaded = current.downloadedBytes + bytesDelta;
          // -- 这里**绝不能**顺手把 totalBytes 设成 downloaded:
          // -- 第一批数据(通常只有几 KB)一到就会把 total 固化成那个小值, 之后永不更新,
          // -- 结果就是 61MB 的文件显示成 "8 KB / 8 KB"。总数只在下载真正结束时用文件实际大小写。
          tasks[episode.id] = current.copyWith(downloadedBytes: downloaded);
          if (downloaded != lastReportedBytes) {
            lastReportedBytes = downloaded;
            lastProgressAt = DateTime.now();
          }
        },
      );
    } catch (e, st) {
      // -- 不兜住的话异常会从 onPressed 抛出, 界面看起来就是"点了没反应"。
      logger.error('podcast download failed', e: e, st: st);
      result = e;
    } finally {
      stallTimer.cancel();
    }

    final current = tasks[episode.id];
    if (current == null) return;

    if (result is Exception) {
      tasks[episode.id] = current.copyWith(
        state: PodcastDownloadState.failed,
        errorText: result.toString(),
      );
    } else if (await file.exists()) {
      final size = await file.length();
      tasks[episode.id] = current.copyWith(
        state: PodcastDownloadState.done,
        downloadedBytes: size,
        totalBytes: current.totalBytes > 0 ? current.totalBytes : size,
        localPath: destination,
        clearError: true,
      );
      PodcastController.inst.onEpisodeDownloaded(episode, destination);
    } else {
      tasks[episode.id] = current.copyWith(state: PodcastDownloadState.failed, errorText: 'file not found');
    }

    _refreshActiveCount();
    unawaited(_save());

    // -- 明确告诉用户结果, 否则"点了没反应"会让人以为功能坏了。
    final finished = tasks[episode.id];
    if (finished != null && finished.state == PodcastDownloadState.failed) {
      snackyy(
        title: 'Download failed',
        message: _friendlyDownloadError(finished.errorText),
        isError: true,
      );
    }
  }

  /// HLS 下载: ffmpeg 把 m3u8 音轨无损 remux 成单个 m4a。
  /// ffmpeg 以 quiet 日志运行拿不到进度, 只能轮询输出文件大小(不确定态)。
  Future<void> _downloadHls(PodcastEpisode episode) async {
    final destination = _destinationFor(episode, extension: 'm4a');
    final file = File(destination);

    tasks[episode.id] = PodcastDownloadInfo.fromEpisode(episode).copyWith(
      state: PodcastDownloadState.downloading,
      downloadedBytes: 0,
      localPath: destination,
      clearError: true,
    );
    _refreshActiveCount();
    unawaited(_save());

    final poll = Timer.periodic(const Duration(seconds: 2), (timer) {
      final task = tasks[episode.id];
      if (task == null || task.state != PodcastDownloadState.downloading) {
        timer.cancel();
        return;
      }
      try {
        if (file.existsSync()) tasks[episode.id] = task.copyWith(downloadedBytes: file.lengthSync());
      } catch (_) {}
    });

    final hasReferer = episode.refererUrl.isNotEmpty;
    bool ok = false;
    try {
      ok = await NamidaFFMPEG.inst.remuxHlsToM4a(
        url: episode.audioUrl,
        savePath: destination,
        userAgent: hasReferer ? otomekoeBrowserUA : null,
        referer: hasReferer ? episode.refererUrl : null,
      );
    } catch (e, st) {
      logger.error('podcast hls download failed', e: e, st: st);
    } finally {
      poll.cancel();
    }

    final current = tasks[episode.id];
    if (current == null || current.state != PodcastDownloadState.downloading) {
      // -- 用户已取消: 清掉 ffmpeg 留下的半截文件。
      try {
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
      return;
    }

    if (ok && file.existsSync()) {
      final size = await file.length();
      tasks[episode.id] = current.copyWith(
        state: PodcastDownloadState.done,
        downloadedBytes: size,
        totalBytes: size,
        localPath: destination,
        clearError: true,
      );
      PodcastController.inst.onEpisodeDownloaded(episode, destination);
    } else {
      try {
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
      tasks[episode.id] = current.copyWith(
        state: PodcastDownloadState.failed,
        errorText: 'HLS remux failed (ffmpeg)',
      );
      snackyy(title: 'Download failed', message: 'Could not save this HLS stream.', isError: true);
    }

    _refreshActiveCount();
    unawaited(_save());
  }

  /// 把底层异常翻译成人能看懂的话, 并提示可能被墙/需要代理。
  static String _friendlyDownloadError(String? errorText) {    final text = errorText ?? '';
    if (text.contains('timed out') || text.contains('Failed host lookup') || text.contains('Connection refused')) {
      return 'Server unreachable. This episode host may be blocked on your network.';
    }
    if (text.contains('404')) return 'Episode file is no longer available (404).';
    if (text.isEmpty) return 'Unknown error.';
    return text.length > 140 ? '${text.substring(0, 140)}...' : text;
  }

  Future<void> cancel(String episodeId) async {
    final task = tasks[episodeId];
    if (task == null) return;
    await FilesDownloadManager.inst.stopDownload(file: task.localPath != null ? File(task.localPath!) : null);
    if (task.state == PodcastDownloadState.downloading) {
      tasks[episodeId] = task.copyWith(state: PodcastDownloadState.none, clearError: true);
    }
    _refreshActiveCount();
    unawaited(_save());
  }

  Future<void> remove(String episodeId) async {
    final task = tasks[episodeId];
    if (task == null) return;

    await FilesDownloadManager.inst.stopDownload(file: task.localPath != null ? File(task.localPath!) : null);
    final localPath = task.localPath;
    if (localPath != null) {
      FilesDownloadManager.deleteDownloadFiles(File(localPath));
    }

    tasks.remove(episodeId);
    _refreshActiveCount();
    unawaited(_save());

    if (localPath != null) {
      PodcastController.inst.onEpisodeDownloadRemoved(task.toEpisode());
    }
  }

  Future<void> retry(String episodeId) async {
    final task = tasks[episodeId];
    if (task == null) return;
    final episode = task.toEpisode();
    tasks.remove(episodeId);
    final localPath = task.localPath;
    if (localPath != null) {
      FilesDownloadManager.deleteDownloadFiles(File(localPath));
    }
    await download(episode);
  }

  Future<void> removeAllCompleted() async {
    final completed = completedTasks;
    for (final task in completed) {
      await remove(task.episodeId);
    }
  }

  void _refreshActiveCount() {
    activeCount.value = tasks.values.where((e) => e.state == PodcastDownloadState.downloading).length;
  }
}