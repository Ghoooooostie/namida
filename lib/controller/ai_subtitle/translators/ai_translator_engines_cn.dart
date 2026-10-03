import 'dart:convert';

import 'package:namida/controller/ai_subtitle/translators/ai_translator.dart';
import 'package:namida/controller/ai_subtitle/translators/ai_translator_http.dart';

/// base64 with a swapped alphabet, 彩云 uses it to hide its payload
const _caiyunNormal = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789=.+-_/';
const _caiyunCipher = 'NOPQRSTUVWXYZABCDEFGHIJKLMnopqrstuvwxyzabcdefghijklm0123456789=.+-_/';

String _caiyunDecrypt(String cipherText) {
  final table = <String, String>{};
  for (var i = 0; i < _caiyunCipher.length; i++) {
    table[_caiyunCipher[i]] = _caiyunNormal[i];
  }
  final restored = cipherText.split('').map((c) => table[c] ?? c).join();
  return utf8.decode(base64.decode(restored));
}

/// 彩云: a fresh jwt per call, an OPTIONS preflight, and the answer comes back
/// through a swapped-alphabet base64.
class CaiyunTranslator extends AiTranslatorEngine {
  @override
  AiTranslatorId get id => AiTranslatorId.caiyun;

  @override
  final AiTranslatorHttp http = AiTranslatorHttp();

  @override
  Set<String> get supportedTargets => const {'zh-Hant'};

  static const _token = 'token:qgemv4jr1y38jyq6vhvi';
  static const _browserId = 'beba19f9d7f10c74c98334c9e8afcd34';

  Map<String, String> get _headers => {
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'app-name': 'xy',
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
        'device-id': '',
        'Origin': 'https://fanyi.caiyunapp.com',
        'Referer': 'https://fanyi.caiyunapp.com/',
        'os-type': 'web',
        'os-version': '',
        'x-authorization': _token,
      };

  Future<String> _fetchJwt() async {
    final body = {'browser_id': _browserId};
    await http.options('https://api.interpreter.caiyunai.com/v1/user/jwt/generate', json: body, headers: _headers);
    final response = await http
        .postJson('https://api.interpreter.caiyunai.com/v1/user/jwt/generate', json: body, headers: _headers)
        .ensureOk();
    final jwt = response.json?['jwt']?.toString();
    if (jwt == null || jwt.isEmpty) throw const AiTranslatorException('彩云: could not get a jwt');
    return jwt;
  }

  @override
  Future<String> translate(String text, {required String source, required String target}) async {
    final jwt = await _fetchJwt();
    final body = <String, dynamic>{
      'source': text,
      'trans_type': '${source == 'auto' ? 'auto' : source}2${mapTarget(target)}',
      'request_id': 'web_fanyi',
      'media': 'text',
      'os_type': 'web',
      'dict': true,
      'cached': true,
      'replaced': true,
      'detect': true,
      'browser_id': _browserId,
    };

    final headers = {..._headers, 't-authorization': jwt};
    await http.options('https://api.interpreter.caiyunai.com/v1/translator', json: body, headers: headers);
    final response =
        await http.postJson('https://api.interpreter.caiyunai.com/v1/translator', json: body, headers: headers).ensureOk();

    final encrypted = response.json?['target']?.toString();
    if (encrypted == null || encrypted.isEmpty) throw const AiTranslatorException('彩云: no translation');
    return _caiyunDecrypt(encrypted);
  }
}

/// 阿里: everything travels in the query string, the body stays empty, and the
/// csrf token comes from a dedicated endpoint.
class AliTranslator extends AiTranslatorEngine {
  @override
  AiTranslatorId get id => AiTranslatorId.ali;

  @override
  final AiTranslatorHttp http = AiTranslatorHttp();

  String? _csrf;

  @override
  Future<void> init() async {
    if (_csrf != null) return;
    await http.get('https://translate.alibaba.com', headers: const {'Accept': 'text/html'});
    final response = await http.get('https://translate.alibaba.com/api/translate/csrftoken').ensureOk();
    final token = response.json?['token']?.toString();
    if (token == null || token.isEmpty) throw const AiTranslatorException('阿里: could not get a csrf token');
    _csrf = token;
  }

  @override
  Future<String> translate(String text, {required String source, required String target}) async {
    await init();
    final response = await http.post(
      'https://translate.alibaba.com/api/translate/text',
      query: {
        'srcLang': source == 'auto' ? 'auto' : source,
        'tgtLang': mapTarget(target),
        'domain': 'general',
        'query': text,
        '_csrf': _csrf!,
      },
      headers: const {
        'Accept': 'text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8',
        'Referer': 'https://translate.alibaba.com',
      },
    ).ensureOk();

    final data = response.json?['data'];
    if (data is! Map) throw const AiTranslatorException('阿里: unexpected answer');
    return aiHtmlUnescape(data['translateText']?.toString() ?? '');
  }
}

/// TranslateCom: the form field is `translated_lang`, past tense, not `target_lang`.
class TranslateComTranslator extends AiTranslatorEngine {
  @override
  AiTranslatorId get id => AiTranslatorId.translateCom;

  @override
  final AiTranslatorHttp http = AiTranslatorHttp();

  @override
  Set<String> get supportedTargets => const {'zh-TW'};

  bool _initialized = false;

  @override
  Future<void> init() async {
    if (_initialized) return;
    await http.get('https://www.translate.com/machine-translation');
    _initialized = true;
  }

  @override
  Future<String> translate(String text, {required String source, required String target}) async {
    await init();

    var from = source;
    if (from == 'auto') {
      final detect = await http.post(
        'https://www.translate.com/translator/ajax_lang_auto_detect',
        form: {'text_to_translate': text},
      ).ensureOk();
      from = detect.json?['language']?.toString() ?? 'auto';
    }

    final response = await http.post(
      'https://www.translate.com/translator/translate_mt',
      form: {
        'text_to_translate': text,
        'source_lang': from,
        'translated_lang': mapTarget(target),
        'use_cache_only': 'false',
      },
    ).ensureOk();

    final translated = response.json?['translated_text'];
    if (translated == null) throw const AiTranslatorException('TranslateCom: no translation');
    return aiHtmlUnescape(translated.toString());
  }
}

/// yandex: the keyless browser endpoint, auto detect needs a probe first.
class YandexTranslator extends AiTranslatorEngine {
  @override
  AiTranslatorId get id => AiTranslatorId.yandex;

  @override
  final AiTranslatorHttp http = AiTranslatorHttp();

  @override
  Set<String> get supportedTargets => const {'zh-TW'};

  Future<String> _detect(String text) async {
    final response = await http.get(
      'https://translate.yandex.net/api/v1/tr.json/detect',
      query: {'srv': 'browser_video_translation', 'text': text},
    ).ensureOk();
    return response.json?['lang']?.toString() ?? 'en';
  }

  @override
  Future<String> translate(String text, {required String source, required String target}) async {
    final from = source == 'auto' ? await _detect(text) : source;
    final response = await http.post(
      'https://browser.translate.yandex.net/api/v1/tr.json/translate',
      query: {
        'lang': '$from-${mapTarget(target)}',
        'text': text,
        'srv': 'browser_video_translation',
      },
      form: {'maxRetryCount': '2', 'fetchAbortTimeout': '500'},
    ).ensureOk();

    final list = response.json?['text'];
    if (list is! List || list.isEmpty) throw const AiTranslatorException('yandex: no translation');
    return list.first.toString();
  }
}
