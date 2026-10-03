import 'dart:async';
import 'dart:io';

// ignore: depend_on_referenced_packages
import 'package:collection/collection.dart';
import 'package:uuid/uuid.dart';

import 'package:namida/anki/class/anki_field_templates.dart';
import 'package:namida/anki/class/anki_field_templates.dart';
import 'package:namida/anki/class/anki_mining.dart';
import 'package:namida/anki/class/anki_models.dart';
import 'package:namida/anki/controller/anki_backend.dart';
import 'package:namida/anki/controller/anki_connect_backend.dart';
import 'package:namida/anki/controller/anki_droid_backend.dart';
import 'package:namida/controller/logs_controller.dart';
import 'package:namida/controller/settings_controller.dart';
import 'package:namida/core/utils.dart';
import 'package:namida/dictionary/class/word_lookup.dart';

/// Anki 门面。
///
/// 上层（点词弹窗、听书句子、转录句子）只需要：
/// ```dart
/// final result = await AnkiController.inst.lookupAndAddCard(
///   request: WordLookupRequest(expression: '言葉', sentence: '…', sentenceOffset: 12),
///   context: AnkiMiningContext(documentTitle: '…', audioClipPath: '…'),
/// );
/// ```
/// 查词走 [WordLookupRegistry]，制卡走当前选中的 [AnkiCardFormat]。
class AnkiController {
  static final AnkiController inst = AnkiController._internal();

  static const _uuid = Uuid();

  /// 正在拉牌组/模板。
  final isRefreshing = false.obs;

  /// 后端最近一次是否可用。
  final isBackendAvailable = false.obs;

  /// 最近一次失败的用户可读原因。
  final lastFailureMessage = Rxn<String>();

  /// AnkiDroid 收藏库权限状态，UI 直接 Obx 监听。
  final ankiDroidPermission = AnkiDroidPermission.notDetermined.obs;

  AnkiController._internal() {
    // -- 原生在用户答复权限对话框后主动通知，立刻刷新状态。
    AnkiDroidChannel.inst.addPermissionResultCallback((_) => refreshAnkiDroidPermission());
    unawaited(refreshAnkiDroidPermission());
  }

  /// 重查 AnkiDroid 权限。切后端、刷新、从系统设置页返回后都该调。
  Future<void> refreshAnkiDroidPermission() async {
    final raw = await AnkiDroidChannel.inst.permissionStatus();
    ankiDroidPermission.value = switch (raw) {
      'granted' => AnkiDroidPermission.granted,
      'unavailable' => AnkiDroidPermission.unavailable,
      'denied' => AnkiDroidPermission.denied,
      _ => AnkiDroidPermission.notDetermined,
    };
  }

  /// 申请 AnkiDroid 权限。[goToSettings] 为 true 表示用户拒绝过，只能去系统设置页。
  Future<bool> requestAnkiDroidPermission({bool goToSettings = false}) async {
    if (goToSettings) return AnkiDroidChannel.inst.openAppSettings();
    final asked = await AnkiDroidChannel.inst.requestPermission();
    if (!asked) await refreshAnkiDroidPermission();
    return asked;
  }

  AnkiSettings get _settings => settings.anki.config.value;

  List<AnkiDeck> get availableDecks => _settings.availableDecks;

  List<AnkiNoteType> get availableNoteTypes => _settings.availableNoteTypes;

  List<AnkiCardFormat> get cardFormats => _settings.cardFormats;

  AnkiCardFormat? get defaultFormat => _settings.defaultFormat;

  /// 当前激活的后端。切后端时设置立即落盘，这里读到的一定是最新配置。
  AnkiBackend get backend {
    return switch (_settings.backendKind) {
      AnkiBackendKind.ankiDroid => _ankiDroidBackend,
      AnkiBackendKind.ankiConnect => ankiConnectBackend,
    };
  }

  final AnkiDroidBackend _ankiDroidBackend = AnkiDroidBackend();

  AnkiConnectBackend get ankiConnectBackend => AnkiConnectBackend(
        endpoint: _settings.ankiConnectUrl,
        apiKey: settings.anki.ankiConnectApiKey.value,
      );

  bool get isConfigured => (defaultFormat?.isValid ?? false);

  // ==================================================================
  // 设置
  // ==================================================================

  void updateSettings(AnkiSettings Function(AnkiSettings settings) transform) {
    settings.anki.config.save(transform(_settings));
  }

  void setBackendKind(AnkiBackendKind kind) {
    updateSettings((s) => s.copyWith(backendKind: kind));
    lastFailureMessage.value = null;
    if (kind == AnkiBackendKind.ankiDroid) unawaited(refreshAnkiDroidPermission());
  }

  void setAnkiConnect({String? url, String? apiKey}) {
    if (url != null) {
      final trimmed = url.trim();
      updateSettings((s) => s.copyWith(ankiConnectUrl: trimmed.isEmpty ? kDefaultAnkiConnectUrl : trimmed));
    }
    if (apiKey != null) settings.anki.ankiConnectApiKey.save(apiKey);
  }

  void setAllowDupes(bool value) => updateSettings((s) => s.copyWith(allowDupes: value));

  void setDuplicateScope(AnkiDuplicateScope value) => updateSettings((s) => s.copyWith(duplicateScope: value));

  void setCheckDuplicatesAcrossAllModels(bool value) =>
      updateSettings((s) => s.copyWith(checkDuplicatesAcrossAllModels: value));

  void setSelectedGlossaryFallback(String value) => updateSettings((s) => s.copyWith(selectedGlossaryFallback: value));

  void setForceSync(bool value) => updateSettings((s) => s.copyWith(forceSync: value));

  /// 牌组/卡片类型选择。选完把名字也存一份，牌组在 Anki 里被删了 UI 还显示得出来。
  /// 传 null 且对应的 `clear*` 为 true 才表示「清空选择」，否则表示「不动」。
  void setFormatTarget(
    String formatId, {
    AnkiDeck? deck,
    AnkiNoteType? noteType,
    bool clearDeck = false,
    bool clearNoteType = false,
    bool clearFieldMappings = false,
  }) {
    updateSettings((s) => s.updateCardFormat(
      formatId,
      (format) {
        // -- 换卡片类型后字段名全变了，旧的映射已经没有意义。
        var mappings = clearFieldMappings ? const <String, String>{} : format.fieldMappings;
        if (noteType != null) {
          // -- Lapis / Kiku / Senren 这类固定字段名的类型，直接把内置模板填上。
          //    只在这套模板一个字段都还没映射过时才填，不覆盖用户手写的内容。
          mappings = AnkiFieldTemplates.applyDefaultsIfUnmapped(noteType, mappings);
        }
        return format.copyWith(
          selectedDeckId: deck?.id,
          selectedDeckName: deck?.name,
          selectedNoteTypeId: noteType?.id,
          selectedNoteTypeName: noteType?.name,
          clearDeck: clearDeck,
          clearNoteType: clearNoteType,
          fieldMappings: mappings,
        );
      },
    ));
  }

  /// 写某个字段的 handlebars 模板。
  void setFieldMapping(String formatId, String field, String template) {
    updateSettings((s) => s.updateCardFormat(
      formatId,
      (format) => format.copyWith(fieldMappings: {...format.fieldMappings, field: template}),
    ));
  }

  void setFormatTags(String formatId, String tags) {
    updateSettings((s) => s.updateCardFormat(formatId, (format) => format.copyWith(tags: tags)));
  }

  AnkiCardFormat createFormat({String name = 'Default'}) {
    final format = AnkiCardFormat(id: _uuid.v4(), name: name);
    updateSettings((s) => s.addCardFormat(format));
    return format;
  }

  void renameFormat(String formatId, String name) {
    updateSettings((s) => s.updateCardFormat(formatId, (format) => format.copyWith(name: name)));
  }

  void duplicateFormat(String formatId) {
    final source = cardFormats.firstWhereOrNull((e) => e.id == formatId);
    if (source == null) return;
    updateSettings((s) => s.addCardFormat(source.copyWith(id: _uuid.v4(), name: '${source.name} copy')));
  }

  void removeFormat(String formatId) {
    updateSettings((s) => s.removeCardFormat(formatId));
  }

  // ==================================================================
  // 后端
  // ==================================================================

  /// 拉牌组 + 卡片类型。成功后写回缓存，UI 直接用 [availableDecks] / [availableNoteTypes]。
  Future<bool> refresh() async {
    if (isRefreshing.value) return false;
    isRefreshing.value = true;
    lastFailureMessage.value = null;
    try {
      final backend = this.backend;
      if (!await backend.isAvailable()) {
        isBackendAvailable.value = false;
        lastFailureMessage.value = AnkiFetchException(AnkiFetchFailure.apiUnavailable).userMessage;
        return false;
      }
      final snapshot = await backend.refresh();
      isBackendAvailable.value = true;

      // -- 拉到 0 个牌组几乎一定是解码/解析出了问题，静默"成功"会让人以为功能坏了。
      if (snapshot.decks.isEmpty || snapshot.noteTypes.isEmpty) {
        isBackendAvailable.value = false;
        lastFailureMessage.value = AnkiFetchException(
          snapshot.decks.isEmpty ? AnkiFetchFailure.deckListUnavailable : AnkiFetchFailure.modelListUnavailable,
        ).userMessage;
        return false;
      }

      updateSettings((s) => s.copyWith(
        availableDecks: snapshot.decks,
        availableNoteTypes: snapshot.noteTypes,
      ));
      // -- 刷新后自动补齐牌组 / 卡片类型 / 字段模板，用户不用自己去猜字段名。
      _autoConfigureTargets();
      return true;
    } on AnkiFetchException catch (e) {
      isBackendAvailable.value = false;
      lastFailureMessage.value = e.userMessage;
      return false;
    } catch (e, st) {
      isBackendAvailable.value = false;
      lastFailureMessage.value = 'Anki 通信失败。';
      logger.error('anki: refresh failed', e: e, st: st);
      return false;
    } finally {
      isRefreshing.value = false;
    }
  }

  /// 刷新之后自动补齐配置：挑一副说得过去的牌组 + 一种卡片类型，并按卡片类型套好字段模板。
  ///
  /// 这一步是「点了刷新就能直接制卡」的关键，否则用户还得自己去猜
  /// 牌组叫什么、这个卡片类型有哪些字段、每个字段该填什么。
  void _autoConfigureTargets() {
    final decks = availableDecks;
    final noteTypes = availableNoteTypes;
    if (decks.isEmpty || noteTypes.isEmpty) return;

    updateSettings((s) {
      final deck = _selectDeck(decks, s);
      final noteType = _selectNoteType(noteTypes, s);

      return s.copyWith(
        selectedDeckId: deck?.id ?? s.selectedDeckId,
        selectedDeckName: deck?.name ?? s.selectedDeckName,
        selectedNoteTypeId: noteType?.id ?? s.selectedNoteTypeId,
        selectedNoteTypeName: noteType?.name ?? s.selectedNoteTypeName,
        cardFormats: s.cardFormats
            .map(
              (format) => format.copyWith(
                selectedDeckId: deck?.id,
                selectedDeckName: deck?.name,
                selectedNoteTypeId: noteType?.id,
                selectedNoteTypeName: noteType?.name,
                fieldMappings: noteType == null
                    ? format.fieldMappings
                    : AnkiFieldTemplates.applyDefaultsIfUnmapped(noteType, format.fieldMappings),
              ),
            )
            .toList(),
      );
    });
  }

  /// 保留用户已选的牌组；否则跳过 Anki 默认的 `Default`，挑第一个真实的。
  AnkiDeck? _selectDeck(List<AnkiDeck> decks, AnkiSettings s) {
    final currentId = s.selectedDeckId;
    if (currentId != null) {
      final existing = decks.firstWhereOrNull((e) => e.id == currentId);
      if (existing != null) return existing;
    }
    final byName = s.selectedDeckName;
    if (byName != null) {
      final matched = decks.firstWhereOrNull((e) => e.name == byName);
      if (matched != null) return matched;
    }
    return decks.firstWhereOrNull((e) => e.name.toLowerCase() != 'default') ?? decks.firstOrNull;
  }

  /// 优先选有预设模板的 mining 笔记类型，用户已选的仍然优先。
  AnkiNoteType? _selectNoteType(List<AnkiNoteType> noteTypes, AnkiSettings s) {
    final currentId = s.selectedNoteTypeId;
    if (currentId != null) {
      final existing = noteTypes.firstWhereOrNull((e) => e.id == currentId);
      if (existing != null) return existing;
    }
    final byName = s.selectedNoteTypeName;
    if (byName != null) {
      final matched = noteTypes.firstWhereOrNull((e) => e.name == byName);
      if (matched != null) return matched;
    }
    return noteTypes.firstWhereOrNull(AnkiFieldTemplates.matches) ?? noteTypes.firstOrNull;
  }

  /// 打开 Anki 的卡片浏览器，定位到这条词。
  Future<bool> openNotes({String key = ''}) async {
    final format = defaultFormat;
    final deck = _settings.selectedDeck;
    final noteType = _settings.selectedNoteType;
    if (format == null || deck == null || noteType == null) return false;
    return backend.openNotes(
      deck: deck,
      noteType: noteType,
      key: key.isNotEmpty ? key : _firstFieldValue(format, noteType),
      duplicateScope: _settings.duplicateScope,
      checkDuplicatesAcrossAllModels: _settings.checkDuplicatesAcrossAllModels,
    );
  }

  /// 触发同步。
  Future<bool> sync() => backend.sync();

  /// Android 上直接拉起 AnkiDroid。
  Future<bool> openAnkiDroid() => AnkiDroidChannel.inst.openAnkiDroid();

  /// AnkiDroid 数据库授权状态：granted / denied / notDetermined。
  Future<String?> ankiDroidPermissionStatus() => AnkiDroidChannel.inst.permissionStatus();

  // ==================================================================
  // 查词 -> 制卡
  // ==================================================================

  /// 完整链路：查词 -> 渲染字段 -> 写卡。
  ///
  /// [formatId] 为空时用第一套模板。返回 [AnkiCardOutcome]。
  Future<AnkiCardOutcome> lookupAndAddCard({
    required WordLookupRequest request,
    AnkiMiningContext context = const AnkiMiningContext(),
    String? formatId,
    List<WordLookupGlossary> termGlossaries = const [],
  }) async {
    final format = _resolveFormat(formatId);
    if (format == null || !format.isValid) {
      return const AnkiCardOutcome(AnkiAddResult.invalidFormat, message: '还没有配置制卡模板。');
    }

    WordLookupResult lookup;
    try {
      final result = await WordLookupRegistry.inst.lookup(request);
      if (result == null) {
        return const AnkiCardOutcome(AnkiAddResult.invalidFormat, message: '没有可用的词典。');
      }
      lookup = result;
    } catch (e, st) {
      logger.error('anki: lookup failed', e: e, st: st);
      return const AnkiCardOutcome(AnkiAddResult.failed, message: '查词失败。');
    }

    return addCardForLookup(
      formatId: format.id,
      lookup: lookup,
      context: context,
      termGlossaries: termGlossaries,
    );
  }

  /// 已经有查词结果时直接制卡（听书句子、离线词典结果走这条）。
  Future<AnkiCardOutcome> addCardForLookup({
    required WordLookupResult lookup,
    AnkiMiningContext context = const AnkiMiningContext(),
    String? formatId,
    List<WordLookupGlossary> termGlossaries = const [],
  }) async {
    final format = _resolveFormat(formatId);
    if (format == null || !format.isValid) {
      return const AnkiCardOutcome(AnkiAddResult.invalidFormat, message: '还没有配置制卡模板。');
    }

    final deck = availableDecks.firstWhereOrNull((e) => e.id == format.selectedDeckId);
    final noteType = availableNoteTypes.firstWhereOrNull((e) => e.id == format.selectedNoteTypeId);
    if (deck == null || noteType == null) {
      return const AnkiCardOutcome(AnkiAddResult.invalidFormat, message: '牌组或卡片类型已失效，请重新刷新。');
    }

    final effectiveContext = context.copyWithDefaultsFrom(lookup);

    // -- 媒体**先**入库：这样模板里的 {audio-clip} / {book-cover} 渲染出来就是真正的
    //    Anki 引用（[sound:x] / <img src="x">），而不是本地路径再回头替换。
    //    只上传模板真正用到的媒体，避免每张卡都白传一遍封面。
    final templates = noteType.fields.map((f) => format.fieldMappings[f] ?? '').join('\n');
    final needsClip = templates.contains('{audio-clip}');
    final needsCover = templates.contains('{book-cover}');
    final needsShot = templates.contains('{sentence-image}');
    final needsWordAudio = templates.contains('{audio}');

    final mediaContext = effectiveContext.copyWith(
      audioClipPath: needsClip ? effectiveContext.audioClipPath : null,
      coverPath: needsCover ? effectiveContext.coverPath : null,
      sentenceImagePath: needsShot ? effectiveContext.sentenceImagePath : null,
    );
    final mediaLookup = lookup.copyWith(wordAudioPath: needsWordAudio ? lookup.wordAudioPath : null);

    final uploaded = await _uploadMedia(mediaLookup, mediaContext);

    final rendered = AnkiFieldRenderer.renderFields(
      noteType: noteType,
      fieldMappings: format.fieldMappings,
      lookup: uploaded.lookup,
      context: uploaded.context,
      selectedGlossaryFallback: _settings.selectedGlossaryFallback,
      termGlossaries: termGlossaries,
    );
    final finalFields = Map<String, String>.from(rendered.fields);

    final backend = this.backend;
    try {
      final ok = await backend.addNote(
        deck: deck,
        noteType: noteType,
        fieldsByName: finalFields,
        tags: format.tagList,
        allowDupes: _settings.allowDupes,
        duplicateScope: _settings.duplicateScope,
        checkDuplicatesAcrossAllModels: _settings.checkDuplicatesAcrossAllModels,
      );
      if (!ok) {
        return const AnkiCardOutcome(AnkiAddResult.duplicate, message: '已经有一张一样的卡了。');
      }
    } catch (e, st) {
      logger.error('anki: add card failed', e: e, st: st);
      return const AnkiCardOutcome(AnkiAddResult.failed, message: '写卡失败。');
    }

    if (_settings.forceSync) unawaited(backend.sync());

    return AnkiCardOutcome(
      AnkiAddResult.success,
      lookup: lookup,
      context: effectiveContext,
      fields: finalFields,
      deckName: deck.name,
      noteTypeName: noteType.name,
    );
  }

  /// 只渲染不写卡，给设置页做预览。
  AnkiRenderedFields previewFields({
    required WordLookupResult lookup,
    AnkiMiningContext context = const AnkiMiningContext(),
    String? formatId,
    List<WordLookupGlossary> termGlossaries = const [],
  }) {
    final format = _resolveFormat(formatId);
    if (format == null) return const AnkiRenderedFields(fields: {});
    final noteType = availableNoteTypes.firstWhereOrNull((e) => e.id == format.selectedNoteTypeId);
    if (noteType == null) return const AnkiRenderedFields(fields: {});
    return AnkiFieldRenderer.renderFields(
      noteType: noteType,
      fieldMappings: format.fieldMappings,
      lookup: lookup,
      context: context.copyWithDefaultsFrom(lookup),
      selectedGlossaryFallback: _settings.selectedGlossaryFallback,
      termGlossaries: termGlossaries,
    );
  }

  /// 首字段是不是重复卡，UI 可以据此决定要不要提示「已存在」。
  Future<bool> isDuplicate({required String key, String? formatId}) async {
    final format = _resolveFormat(formatId);
    if (format == null) return false;
    final deck = availableDecks.firstWhereOrNull((e) => e.id == format.selectedDeckId);
    final noteType = availableNoteTypes.firstWhereOrNull((e) => e.id == format.selectedNoteTypeId);
    if (deck == null || noteType == null || key.isEmpty) return false;
    return backend.isDuplicate(
      deck: deck,
      noteType: noteType,
      key: key,
      duplicateScope: _settings.duplicateScope,
      checkDuplicatesAcrossAllModels: _settings.checkDuplicatesAcrossAllModels,
    );
  }

  AnkiCardFormat? _resolveFormat(String? formatId) {
    final formats = cardFormats;
    if (formats.isEmpty) return null;
    if (formatId == null || formatId.isEmpty) return formats.first;
    return formats.firstWhereOrNull((e) => e.id == formatId) ?? formats.first;
  }

  String _firstFieldValue(AnkiCardFormat format, AnkiNoteType noteType) {
    final first = noteType.fields.firstOrNull;
    if (first == null) return '';
    return format.fieldMappings[first] ?? '';
  }

  /// 把词条相关的媒体（例句截图、封面、音频片段、单词发音）插进 Anki。
  ///
  /// 返回**替换后的上下文与载荷**：路径换成 Anki 真正的引用
  /// （`[sound:x]` / `<img src="x">`），后续渲染模板时直接就是最终形态。
  Future<_AnkiMediaUploadResult> _uploadMedia(WordLookupResult lookup, AnkiMiningContext context) async {
    var resultLookup = lookup;
    var resultContext = context;

    Future<void> upload(
      String? path,
      String preferredName,
      String mimeType,
      void Function(String value) apply,
    ) async {
      if (path == null || path.isEmpty) return;
      if (!File(path).existsSync()) {
        logger.error('anki: media missing $path');
        return;
      }
      try {
        final value = await backend.addMediaFromPath(
          path,
          preferredName: '$preferredName${_extensionOf(path)}',
          mimeType: mimeType,
        );
        if (value == null || value.isEmpty) return;
        apply(value);
      } catch (e, st) {
        logger.error('anki: add media failed $path', e: e, st: st);
      }
    }

    final base = _safeBaseName(lookup.expression);
    final title = _safeBaseName(context.documentTitle.isEmpty ? lookup.expression : context.documentTitle);

    await upload(context.audioClipPath, '${base}_clip', 'audio/mpeg',
        (v) => resultContext = resultContext.copyWith(audioClipPath: v));
    await upload(lookup.wordAudioPath, '${base}_word', 'audio/mpeg',
        (v) => resultLookup = resultLookup.copyWith(wordAudioPath: v));
    await upload(context.sentenceImagePath, '${base}_sentence', 'image/png',
        (v) => resultContext = resultContext.copyWith(sentenceImagePath: v));
    await upload(context.coverPath, title, 'image/jpeg',
        (v) => resultContext = resultContext.copyWith(coverPath: v));

    return _AnkiMediaUploadResult(resultLookup, resultContext);
  }

  static String _safeBaseName(String input) {
    final cleaned = input.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_').trim();
    return cleaned.isEmpty ? 'namida' : cleaned;
  }

  static String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot < path.lastIndexOf('/')) return '';
    return path.substring(dot);
  }
}

/// 上一次查的词。
///
/// 点词弹窗写入，「打开卡片浏览器」用它定位。只服务 UI 跳转，不参与任何写入逻辑，
/// 所以放在 Controller 旁边而不是某个 Widget 里。
class AnkiLastLookup {
  const AnkiLastLookup._();

  static final term = ''.obs;

  static void mark(String expression) => term.value = expression;
}

/// 制卡结果 + 细节。
class AnkiCardOutcome {
  final AnkiAddResult result;
  final String? message;
  final WordLookupResult? lookup;
  final AnkiMiningContext? context;

  /// 实际写进 Anki 的字段。
  final Map<String, String> fields;

  final String? deckName;
  final String? noteTypeName;

  const AnkiCardOutcome(
    this.result, {
    this.message,
    this.lookup,
    this.context,
    this.fields = const {},
    this.deckName,
    this.noteTypeName,
  });

  bool get isSuccess => result == AnkiAddResult.success;
}

extension AnkiMiningContextX on AnkiMiningContext {
  /// 上下文为空的部分用查词结果兜底。
  AnkiMiningContext copyWithDefaultsFrom(WordLookupResult lookup) {
    return AnkiMiningContext(
      sentence: sentence.isNotEmpty ? sentence : lookup.sentence,
      sentenceOffset: sentenceOffset ?? lookup.sentenceOffset,
      documentTitle: documentTitle,
      coverPath: coverPath,
      audioClipPath: audioClipPath ?? lookup.audioClipPath,
      sentenceImagePath: sentenceImagePath ?? lookup.sentenceImagePath,
      sourceAudioPath: sourceAudioPath,
      audioClipStartMS: audioClipStartMS,
    );
  }
}

class _AnkiMediaUploadResult {
  final WordLookupResult lookup;
  final AnkiMiningContext context;

  const _AnkiMediaUploadResult(this.lookup, this.context);
}
