import 'package:namida/controller/ai_subtitle/translators/ai_translator.dart';
import 'package:namida/controller/ai_subtitle/translators/ai_translator_engines.dart';
import 'package:namida/controller/ai_subtitle/translators/ai_translator_http.dart';

const qqApi = 'https://transmart.qq.com/api/imt';

/// qqimt: the same endpoint as qqTranSmart, without the server side split.
class QqimtTranslator extends AiTranslatorEngine {
  @override
  AiTranslatorId get id => AiTranslatorId.qqimt;

  @override
  final AiTranslatorHttp http = AiTranslatorHttp();

  @override
  bool get supportsAutoDetect => false;

  @override
  Future<String> translate(String text, {required String source, required String target}) async {
    final response = await http.postJson(
      qqApi,
      json: {
        'header': {
          'fn': 'auto_translation',
          'session': '',
          'client_key': 'browser-chrome-124.0.0-Windows_10-${aiPseudoUuid()}-${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
          'user': '',
        },
        'type': 'plain',
        'model_category': 'normal',
        'text_domain': 'general',
        'source': {
          'lang': source == 'auto' ? 'auto' : source,
          // -- the client pads the sentence list with empty strings on both ends
          'text_list': ['', text, ''],
        },
        'target': {'lang': mapTarget(target)},
      },
      headers: {
        'Accept': 'application/json, text/plain, */*',
        'Origin': 'https://transmart.qq.com',
        'Referer': 'https://transmart.qq.com/zh-CN/index',
        'X-Requested-With': 'XMLHttpRequest',
      },
    ).ensureOk();

    final list = response.json?['auto_translation'];
    if (list is! List) throw const AiTranslatorException('qqimt: no translation');
    return list.map((e) => e?.toString() ?? '').join();
  }
}

/// qqTranSmart: the server splits the text into sentences first, then translates
/// the whole sentence list in one go.
class QqTranSmartTranslator extends AiTranslatorEngine {
  @override
  AiTranslatorId get id => AiTranslatorId.qqTranSmart;

  @override
  final AiTranslatorHttp http = AiTranslatorHttp();

  @override
  Set<String> get supportedTargets => const {'zh-TW'};

  @override
  bool get supportsAutoDetect => false;

  String? _clientKey;
  bool _initialized = false;

  @override
  Future<void> init() async {
    if (_initialized) return;
    await http.get('https://transmart.qq.com');
    _clientKey = 'browser-firefox-110.0.0-Windows 10-${aiPseudoUuid()}-${DateTime.now().millisecondsSinceEpoch}';
    _initialized = true;
  }

  /// Cuts [text] on the sentence boundaries the server reports.
  static List<String> splitSentences(Map<String, dynamic> data, String text) {
    final list = data['sentence_list'];
    if (list is! List || list.isEmpty) return [text];

    final bounds = <int>[];
    for (final item in list) {
      if (item is! Map) continue;
      final start = item['start'];
      final length = item['len'];
      if (start is int && length is int) {
        bounds.add(start);
        bounds.add(start + length);
      }
    }
    if (bounds.length < 2) return [text];

    final result = <String>[];
    for (var i = 0; i < bounds.length - 1; i++) {
      final start = bounds[i].clamp(0, text.length);
      final end = bounds[i + 1].clamp(0, text.length);
      if (end > start) result.add(text.substring(start, end));
    }
    return result.isEmpty ? [text] : result;
  }

  @override
  Future<String> translate(String text, {required String source, required String target}) async {
    await init();
    final key = _clientKey!;

    final analysis = await http.postJson(
      qqApi,
      json: {
        'header': {'fn': 'text_analysis', 'client_key': key},
        'type': 'plain',
        'text': text,
        'normalize': {'merge_broken_line': 'false'},
      },
    ).ensureOk();

    final sentences = splitSentences(analysis.json ?? const {}, text);

    final response = await http.postJson(
      qqApi,
      json: {
        'header': {'fn': 'auto_translation', 'client_key': key},
        'type': 'plain',
        'model_category': 'normal',
        'source': {
          'lang': source == 'auto' ? 'auto' : source,
          'text_list': ['', ...sentences, ''],
        },
        'target': {'lang': mapTarget(target)},
      },
      headers: {'Cookie': 'client_key=$key'},
    ).ensureOk();

    final list = response.json?['auto_translation'];
    if (list is! List) throw const AiTranslatorException('qqTranSmart: no translation');
    return list.map((e) => e?.toString() ?? '').join();
  }
}
