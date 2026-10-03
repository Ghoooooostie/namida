import 'dart:convert';

import 'package:crypto/crypto.dart';
// ignore: depend_on_referenced_packages
import 'package:collection/collection.dart';

import 'package:namida/anki/class/anki_models.dart';

/// 一次拉取的结果。
class AnkiBackendSnapshot {
  final List<AnkiDeck> decks;
  final List<AnkiNoteType> noteTypes;

  const AnkiBackendSnapshot({required this.decks, required this.noteTypes});
}

/// Anki 后端契约。
///
/// 两个实现：
/// - `AnkiDroidBackend`（Android，走 ContentProvider）
/// - `AnkiConnectBackend`（HTTP，桌面 + 手机都能用）
abstract class AnkiBackend {
  AnkiBackendKind get kind;

  /// 收藏库可读（AnkiDroid 已安装且授权 / AnkiConnect 能连通）。
  Future<bool> isAvailable();

  Future<List<AnkiDeck>> fetchDecks();

  Future<List<AnkiNoteType>> fetchNoteTypes();

  /// 拉牌组 + 卡片类型。任一环节失败抛 [AnkiFetchException]。
  Future<AnkiBackendSnapshot> refresh() async {
    final decks = await fetchDecks();
    final noteTypes = await fetchNoteTypes();
    return AnkiBackendSnapshot(decks: decks, noteTypes: noteTypes);
  }

  /// 首字段是否为重复。`key` 一般是词条。
  Future<bool> isDuplicate({
    required AnkiDeck deck,
    required AnkiNoteType noteType,
    required String key,
    required AnkiDuplicateScope duplicateScope,
    required bool checkDuplicatesAcrossAllModels,
  });

  /// 写卡。返回 false 表示被当成重复卡拒了。
  Future<bool> addNote({
    required AnkiDeck deck,
    required AnkiNoteType noteType,
    required Map<String, String> fieldsByName,
    required Set<String> tags,
    required bool allowDupes,
    required AnkiDuplicateScope duplicateScope,
    required bool checkDuplicatesAcrossAllModels,
  });

  /// 从本地文件插入媒体，返回 Anki 字段里该填的片段：
  /// 音频是 `[sound:name]`，图片是 `<img src="name">`。不支持时返回 null。
  Future<String?> addMediaFromPath(String path, {required String preferredName, required String mimeType}) async => null;

  /// 触发同步。AnkiDroid 只能拉起它的同步界面，返回 true 表示已请求。
  Future<bool> sync() async => false;

  /// 打开 Anki 卡片浏览器并带上查询串。
  Future<bool> openNotes({
    required AnkiDeck deck,
    required AnkiNoteType noteType,
    required String key,
    required AnkiDuplicateScope duplicateScope,
    required bool checkDuplicatesAcrossAllModels,
  }) async =>
      false;
}

/// 拉取失败原因。
enum AnkiFetchFailure {
  /// AnkiDroid 没装 / AnkiConnect 连不上。
  apiUnavailable,

  /// AnkiDroid 数据库权限被拒。
  permissionDenied,

  /// 牌组列表读不出来。
  deckListUnavailable,

  /// 卡片类型列表读不出来。
  modelListUnavailable,

  /// 某个卡片类型的字段读不出来。
  modelFieldsUnavailable,

  /// 后端其它异常。
  providerFailure,
}

class AnkiFetchException implements Exception {
  final AnkiFetchFailure failure;
  final String? cause;

  AnkiFetchException(this.failure, {this.cause});

  String get userMessage => switch (failure) {
    AnkiFetchFailure.apiUnavailable => '未检测到 Anki。请安装 AnkiDroid，或启动桌面版 Anki 并开启 AnkiConnect。',
    AnkiFetchFailure.permissionDenied => '读取 AnkiDroid 数据库被拒绝，请在系统设置里授权。',
    AnkiFetchFailure.deckListUnavailable => '读取 AnkiDroid 牌组失败，请先打开一次 AnkiDroid。',
    AnkiFetchFailure.modelListUnavailable => '读取 AnkiDroid 卡片类型失败，请先打开一次 AnkiDroid。',
    AnkiFetchFailure.modelFieldsUnavailable => '读取 AnkiDroid 卡片类型字段失败。',
    AnkiFetchFailure.providerFailure => 'Anki 没有响应，请确认它已启动。',
  };

  @override
  String toString() => 'AnkiFetchException(${failure.name}${cause == null ? '' : ': $cause'})';
}

/// 牌组按名字排序，大小写不敏感优先。
int compareAnkiDecks(AnkiDeck a, AnkiDeck b) {
  final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
  if (byName != 0) return byName;
  final byExact = a.name.compareTo(b.name);
  if (byExact != 0) return byExact;
  return a.id.compareTo(b.id);
}

/// AnkiConnect 没有稳定的数字 id，用 `namespace:value` 的 SHA-256 前 8 字节伪造一个。
/// 同一个名字永远得到同一个 id，缓存和字段映射才能稳定。
int ankiStableId(String namespace, String value) {
  final digest = sha256.convert(utf8.encode('$namespace:$value')).bytes;
  var id = 0;
  for (var i = 0; i < 8; i++) {
    id = (id << 8) | digest[i];
  }
  return id & 0x7FFFFFFF;
}

/// Anki 首字段校验和 `csum`。
///
/// AnkiDroid 查重只能走 ContentProvider 的 `csum` 列，所以必须算出与 Anki 一致的值：
/// 字段先 NFC 规范化 -> 去 HTML 媒体 -> 去标签 -> 解实体 -> SHA1 -> 取前 8 个十六进制字符。
///
/// Dart 没有内置 NFC 规范化，因此**这段只在原生侧算**（Kotlin 的 `java.text.Normalizer`），
/// 见 `AnkiDroidBackend.isDuplicate`。这里保留实现仅供桌面侧自检。
int ankiFirstFieldChecksum(String data) {
  final stripped = stripHtmlMedia(data);
  final digest = sha1.convert(utf8.encode(stripped)).bytes;
  final hex = digest.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  return int.parse(hex.substring(0, 8), radix: 16);
}

/// 查重范围对应的牌组 id 集合。`collection` 返回空集表示不限定牌组。
Set<int> ankiDuplicateScopeDeckIds(List<AnkiDeck> decks, AnkiDeck selected, AnkiDuplicateScope scope) {
  switch (scope) {
    case AnkiDuplicateScope.collection:
      return const {};
    case AnkiDuplicateScope.deck:
      return {selected.id};
    case AnkiDuplicateScope.deckRoot:
      final root = selected.rootName;
      return decks.where((e) => e.name == root || e.name.startsWith('$root::')).map((e) => e.id).toSet();
  }
}

/// Anki 卡片浏览器搜索串。
String ankiNoteBrowserQuery({
  required AnkiDeck deck,
  required AnkiNoteType noteType,
  required String key,
  required AnkiDuplicateScope duplicateScope,
  required bool checkDuplicatesAcrossAllModels,
}) {
  final firstField = noteType.fields.firstOrNull;
  if (firstField == null) return '';
  final escapedKey = key.replaceAll('"', '');
  if (escapedKey.trim().isEmpty) return '';

  final parts = <String>['"$firstField:$escapedKey"'];
  if (!checkDuplicatesAcrossAllModels) parts.add('"note:${noteType.name}"');
  switch (duplicateScope) {
    case AnkiDuplicateScope.collection:
      break;
    case AnkiDuplicateScope.deck:
      parts.add('"deck:${deck.name}"');
    case AnkiDuplicateScope.deckRoot:
      parts.add('"deck:${deck.rootName}"');
  }
  return parts.join(' ');
}

final RegExp _styleRegex = RegExp(r'<style.*?>[\s\S]*?</style>', caseSensitive: false);
final RegExp _scriptRegex = RegExp(r'<script.*?>[\s\S]*?</script>', caseSensitive: false);
final RegExp _tagRegex = RegExp(r'<.*?>');
final RegExp _imgRegex = RegExp(r'''<img src=["']?([^"'>\s]+)["']?\s*/?>''');
final RegExp _entityRegex = RegExp(r'&#?\w+;');

String stripHtmlMedia(String input) {
  var out = input.replaceAllMapped(_imgRegex, (m) => ' ${m.group(1)} ');
  out = out.replaceAll(_styleRegex, '').replaceAll(_scriptRegex, '').replaceAll(_tagRegex, '');
  return _decodeHtmlEntities(out);
}

String _decodeHtmlEntities(String input) {
  final withoutNbsp = input.replaceAll('&nbsp;', ' ');
  return withoutNbsp.replaceAllMapped(_entityRegex, (m) {
    return switch (m.group(0)) {
      '&amp;' => '&',
      '&lt;' => '<',
      '&gt;' => '>',
      '&quot;' => '"',
      '&#39;' || '&apos;' => "'",
      _ => _decodeNumericHtmlEntity(m.group(0)!) ?? m.group(0)!,
    };
  });
}

String? _decodeNumericHtmlEntity(String entity) {
  var value = entity;
  if (value.startsWith('&#')) value = value.substring(2);
  if (value.endsWith(';')) value = value.substring(0, value.length - 1);
  if (value.isEmpty) return null;

  int? codePoint;
  if (value.startsWith('x') || value.startsWith('X')) {
    codePoint = int.tryParse(value.substring(1), radix: 16);
  } else {
    codePoint = int.tryParse(value);
  }
  if (codePoint == null || codePoint < 0 || codePoint > 0x10FFFF) return null;
  return String.fromCharCode(codePoint);
}
