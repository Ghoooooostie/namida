import 'dart:io';

import 'package:flutter_archive/flutter_archive.dart';
import 'package:nampack/nampack.dart';
import 'package:path_provider/path_provider.dart' show getApplicationDocumentsDirectory;
import 'package:vosk_flutter_fixed/vosk_flutter.dart';

import 'package:namida/class/file_parts.dart';
import 'package:namida/controller/ai_subtitle/ai_subtitle_config.dart';
import 'package:namida/controller/logs_controller.dart';
import 'package:namida/core/constants.dart';

/// A downloadable vosk model.
class VoskModelInfo {
  /// the folder name vosk unpacks to, this is also the id used everywhere.
  final String name;
  final String label;
  final String url;
  final String sizeText;
  final String? note;

  /// where the same zip is mirrored on the hf hosts (`<repo>/resolve/main/<path>`),
  /// used when the official host cannot be reached. null = no mirror known.
  final String? mirrorPath;

  const VoskModelInfo({
    required this.name,
    required this.label,
    required this.url,
    required this.sizeText,
    this.note,
    this.mirrorPath,
  });
}

/// A downloadable sherpa-onnx model, fetched as individual files from
/// huggingface with hf-mirror.com tried as the fallback channel.
class AiLocalModelInfo {
  final String name;
  final String label;
  final AiLocalAsrEngine engine;
  final String sizeText;
  final String? note;

  /// the huggingface repo id, files are read from `<host>/<repo>/resolve/main/<file>`.
  final String hfRepo;

  /// relative paths inside the repo, in download order (the model file first).
  final List<String> files;

  const AiLocalModelInfo({
    required this.name,
    required this.label,
    required this.engine,
    required this.hfRepo,
    required this.files,
    required this.sizeText,
    this.note,
  });
}

/// Where local ASR models live, and how they get there.
///
/// The vosk plugin's own loader handles vosk models (zip, unpacked into the app
/// documents directory), sherpa-onnx models are plain file downloads into the
/// same model folder, so both runtimes find everything in one place.
class AiSubtitleModels {
  static const voskModels = <VoskModelInfo>[
    VoskModelInfo(
      name: 'vosk-model-small-cn-0.22',
      label: 'Vosk small · Chinese',
      url: 'https://alphacephei.com/vosk/models/vosk-model-small-cn-0.22.zip',
      sizeText: '42 MB',
      note: 'Fastest, good enough for a first pass.',
      mirrorPath: 'rhasspy/vosk-models/resolve/main/zh/vosk-model-small-cn-0.22.zip',
    ),
    VoskModelInfo(
      name: 'vosk-model-cn-0.22',
      label: 'Vosk big · Chinese',
      url: 'https://alphacephei.com/vosk/models/vosk-model-cn-0.22.zip',
      sizeText: '1.3 GB',
      note: 'Most accurate, needs a lot of disk and patience.',
    ),
    VoskModelInfo(
      name: 'vosk-model-small-en-us-0.15',
      label: 'Vosk small · English',
      url: 'https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip',
      sizeText: '40 MB',
      mirrorPath: 'rhasspy/vosk-models/resolve/main/en/vosk-model-small-en-us-0.15.zip',
    ),
    VoskModelInfo(
      name: 'vosk-model-small-ja-0.22',
      label: 'Vosk small · Japanese',
      url: 'https://alphacephei.com/vosk/models/vosk-model-small-ja-0.22.zip',
      sizeText: '48 MB',
      mirrorPath: 'rhasspy/vosk-models/resolve/main/ja/vosk-model-small-ja-0.22.zip',
    ),
    VoskModelInfo(
      name: 'vosk-model-small-ko-0.22',
      label: 'Vosk small · Korean',
      url: 'https://alphacephei.com/vosk/models/vosk-model-small-ko-0.22.zip',
      sizeText: '85 MB',
      mirrorPath: 'rhasspy/vosk-models/resolve/main/ko/vosk-model-small-ko-0.22.zip',
    ),
  ];

  static const sherpaModels = <AiLocalModelInfo>[
    AiLocalModelInfo(
      name: 'sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17',
      label: 'SenseVoice · zh/en/ja/ko/yue',
      engine: AiLocalAsrEngine.senseVoice,
      hfRepo: 'csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17',
      files: ['model.int8.onnx', 'tokens.txt'],
      sizeText: '~230 MB',
      note: 'Best quality for CJK languages, with word timestamps.',
    ),
    AiLocalModelInfo(
      name: 'sherpa-onnx-paraformer-zh-2024-03-09',
      label: 'Paraformer · zh/en',
      engine: AiLocalAsrEngine.paraformer,
      hfRepo: 'csukuangfj/sherpa-onnx-paraformer-zh-2024-03-09',
      files: ['model.int8.onnx', 'tokens.txt'],
      sizeText: '~230 MB',
      note: 'Fast, Mandarin focused.',
    ),
    AiLocalModelInfo(
      name: 'sherpa-onnx-whisper-tiny.en',
      label: 'Whisper tiny.en · English',
      engine: AiLocalAsrEngine.whisper,
      hfRepo: 'csukuangfj/sherpa-onnx-whisper-tiny.en',
      files: ['tiny.en-encoder.int8.onnx', 'tiny.en-decoder.int8.onnx', 'tiny.en-tokens.txt'],
      sizeText: '~75 MB',
      note: 'English only, reliable word timestamps.',
    ),
    AiLocalModelInfo(
      name: 'sherpa-onnx-whisper-tiny',
      label: 'Whisper tiny · multilingual',
      engine: AiLocalAsrEngine.whisper,
      hfRepo: 'csukuangfj/sherpa-onnx-whisper-tiny',
      files: ['tiny-encoder.int8.onnx', 'tiny-decoder.int8.onnx', 'tiny-tokens.txt'],
      sizeText: '~150 MB',
      note: '99 languages, auto language detection.',
    ),
    AiLocalModelInfo(
      name: 'sherpa-onnx-moonshine-tiny-en-int8',
      label: 'Moonshine tiny · English',
      engine: AiLocalAsrEngine.moonshine,
      hfRepo: 'csukuangfj/sherpa-onnx-moonshine-tiny-en-int8',
      files: ['preprocess.onnx', 'encode.int8.onnx', 'uncached_decode.int8.onnx', 'cached_decode.int8.onnx', 'tokens.txt'],
      sizeText: '~50 MB',
      note: 'Fastest English model, timing is approximate.',
    ),
  ];

  static VoskModelInfo? infoFor(String? name) {
    if (name == null || name.isEmpty) return null;
    for (final model in voskModels) {
      if (model.name == name) return model;
    }
    return null;
  }

  static AiLocalModelInfo? sherpaInfoFor(String? name) {
    if (name == null || name.isEmpty) return null;
    for (final model in sherpaModels) {
      if (model.name == name) return model;
    }
    return null;
  }

  static Future<Directory> _root() async {
    final dir = Directory(FileParts.joinPath(AppDirs.USER_DATA, 'Models'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  /// The plugin picks where it unpacks, so this looks in our own model folder
  /// first and then asks the loader where it actually put things.
  static Future<String> localModelPath(String? name) async {
    if (name == null || name.isEmpty) return '';
    final root = await _root();
    final direct = Directory(FileParts.joinPath(root.path, name));
    if (direct.existsSync()) return direct.path;

    final documents = await _documentsPath();
    final fromDocuments = Directory(FileParts.joinPath(documents, name));
    if (fromDocuments.existsSync()) return fromDocuments.path;

    try {
      final loader = ModelLoader(modelStorage: root.path);
      final path = await loader.modelPath(name);
      if (path.isNotEmpty && Directory(path).existsSync()) return path;
    } catch (_) {}

    return direct.path;
  }

  static Future<String> _documentsPath() async {
    try {
      return (await getApplicationDocumentsDirectory()).path;
    } catch (_) {
      return AppDirs.USER_DATA;
    }
  }

  static Future<bool> isLocalModelInstalled(String? name) async {
    if (name == null || name.isEmpty) return false;
    final path = await localModelPath(name);
    return path.isNotEmpty && Directory(path).existsSync();
  }

  /// Every model dir sitting in the model folders, whichever engine it belongs to.
  static Future<Set<String>> installedModelNames() async {
    final found = <String>{};

    final root = await _root();
    if (root.existsSync()) {
      for (final entity in root.listSync()) {
        if (entity is Directory) found.add(entity.uri.pathSegments.where((s) => s.isNotEmpty).last);
      }
    }

    try {
      final documentsDir = Directory(await _documentsPath());
      if (documentsDir.existsSync()) {
        for (final entity in documentsDir.listSync()) {
          if (entity is Directory && entity.uri.pathSegments.last.startsWith('vosk-model')) {
            found.add(entity.uri.pathSegments.last);
          }
        }
      }
    } catch (_) {}

    return found;
  }
  static final isDownloading = false.obs;
  static final downloadingModelName = ''.obs;
  static final downloadProgress = 0.0.obs;
  static final downloadError = Rxn<String>();

  /// Downloads the archive to disk and unpacks it with the platform unzip.
  ///
  /// The official host is tried first, the hf mirror (when the model has one)
  /// after. The plugin's own `ModelLoader.loadFromNetwork` reads the whole zip
  /// into memory before extracting, which dies on the bigger models, and it
  /// reports no progress at all - streaming the download and extracting through
  /// `flutter_archive` keeps the memory flat, gives a real progress bar, and
  /// lets us log why a download failed. Null means it failed, the reason lands
  /// in [downloadError].
  static Future<String?> downloadVoskModel(VoskModelInfo info) async {
    if (isDownloading.value) return null;

    isDownloading.value = true;
    downloadingModelName.value = info.name;
    downloadProgress.value = 0;
    downloadError.value = null;

    HttpClient? client;
    File? archive;

    try {
      final root = await _root();
      archive = File(FileParts.joinPath(root.path, '${info.name}.zip'));

      // ---------- download (0 -> 0.9) ----------
      client = _newClient();
      await _downloadTo(
        client,
        _voskUrls(info),
        archive,
        progressSpan: 0.9,
      );

      // ---------- extract (0.9 -> 1) ----------
      await ZipFile.extractToDirectory(
        zipFile: archive,
        destinationDir: root,
        onExtracting: (entry, progress) {
          downloadProgress.value = 0.9 + progress.clamp(0.0, 1.0) * 0.1;
          return ZipFileOperation.includeItem;
        },
      );

      final extracted = Directory(FileParts.joinPath(root.path, info.name));
      if (!extracted.existsSync()) {
        throw 'the archive did not contain a "${info.name}" folder';
      }

      downloadProgress.value = 1;
      return extracted.path;
    } catch (e, st) {
      logger.error('ai subtitle: downloading model ${info.name}', e: e, st: st);
      downloadError.value = e.toString();
      return null;
    } finally {
      try {
        client?.close(force: true);
      } catch (_) {}
      // -- the zip is as big as the model, do not keep it around.
      try {
        if (archive != null && archive.existsSync()) await archive.delete();
      } catch (_) {}

      isDownloading.value = false;
      downloadingModelName.value = '';
      downloadProgress.value = 0;
    }
  }

  static List<String> _voskUrls(VoskModelInfo info) {
    return [
      info.url,
      if (info.mirrorPath != null) ..._hfHosts.map((host) => '$host/${info.mirrorPath}'),
    ];
  }

  /// A client that gives up on a dead host quickly - a hung connection would
  /// otherwise stall the fallback forever.
  static HttpClient _newClient() {
    return HttpClient()..connectionTimeout = const Duration(seconds: 15);
  }

  /// huggingface first, the well known mirror as the fallback channel - it is
  /// only consulted when the primary host actually failed for a file.
  ///
  /// The mirror goes FIRST for the sherpa models though: huggingface.co itself
  /// is unreachable on many networks (the tls handshake gets cut there), while
  /// the mirror answers. Vosk keeps the official host first, it is fine and
  /// holds the models the mirror does not have.
  static const _hfHosts = ['https://hf-mirror.com', 'https://huggingface.co'];

  /// Downloads a sherpa-onnx model as its individual files, so nothing has to be
  /// unpacked (the release archives are tar.bz2, which dart cannot stream) and a
  /// half fetched file can be retried on its own. Null means it failed, the
  /// reason lands in [downloadError].
  static Future<String?> downloadSherpaModel(AiLocalModelInfo info) async {
    if (isDownloading.value) return null;

    isDownloading.value = true;
    downloadingModelName.value = info.name;
    downloadProgress.value = 0;
    downloadError.value = null;

    HttpClient? client;

    try {
      final root = await _root();
      final modelDir = Directory(FileParts.joinPath(root.path, info.name));
      await modelDir.create(recursive: true);

      client = _newClient();
      for (var i = 0; i < info.files.length; i++) {
        final fileName = info.files[i];
        final target = File(FileParts.joinPath(modelDir.path, fileName));

        // -- already complete from an earlier attempt, keep it.
        if (target.existsSync() && target.lengthSync() > 0) continue;

        final urls = _hfHosts.map((host) => '$host/${info.hfRepo}/resolve/main/$fileName');
        await _downloadTo(
          client,
          urls,
          target,
          progressSpan: 1 / info.files.length,
          baseProgress: i / info.files.length,
        );
      }

      // -- the big model file is the whole point, a stub means the sources lied.
      final hasRealContent = info.files.any((file) {
        final f = File(FileParts.joinPath(modelDir.path, file));
        return f.existsSync() && f.lengthSync() > 1024 * 1024;
      });
      if (!hasRealContent) {
        throw 'the model files are missing or truncated, try again';
      }

      downloadProgress.value = 1;
      return modelDir.path;
    } catch (e, st) {
      logger.error('ai subtitle: downloading model ${info.name}', e: e, st: st);
      downloadError.value = e.toString();
      return null;
    } finally {
      try {
        client?.close(force: true);
      } catch (_) {}

      isDownloading.value = false;
      downloadingModelName.value = '';
      downloadProgress.value = 0;
    }
  }

  /// Tries every url in order, tagging the failure with the host so the user
  /// can tell which channel betrayed them. The first host that serves the whole
  /// file wins; failed partial files are removed before the next attempt.
  static Future<void> _downloadTo(
    HttpClient client,
    Iterable<String> urls,
    File target, {
    required double progressSpan,
    double baseProgress = 0.0,
  }) async {
    Object? lastError;

    for (final url in urls) {
      try {
        await _downloadToFile(client, url, target, baseProgress: baseProgress, span: progressSpan);
        return;
      } catch (e) {
        lastError = '${Uri.parse(url).host}: $e';
        logger.error('ai subtitle: downloading $url', e: e);
        try {
          if (target.existsSync()) await target.delete();
        } catch (_) {}
      }
    }

    throw lastError ?? 'could not reach any download source';
  }

  static Future<void> _downloadToFile(
    HttpClient client,
    String url,
    File target, {
    required double baseProgress,
    required double span,
  }) async {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();

    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${response.statusCode} for $url', uri: Uri.parse(url));
    }

    final total = response.contentLength;
    var received = 0;

    final sink = target.openWrite();
    try {
      await for (final chunk in response) {
        received += chunk.length;
        sink.add(chunk);
        // -- an unknown length (no content-length) has to keep the bar moving too.
        downloadProgress.value = total > 0 ? baseProgress + span * (received / total) : baseProgress + span * 0.5;
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    if (total > 0 && received < total) {
      throw 'the download was truncated ($received of $total bytes)';
    }
  }

  /// Removes both the zip and the unpacked folder, the loader keeps them side by side.
  static Future<bool> deleteModel(String name) async {
    try {
      final root = await _root();
      final targets = <String>[FileParts.joinPath(root.path, name)];

      try {
        final documents = await _documentsPath();
        targets
          ..add(FileParts.joinPath(documents, name))
          ..add(FileParts.joinPath(documents, '$name.zip'));
      } catch (_) {}

      for (final path in targets) {
        final dir = Directory(path);
        if (dir.existsSync()) await dir.delete(recursive: true);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Human readable footprint of a downloaded model, for the models page.
  static Future<String> modelSizeText(String name) async {
    try {
      final path = await localModelPath(name);
      final dir = Directory(path);
      if (!dir.existsSync()) return '';

      var bytes = 0;
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is File) bytes += entity.lengthSync();
      }
      return '${(bytes / (1024 * 1024)).ceil()} MB';
    } catch (_) {
      return '';
    }
  }
}
