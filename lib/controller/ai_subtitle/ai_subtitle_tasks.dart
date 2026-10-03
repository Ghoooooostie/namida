import 'dart:async';
import 'dart:io';

import 'package:nampack/nampack.dart';
import 'package:rhttp/rhttp.dart';

import 'package:namida/class/file_parts.dart';
import 'package:namida/class/subtitle_srt.dart';
import 'package:namida/class/subtitle_track.dart';
import 'package:namida/class/track.dart';
import 'package:namida/controller/ai_subtitle/ai_asr_factory.dart';
import 'package:namida/controller/ai_subtitle/ai_asr_shared.dart';
import 'package:namida/controller/ai_subtitle/ai_subtitle_config.dart';
import 'package:namida/controller/ai_subtitle/ai_subtitle_models.dart';
import 'package:namida/controller/ai_subtitle/ai_translation_service.dart';
import 'package:namida/controller/logs_controller.dart';
import 'package:namida/controller/platform/namida_channel/namida_channel.dart';
import 'package:namida/controller/platform/permission_manager/permission_manager.dart';
import 'package:namida/controller/player_controller.dart';
import 'package:namida/controller/subtitles_controller.dart';
import 'package:namida/core/constants.dart';
import 'package:namida/core/extensions.dart';
import 'package:namida/core/translations/language.dart';

enum AiSubtitleTaskState { queued, running, done, failed, cancelled }

/// One audio file going through recognition (and optionally translation).
class AiSubtitleTask {
  final String id;
  final File audioFile;
  final state = AiSubtitleTaskState.queued.obs;
  final progress = 0.0.obs;
  final errorMessage = Rxn<String>();

  /// set once the cues exist, before any translation
  final sourceCues = RxList<SubtitleSrtCue>([]);
  final translatedCues = RxList<SubtitleSrtCue>([]);

  /// the `.srt` that was written, either the source or the translation
  final savedFile = Rxn<File>();

  /// not final: it is downgraded when the translation settings are incomplete,
  /// so a plain transcription still runs instead of the batch being refused.
  bool translateAfter;

  /// when true the audio is not recognized again, the subtitles that already sit
  /// next to the track are read and only translated.
  final bool translateOnly;

  AiSubtitleTask({
    required this.id,
    required this.audioFile,
    required this.translateAfter,
    this.translateOnly = false,
  });

  String get title => audioFile.uri.pathSegments.last;

  bool get isFinished => state.value == AiSubtitleTaskState.done || state.value == AiSubtitleTaskState.failed || state.value == AiSubtitleTaskState.cancelled;

  bool get isActive => state.value == AiSubtitleTaskState.queued || state.value == AiSubtitleTaskState.running;

  @override
  String toString() => 'AiSubtitleTask($title, ${state.value.name})';
}

/// Runs recognition/translation jobs one after another and writes the result
/// next to the audio, which is all the subtitles controller needs to pick it up.
class AiSubtitleTasksController {
  static final inst = AiSubtitleTasksController._();

  AiSubtitleTasksController._() {
    // -- the cancel button on the background notification stops the whole queue.
    NamidaChannel.inst.addOnAiRecognitionCancel(cancel);
  }

  final tasks = <AiSubtitleTask>[].obs;
  final isRunning = false.obs;
  final currentTaskTitle = ''.obs;

  /// Why the queue refuses to start, shown instead of silently sitting at 0%.
  final blockReason = Rxn<String>();

  CancelToken? _cancelToken;
  final _translationService = AiTranslationService();

  /// whether the background service is up for this run, so the first progress
  /// report starts it instead of every task re-starting it.
  bool _bgServiceStarted = false;
  DateTime? _lastBgUpdate;

  /// `RxList` is an `Rx<List<E>>`, not an Iterable, so reads go through this.
  List<AiSubtitleTask> get allTasks => tasks.value;

  List<AiSubtitleTask> get pendingTasks => allTasks.where((t) => !t.isFinished).toList();

  int get doneCount => allTasks.where((t) => t.state.value == AiSubtitleTaskState.done).length;

  int get failedCount => allTasks.where((t) => t.state.value == AiSubtitleTaskState.failed).length;

  void enqueue(Iterable<File> audioFiles, {bool? translateAfter, bool translateOnly = false}) {
    var added = false;
    for (final file in audioFiles) {
      if (!file.existsSync()) continue;
      if (allTasks.any((t) => t.audioFile.path == file.path && !t.isFinished)) continue;

      tasks.add(AiSubtitleTask(
        id: '${DateTime.now().microsecondsSinceEpoch}_${file.path.hashCode.abs()}',
        audioFile: file,
        translateAfter: translateAfter ?? AiSubtitleConfig.inst.translateAfterRecognition.value,
        translateOnly: translateOnly,
      ));
      added = true;
    }

    // -- queuing is not a two step flow: the user picked files, run them.
    if (added) unawaited(run());
  }

  /// Queues a translation of the subtitles the track already has.
  void enqueueTranslationOf(Iterable<File> audioFiles) {
    enqueue(audioFiles, translateAfter: true, translateOnly: true);
  }

  void clearFinished() {
    tasks.value.removeWhere((t) => t.isFinished);
    tasks.refresh();
  }

  void remove(AiSubtitleTask task) {
    if (task.state.value == AiSubtitleTaskState.running) return;
    tasks.value.remove(task);
    tasks.refresh();
  }

  void cancel() {
    _cancelToken?.cancel();
    for (final task in allTasks) {
      if (task.state.value == AiSubtitleTaskState.queued) {
        task.state.value = AiSubtitleTaskState.cancelled;
      }
    }
  }
  /// Runs every pending task in order. Safe to call again after adding files.
  Future<void> run() async {
    if (isRunning.value) return;

    final asrSettings = AiSubtitleConfig.inst.asrSettings;
    var translationSettings = AiSubtitleConfig.inst.translationSettings;

    // -- a missing setting must not throw the whole batch away, and it must not
    // -- leave the tasks looking like they are working: say what is missing and
    // -- keep them queued so the user can fix it and press start again.
    blockReason.value = null;

    if (asrSettings.isLocal) {
      final modelPath = await AiSubtitleModels.localModelPath(asrSettings.localModelName);
      if (!await Directory(modelPath).exists()) {
        blockReason.value = lang.aiSubtitleModelNotReady;
        return;
      }
    } else if (!AiSubtitleConfig.inst.isAsrConfigured) {
      blockReason.value = lang.aiSubtitleAsrMissing;
      return;
    }

    final wantsTranslation = pendingTasks.any((t) => t.translateAfter && !t.translateOnly);
    if (wantsTranslation && !AiSubtitleConfig.inst.isTranslationConfigured) {
      // -- recognition still works on its own, so do that instead of refusing
      // -- the whole batch. The tasks page tells the user what was skipped.
      for (final task in pendingTasks) {
        if (task.translateAfter && !task.translateOnly) task.translateAfter = false;
      }
      translationSettings = AiSubtitleConfig.inst.translationSettings;
    }

    isRunning.value = true;
    _cancelToken = CancelToken();
    _bgServiceStarted = false;

    try {
      for (final task in pendingTasks) {
        if (_cancelToken?.isCancelled ?? false) {
          task.state.value = AiSubtitleTaskState.cancelled;
          continue;
        }

        currentTaskTitle.value = task.title;
        task.state.value = AiSubtitleTaskState.running;
        task.progress.value = 0;
        task.errorMessage.value = null;
        _updateBgService(task.title, lang.aiSubtitleStateRunning, 0);

        try {
          final cues = task.translateOnly ? await _readExistingCues(task) : await _recognize(task, asrSettings);
          task.sourceCues.value = cues;

          var output = cues;
          if (task.translateAfter) {
            task.progress.value = 0.9;
            output = await _translationService.translate(
              cues,
              translationSettings,
              onProgress: (p) {
                task.progress.value = 0.9 + 0.1 * p;
                _updateBgService(task.title, lang.aiSubtitleTranslateAfter, task.progress.value);
              },
              cancelToken: _cancelToken,
            );
            task.translatedCues.value = output;
          }

          // -- the translation is merged into the source cues, so the track's
          // -- own `.srt` carries the original line and the translated one, and
          // -- the lyrics view shows both together.
          final merged = task.translateAfter ? _mergeBilingual(task.sourceCues.value, output) : output;
          final file = await saveCues(merged, task.audioFile);
          task.savedFile.value = file;
          task.progress.value = 1;
          task.state.value = AiSubtitleTaskState.done;

          // -- if this is the track that is playing, show it right away instead
          // -- of making the user dig through the track menu.
          await applyToPlayerIfCurrent(task.audioFile, file);
        } catch (e) {
          if (_cancelToken?.isCancelled ?? false) {
            task.state.value = AiSubtitleTaskState.cancelled;
          } else {
            task.errorMessage.value = e.toString();
            task.state.value = AiSubtitleTaskState.failed;
            logger.error('ai subtitle task failed', e: e);
          }
        }
      }
    } finally {
      isRunning.value = false;
      currentTaskTitle.value = '';
      _cancelToken = null;
      _stopBgService();
    }
  }

  /// Mirrors the queue into the background service: the first report starts the
  /// foreground service (wakelock + notification), the rest update its progress.
  /// Throttled so the notification is not rebuilt on every audio chunk.
  void _updateBgService(String title, String label, double progress) {
    if (!isRunning.value) return;

    final now = DateTime.now();
    final last = _lastBgUpdate;
    if (last != null && now.difference(last) < const Duration(milliseconds: 700)) return;
    _lastBgUpdate = now;

    final percent = (progress.clamp(0, 1) * 100).round();
    final text = '$label · $percent%';

    if (!_bgServiceStarted) {
      _bgServiceStarted = true;
      NamidaChannel.inst.startAiRecognitionService(
        title: title,
        text: text,
        cancelLabel: lang.aiSubtitleCancel,
        channelName: lang.aiSubtitleRecognition,
        channelDescription: lang.aiSubtitleRecognitionSubtitle,
      );
      return;
    }
    NamidaChannel.inst.updateAiRecognitionNotification(title: title, text: text, progress: percent);
  }

  void _stopBgService() {
    _bgServiceStarted = false;
    _lastBgUpdate = null;
    NamidaChannel.inst.stopAiRecognitionService();
  }
  /// Merges the translation into the source cues: every cue carries the
  /// original line with the translated one right below it, so a single `.srt`
  /// file (and the lyrics view) shows both. Cues are paired by timing, which
  /// the translation preserves; slots the translation produced nothing for
  /// keep the plain cue.
  List<SubtitleSrtCue> _mergeBilingual(List<SubtitleSrtCue> source, List<SubtitleSrtCue> translated) {
    final originalOf = <(int, int), String>{
      for (final cue in source) (cue.startMS, cue.endMS): cue.text,
    };

    final merged = <SubtitleSrtCue>[];
    for (final cue in translated) {
      final original = originalOf[(cue.startMS, cue.endMS)]?.trim();
      merged.add(original == null || original.isEmpty ? cue : cue.copyWith(text: '$original\n${cue.text.trim()}'));
    }
    return merged;
  }

  Future<List<SubtitleSrtCue>> _recognize(AiSubtitleTask task, AiAsrSettings asrSettings) async {
    final engine = AiAsrEngineFactory.create(asrSettings);
    final cues = await engine.transcribe(
      task.audioFile,
      settings: asrSettings,
      onProgress: (p) {
        task.progress.value = (p * 0.9).clamp(0, 0.9);
        _updateBgService(task.title, lang.aiSubtitleRecognition, p);
      },
      cancelToken: _cancelToken,
    );

    // -- engines can return a wall of text for a long cue, splitting it here
    // -- keeps the timeline readable for every provider.
    return SubtitleSrt.splitLongCues(SubtitleSrt.normalize(cues));
  }

  /// Writes the `.srt` and, when it belongs to a track, makes the player show it.
  ///
  /// The name matches the audio (`track.srt`), which is exactly what
  /// `Subtitles.inst` looks for, so no extra wiring is needed.
  Future<File> saveCues(List<SubtitleSrtCue> cues, File audio, {String suffix = ''}) async {
    if (cues.isEmpty) throw const AiAsrException('There is nothing to save');

    final content = SubtitleSrt.build(cues);
    final useTrackFolder = AiSubtitleConfig.inst.saveLocation.value == AiSubtitleSaveLocation.trackFolder;

    if (useTrackFolder) {
      final hasPermission = await PermissionManager.platform.requestManageStoragePermission(
        showError: false,
        directoryToCreate: audio.parent.path,
      );

      if (hasPermission) {
        final file = File(_srtPathFor(audio, suffix));
        await file.writeAsString(content);
        return file;
      }
    }

    // -- no permission or the user wants them out of the way, the cache is
    // -- always writable and the track can still be pointed at it manually.
    final fallback = File(FileParts.joinPath(AppDirs.SUBTITLES, '${_baseName(audio)}$suffix.srt'));
    await fallback.parent.create(recursive: true);
    await fallback.writeAsString(content);
    return fallback;
  }

  /// Reads the subtitles that already sit next to the track, in the same order
  /// [Subtitles.inst] discovers them, so "translate" works on an imported or an
  /// embedded track without recognizing the audio again.
  Future<List<SubtitleSrtCue>> _readExistingCues(AiSubtitleTask task) async {
    final base = _baseName(task.audioFile);
    final dirPath = task.audioFile.parent.path;

    // -- an srt first (what this feature writes), then the other subtitle formats.
    const candidates = ['srt', 'vtt', 'ass', 'ssa', 'sbv', 'ttml'];
    for (final extension in candidates) {
      final file = File(FileParts.joinPath(dirPath, '$base.$extension'));
      if (!await file.existsAndValid()) continue;

      final cues = SubtitleSrt.parse(await file.readAsString());
      if (cues.isNotEmpty) return cues;
    }

    throw const AiAsrException('This track has no subtitles to translate yet, recognize it first');
  }

  static String _baseName(File audio) => audio.uri.pathSegments.last.replaceFirst(RegExp(r'\.[^.]+$'), '');

  static String _srtPathFor(File audio, String suffix) {
    return FileParts.joinPath(audio.parent.path, '${_baseName(audio)}$suffix.srt');
  }

  /// Shows [file] right away when it belongs to the track that is playing.
  Future<void> applyToPlayerIfCurrent(File audio, File srt) async {
    try {
      final current = Player.inst.currentItem.value;
      if (current is! Selectable) return;
      if (current.track.path != audio.path) return;

      await Subtitles.inst.selectTrack(SubtitleTrackFile(srt));
    } catch (e) {
      // -- not being able to switch tracks is not a reason to fail the job.
      logger.report(e, null);
    }
  }

  void _failAll(String message) {
    for (final task in allTasks) {
      if (task.isFinished) continue;
      task.errorMessage.value = message;
      task.state.value = AiSubtitleTaskState.failed;
    }
  }
}
