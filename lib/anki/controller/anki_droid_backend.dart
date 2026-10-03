import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:namida/anki/class/anki_models.dart';
import 'package:namida/anki/controller/anki_backend.dart';
import 'package:namida/controller/logs_controller.dart';

/// 原生返回的 id/name 对。
class _IdName {
  final int id;
  final String name;

  const _IdName(this.id, this.name);
}

/// AnkiDroid 收藏库访问权限的状态。
enum AnkiDroidPermission {
  /// 没装 AnkiDroid。
  unavailable,

  /// 已授权，可以读写收藏库。
  granted,

  /// 从没弹过对话框，点一下会弹系统申请框。
  notDetermined,

  /// 用户点过「拒绝」，系统不会再弹，只能去应用设置页手动开。
  denied,
}

/// 与 `AnkiDroidApi.kt` 通信的通道。
class AnkiDroidChannel {
  AnkiDroidChannel._internal();

  static final AnkiDroidChannel inst = AnkiDroidChannel._internal();

  static const _channel = MethodChannel('namida/anki');

  static bool _handlerInstalled = false;

  /// 原生在用户答复权限对话框后主动通知，用来立刻刷新 UI。
  static final _permissionResultCallbacks = <void Function(bool granted)>[];

  void addPermissionResultCallback(void Function(bool granted) callback) {
    _ensureHandler();
    _permissionResultCallbacks.add(callback);
  }

  void removePermissionResultCallback(void Function(bool granted) callback) {
    _permissionResultCallbacks.remove(callback);
  }

  static void _ensureHandler() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onPermissionResult') {
        final granted = call.arguments is Map ? call.arguments['granted'] == true : false;
        for (final callback in List.of(_permissionResultCallbacks)) {
          callback(granted);
        }
      }
      return null;
    });
  }

  Future<T?> _invoke<T>(String method, [Map<String, dynamic>? args]) async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw AnkiFetchException(_failureFrom(e.code), cause: e.message);
    } on MissingPluginException {
      return null;
    }
  }

  static AnkiFetchFailure _failureFrom(String code) => switch (code) {
        'UNAVAILABLE' => AnkiFetchFailure.apiUnavailable,
        'PERMISSION_DENIED' => AnkiFetchFailure.permissionDenied,
        'DECK_LIST' => AnkiFetchFailure.deckListUnavailable,
        'MODEL_LIST' => AnkiFetchFailure.modelListUnavailable,
        'MODEL_FIELDS' => AnkiFetchFailure.modelFieldsUnavailable,
        _ => AnkiFetchFailure.providerFailure,
      };

  /// AnkiDroid 是否已安装。
  Future<bool> isInstalled() async {
    return await _invoke<bool>('isAvailable') ?? false;
  }

  Future<List<AnkiDeck>> fetchDecks() async {
    final raw = await _invoke<List<dynamic>>('deckList');
    if (raw == null) throw AnkiFetchException(AnkiFetchFailure.apiUnavailable);
    return raw
        .map(_idNameOf)
        .whereType<_IdName>()
        .map((e) => AnkiDeck(id: e.id, name: e.name))
        .where((e) => e.name.isNotEmpty)
        .toList()
      ..sort(compareAnkiDecks);
  }

  /// 原生侧返回的可能是 `{"id":..,"name":..}`，也可能是 `Map<Long,String>` 直接序列化后的
  /// `{0: id, 1: name}`。两种都认，免得因为形状对不上而静默变成空列表。
  static _IdName? _idNameOf(dynamic entry) {
    if (entry is! Map) return null;
    final id = entry['id'];
    final name = entry['name'];
    if (id is num && name is String) return _IdName(id.toInt(), name);

    // -- Map<Long, String> 的键是 Long，到 Dart 里可能落在 String key 上。
    final values = entry.values.toList();
    if (values.length == 2) {
      final first = values[0];
      final second = values[1];
      if (first is num && second is String) return _IdName(first.toInt(), second);
    }
    return null;
  }

  Future<List<AnkiNoteType>> fetchNoteTypes() async {
    final raw = await _invoke<List<dynamic>>('modelList');
    if (raw == null) throw AnkiFetchException(AnkiFetchFailure.apiUnavailable);

    final noteTypes = <AnkiNoteType>[];
    final unreadable = <String>[];
    for (final entry in raw) {
      final parsed = _idNameOf(entry);
      if (parsed == null) continue;
      final id = parsed.id;
      final name = parsed.name;
      List<String> fields;
      try {
        fields = await fetchFields(id) ?? const [];
      } on AnkiFetchException catch (e) {
        if (e.failure != AnkiFetchFailure.modelFieldsUnavailable) rethrow;
        unreadable.add(name);
        continue;
      }
      if (fields.isEmpty) {
        unreadable.add(name);
        continue;
      }
      noteTypes.add(AnkiNoteType(id: id, name: name, fields: fields));
    }

    if (unreadable.isNotEmpty) {
      throw AnkiFetchException(
        AnkiFetchFailure.modelFieldsUnavailable,
        cause: unreadable.join(', '),
      );
    }
    return noteTypes;
  }

  Future<List<String>?> fetchFields(int modelId) async {
    final raw = await _invoke<List<dynamic>>('fieldList', {'modelId': modelId});
    return raw?.map((e) => '$e').where((e) => e.isNotEmpty).toList();
  }

  Future<bool> isDuplicate({
    required int noteTypeId,
    required int keyChecksum,
    required List<int> scopeDeckIds,
    required bool checkAllModels,
  }) async {
    final res = await _invoke<bool>('findDuplicates', {
      'modelId': noteTypeId,
      'checksum': keyChecksum,
      'deckIds': scopeDeckIds,
      'checkAllModels': checkAllModels,
    });
    return res ?? false;
  }

  Future<bool> addNote({
    required int noteTypeId,
    required int deckId,
    required List<String> fields,
    required Set<String> tags,
  }) async {
    final res = await _invoke<bool>('addNote', {
      'modelId': noteTypeId,
      'deckId': deckId,
      'fields': fields,
      'tags': tags.toList(),
    });
    return res ?? false;
  }

  /// 首字段 `csum`。原生侧算，Kotlin 才有 NFC 规范化。
  Future<int?> firstFieldChecksum(String data) async {
    return await _invoke<int>('firstFieldChecksum', {'data': data});
  }

  Future<String?> addMediaFromPath(String path, {required String preferredName, required String mimeType}) async {
    return await _invoke<String>('addMedia', {
      'path': path,
      'name': preferredName,
      'mimeType': mimeType,
    });
  }

  Future<bool> sync() async {
    return await _invoke<bool>('sync') ?? false;
  }

  Future<bool> openNotes(String query) async {
    if (query.isEmpty) return false;
    return await _invoke<bool>('openNotes', {'query': query}) ?? false;
  }

  /// 打开 AnkiDroid 应用本体。
  Future<bool> openAnkiDroid() async {
    return await _invoke<bool>('openAnkiDroid') ?? false;
  }

  /// 申请 AnkiDroid 的收藏库访问权限。
  ///
  /// `com.ichi2.anki.permission.READ_WRITE_DATABASE` 在 AnkiDroid 里是 `dangerous` 级别，
  /// **必须运行时申请**，manifest 里声明了也不够。返回 true 表示系统弹窗已弹出（或本来就有）。
  Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return false;
    return await _invoke<bool>('requestPermission') ?? false;
  }

  /// 跳到系统应用信息页。
  ///
  /// 用户点过「拒绝」之后系统不会再弹窗，只能到这里手动开。
  Future<bool> openAppSettings() async {
    if (!Platform.isAndroid) return false;
    return await _invoke<bool>('openAppSettings') ?? false;
  }

  /// 授权状态：已授权 / 已拒绝 / 还没问过。
  Future<String?> permissionStatus() async => await _invoke<String>('permissionStatus');
}

/// AnkiDroid 后端。只在 Android 生效，其它平台所有方法返回空/false。
class AnkiDroidBackend extends AnkiBackend {
  final AnkiDroidChannel channel;

  AnkiDroidBackend({AnkiDroidChannel? channel}) : channel = channel ?? AnkiDroidChannel.inst;

  @override
  AnkiBackendKind get kind => AnkiBackendKind.ankiDroid;

  @override
  Future<bool> isAvailable() async {
    if (!Platform.isAndroid) return false;
    // -- 先看权限：持有 AnkiDroid 的守卫权限就说明它装着，
    //    比「查包可见性」可靠（Android 11+ 会过滤掉看不见的包）。
    if (await channel.permissionStatus() == 'granted') return true;
    // -- 没授权时再单独判一次装没装，作为 UI 的提示依据。
    return await channel.isInstalled();
  }

  @override
  Future<List<AnkiDeck>> fetchDecks() => channel.fetchDecks();

  @override
  Future<List<AnkiNoteType>> fetchNoteTypes() => channel.fetchNoteTypes();

  @override
  Future<bool> isDuplicate({
    required AnkiDeck deck,
    required AnkiNoteType noteType,
    required String key,
    required AnkiDuplicateScope duplicateScope,
    required bool checkDuplicatesAcrossAllModels,
  }) async {
    if (key.trim().isEmpty) return false;
    if (!Platform.isAndroid) return false;

    final checksum = await channel.firstFieldChecksum(key);
    if (checksum == null || checksum == 0) return false;

    final scopeDeckIds = duplicateScope == AnkiDuplicateScope.collection
        ? const <int>[]
        : ankiDuplicateScopeDeckIds(await fetchDecks(), deck, duplicateScope).toList();

    try {
      return await channel.isDuplicate(
        noteTypeId: noteType.id,
        keyChecksum: checksum,
        scopeDeckIds: scopeDeckIds,
        checkAllModels: checkDuplicatesAcrossAllModels,
      );
    } on AnkiFetchException catch (e) {
      logger.error('anki: AnkiDroid duplicate check failed', e: e);
      return false;
    }
  }

  @override
  Future<bool> addNote({
    required AnkiDeck deck,
    required AnkiNoteType noteType,
    required Map<String, String> fieldsByName,
    required Set<String> tags,
    required bool allowDupes,
    required AnkiDuplicateScope duplicateScope,
    required bool checkDuplicatesAcrossAllModels,
  }) async {
    if (!Platform.isAndroid) return false;

    final firstField = noteType.fields.firstOrNull;
    if (firstField == null) return false;
    final duplicateKey = fieldsByName[firstField] ?? '';

    if (!allowDupes && duplicateKey.isNotEmpty) {
      final isDupe = await isDuplicate(
        deck: deck,
        noteType: noteType,
        key: duplicateKey,
        duplicateScope: duplicateScope,
        checkDuplicatesAcrossAllModels: checkDuplicatesAcrossAllModels,
      );
      if (isDupe) return false;
    }

    final fields = noteType.fields.map((e) => fieldsByName[e] ?? '').toList();
    try {
      return await channel.addNote(
        noteTypeId: noteType.id,
        deckId: deck.id,
        fields: fields,
        tags: tags,
      );
    } on AnkiFetchException catch (e) {
      logger.error('anki: AnkiDroid addNote failed', e: e);
      return false;
    }
  }

  @override
  Future<String?> addMediaFromPath(String path, {required String preferredName, required String mimeType}) {
    if (!Platform.isAndroid) return Future.value(null);
    return channel.addMediaFromPath(path, preferredName: preferredName, mimeType: mimeType);
  }

  @override
  Future<bool> sync() {
    if (!Platform.isAndroid) return Future.value(false);
    return channel.sync();
  }

  @override
  Future<bool> openNotes({
    required AnkiDeck deck,
    required AnkiNoteType noteType,
    required String key,
    required AnkiDuplicateScope duplicateScope,
    required bool checkDuplicatesAcrossAllModels,
  }) {
    if (!Platform.isAndroid) return Future.value(false);
    final query = ankiNoteBrowserQuery(
      deck: deck,
      noteType: noteType,
      key: key,
      duplicateScope: duplicateScope,
      checkDuplicatesAcrossAllModels: checkDuplicatesAcrossAllModels,
    );
    return channel.openNotes(query);
  }
}

/// 调试用：Android 侧模拟器里没有 AnkiDroid 时，UI 需要知道原因。
String describeAnkiFailure(Object error) {
  if (error is AnkiFetchException) return error.userMessage;
  if (error is PlatformException) return 'Anki 调用失败：${error.message}';
  if (kDebugMode) return error.toString();
  return 'Anki 调用失败。';
}
