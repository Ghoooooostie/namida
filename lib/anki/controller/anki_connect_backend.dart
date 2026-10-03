import 'dart:async';
import 'dart:convert';
import 'dart:io';

// ignore: depend_on_referenced_packages
import 'package:collection/collection.dart';
import 'package:rhttp/rhttp.dart';

import 'package:namida/anki/class/anki_models.dart';
import 'package:namida/anki/controller/anki_backend.dart';
import 'package:namida/controller/logs_controller.dart';

/// AnkiConnect 后端（v6）。
///
/// 桌面版 Anki 默认在 8765 端口监听，手机需要跟电脑同局域网并填电脑 IP。
class AnkiConnectBackend extends AnkiBackend {
  final String endpoint;
  final String apiKey;
  final int timeoutMS;

  /// 便于测试替换成假的传输层。
  final Future<String> Function(String url, Map<String, dynamic> body) transport;

  AnkiConnectBackend({
    String? endpoint,
    this.apiKey = '',
    this.timeoutMS = 10000,
    Future<String> Function(String url, Map<String, dynamic> body)? transport,
  })  : endpoint = _normalizeEndpoint(endpoint ?? kDefaultAnkiConnectUrl),
        transport = transport ?? ((url, body) => _httpPost(url, body, timeoutMS));

  @override
  AnkiBackendKind get kind => AnkiBackendKind.ankiConnect;

  @override
  Future<bool> isAvailable() async {
    try {
      await _request('version');
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<AnkiDeck>> fetchDecks() async {
    return _wrapFetch(() async {
      final names = (await _requestArray('deckNames')).map(_asString).where((e) => e.isNotEmpty).toList();
      return names.map((name) => AnkiDeck(id: ankiStableId('deck', name), name: name)).toList()..sort(compareAnkiDecks);
    });
  }

  @override
  Future<List<AnkiNoteType>> fetchNoteTypes() async {
    return _wrapFetch(() async {
      final names = (await _requestArray('modelNames')).map(_asString).where((e) => e.isNotEmpty).toList();
      final noteTypes = <AnkiNoteType>[];
      for (final name in names) {
        final fields =
            (await _requestArray('modelFieldNames', {'modelName': name})).map(_asString).where((e) => e.isNotEmpty).toList();
        if (fields.isEmpty) {
          throw AnkiFetchException(AnkiFetchFailure.modelFieldsUnavailable, cause: name);
        }
        noteTypes.add(AnkiNoteType(id: ankiStableId('model', name), name: name, fields: fields));
      }
      return noteTypes;
    });
  }


  @override
  Future<bool> isDuplicate({
    required AnkiDeck deck,
    required AnkiNoteType noteType,
    required String key,
    required AnkiDuplicateScope duplicateScope,
    required bool checkDuplicatesAcrossAllModels,
  }) async {
    if (key.trim().isEmpty) return false;
    final firstField = noteType.fields.firstOrNull;
    if (firstField == null) return false;

    try {
      final note = _buildNote(
        deck: deck,
        noteType: noteType,
        fieldsByName: {firstField: key},
        options: _duplicateOptions(
          deck: deck,
          allowDupes: false,
          duplicateScope: duplicateScope,
          checkDuplicatesAcrossAllModels: checkDuplicatesAcrossAllModels,
        ),
      );
      final results = await _requestArray('canAddNotesWithErrorDetail', {
        'notes': [note],
      });
      if (results.isEmpty) return false;
      final first = results.first;
      if (first is Map) {
        return !(first['canAdd'] as bool? ?? true);
      }
      // -- 老版本 AnkiConnect 只返回 bool 数组。
      return first == false;
    } catch (e) {
      logger.error('anki: isDuplicate failed', e: e);
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
    try {
      var note = _buildNote(
        deck: deck,
        noteType: noteType,
        fieldsByName: fieldsByName,
        options: _duplicateOptions(
          deck: deck,
          allowDupes: allowDupes,
          duplicateScope: duplicateScope,
          checkDuplicatesAcrossAllModels: checkDuplicatesAcrossAllModels,
        ),
      );
      if (tags.isNotEmpty) {
        note = {...note, 'tags': tags.toList()};
      }
      await _request('addNote', {'note': note});
      return true;
    } catch (e) {
      logger.error('anki: addNote failed', e: e);
      return false;
    }
  }

  @override
  Future<String?> addMediaFromPath(String path, {required String preferredName, required String mimeType}) async {
    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      final filename = _mediaFilename(preferredName);
      await _request('storeMediaFile', {
        'filename': filename,
        'data': base64Encode(file.readAsBytesSync()),
      });
      return _mediaFieldValue(filename, mimeType);
    } catch (e) {
      logger.error('anki: storeMediaFile failed: $path', e: e);
      return null;
    }
  }

  @override
  Future<bool> sync() async {
    try {
      await _request('sync');
      return true;
    } catch (e) {
      logger.error('anki: sync failed', e: e);
      return false;
    }
  }

  @override
  Future<bool> openNotes({
    required AnkiDeck deck,
    required AnkiNoteType noteType,
    required String key,
    required AnkiDuplicateScope duplicateScope,
    required bool checkDuplicatesAcrossAllModels,
  }) async {
    final query = ankiNoteBrowserQuery(
      deck: deck,
      noteType: noteType,
      key: key,
      duplicateScope: duplicateScope,
      checkDuplicatesAcrossAllModels: checkDuplicatesAcrossAllModels,
    );
    if (query.isEmpty) return false;
    try {
      await _request('guiBrowse', {'query': query});
      return true;
    } catch (e) {
      logger.error('anki: guiBrowse failed', e: e);
      return false;
    }
  }

  // ------------------------------------------------------------------
  // internals
  // ------------------------------------------------------------------

  Map<String, dynamic> _buildNote({
    required AnkiDeck deck,
    required AnkiNoteType noteType,
    required Map<String, String> fieldsByName,
    required Map<String, dynamic> options,
  }) {
    // -- 只写卡片类型真实拥有的字段，多余的会被 AnkiConnect 静默忽略，显式过滤更可控。
    final fields = <String, String>{};
    for (final field in noteType.fields) {
      final value = fieldsByName[field];
      if (value != null) fields[field] = value;
    }
    return {
      'deckName': deck.name,
      'modelName': noteType.name,
      'fields': fields,
      'options': options,
    };
  }

  Map<String, dynamic> _duplicateOptions({
    required AnkiDeck deck,
    required bool allowDupes,
    required AnkiDuplicateScope duplicateScope,
    required bool checkDuplicatesAcrossAllModels,
  }) {
    // -- deckRoot 时限定到根牌组并递归子牌组。
    final rootScope = duplicateScope == AnkiDuplicateScope.deckRoot
        ? <String, dynamic>{'deckName': deck.rootName, 'checkChildren': true}
        : null;

    final scopeOptions = switch ((rootScope, checkDuplicatesAcrossAllModels)) {
      (final root?, true) => {...root, 'checkAllModels': true},
      (final root?, false) => root,
      (null, true) => <String, dynamic>{'checkAllModels': true},
      (null, false) => null,
    };

    return {
      'allowDuplicate': allowDupes,
      'duplicateScope': duplicateScope == AnkiDuplicateScope.collection ? 'collection' : 'deck',
      'duplicateScopeOptions': ?scopeOptions,
    };
  }

  Future<List<dynamic>> _requestArray(String action, [Map<String, dynamic>? params]) async {
    final result = await _request(action, params);
    if (result is List) return result;
    return const [];
  }

  Future<dynamic> _request(String action, [Map<String, dynamic>? params]) async {
    final body = <String, dynamic>{
      'action': action,
      'version': 6,
      'params': ?params,
      if (apiKey.isNotEmpty) 'key': apiKey,
    };
    final raw = await transport(endpoint, body);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw AnkiFetchException(AnkiFetchFailure.providerFailure, cause: 'unexpected response');
    }
    final error = decoded['error'];
    if (error != null) {
      throw AnkiFetchException(AnkiFetchFailure.providerFailure, cause: '$error');
    }
    return decoded['result'];
  }

  static String _asString(dynamic value) => value is String ? value : '';

  Future<T> _wrapFetch<T>(Future<T> Function() block) async {
    try {
      return await block();
    } on AnkiFetchException {
      rethrow;
    } catch (e) {
      throw AnkiFetchException(AnkiFetchFailure.providerFailure, cause: '$e');
    }
  }

  static String _mediaFilename(String preferredName) {
    var name = preferredName.replaceAll('\\', '/');
    name = name.substring(name.lastIndexOf('/') + 1);
    return name.isEmpty ? 'namida_media' : name;
  }

  static String _mediaFieldValue(String filename, String mimeType) {
    if (mimeType.startsWith('audio/')) return '[sound:$filename]';
    if (mimeType.startsWith('image/')) return '<img src="$filename">';
    return filename;
  }

  /// 缺 scheme 补 http，末尾多余的斜杠去掉。
  static String _normalizeEndpoint(String raw) {
    var url = raw.trim();
    if (url.isEmpty) url = kDefaultAnkiConnectUrl;
    if (!url.startsWith('http://') && !url.startsWith('https://')) url = 'http://$url';
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  /// 一次 POST。[url] 一定是用户填的 AnkiConnect 地址，超时用 [CancelToken] 实现。
  static Future<String> _httpPost(String url, Map<String, dynamic> body, int timeoutMS) async {
    final client = await RhttpClient.create();
    final cancelToken = CancelToken();
    final timer = Timer(Duration(milliseconds: timeoutMS), cancelToken.cancel);
    try {
      final response = await client.post(url, body: HttpBody.json(body), cancelToken: cancelToken);
      return response.body;
    } finally {
      timer.cancel();
      client.dispose(cancelRunningRequests: true);
    }
  }
}
