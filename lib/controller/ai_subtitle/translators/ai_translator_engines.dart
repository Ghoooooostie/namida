import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:namida/controller/ai_subtitle/translators/ai_translator.dart';
import 'package:namida/controller/ai_subtitle/translators/ai_translator_http.dart';

String aiMd5Hex(String input) => md5.convert(utf8.encode(input)).toString();

String aiHmacBase64(String key, String message, Hash algorithm) =>
    base64.encode(Hmac(algorithm, utf8.encode(key)).convert(utf8.encode(message)).bytes);

/// A uuid v4 shaped id built from the clock. The signature schemes only need
/// something that looks unique, not a real random source.
String aiPseudoUuid() {
  final now = DateTime.now();
  String part(int value, int width) => value.toRadixString(16).padLeft(width, '0');
  final micro = now.microsecondsSinceEpoch;
  return '${part(micro, 8)}-${part(now.microsecond * 3571, 4)}-4${part(now.second * 97, 3)}-'
      'a${part(now.millisecond * 13, 3)}-${part(micro * 7, 12)}';
}

/// 微软: the endpoint the Android translator app uses, identified by an HMAC over
/// the url. Nothing to configure, the private key ships inside the app.
class MicrosoftTranslator extends AiTranslatorEngine {
  @override
  AiTranslatorId get id => AiTranslatorId.microsoft;

  @override
  final AiTranslatorHttp http = AiTranslatorHttp();

  @override
  Set<String> get supportedTargets => const {'zh-Hans', 'zh-Hant'};

  /// the key the official app embeds, as **raw bytes**: the signature treats
  /// them as an opaque blob, so each value above 0x7f must stay a single byte
  /// instead of being expanded to its 2 byte utf-8 encoding.
  static const List<int> _privateKey = [
    0xa2, 0x29, 0x3a, 0x3d, 0xd0, 0xdd, 0x32, 0x73, 0x97, 0x7a, 0x64, 0xdb, 0xc2, 0xf3, 0x27, 0xf5, //
    0xd7, 0xbf, 0x87, 0xd9, 0x45, 0x9d, 0xf0, 0x5a, 0x09, 0x66, 0xc6, 0x30, 0xc6, 0x6a, 0xaa, 0x84,
    0x9a, 0x41, 0xaa, 0x94, 0x3a, 0xa8, 0xd5, 0x1a, 0x6e, 0x4d, 0xaa, 0xc9, 0xa3, 0x70, 0x12, 0x35,
    0xc7, 0xeb, 0x12, 0xf6, 0xe8, 0x23, 0x07, 0x9e, 0x47, 0x10, 0x95, 0x91, 0x88, 0x55, 0xd8, 0x17,
  ];

  String _signature(String escapedUrl, String dateTime, String guid) {
    final message = 'MSTranslatorAndroidApp$escapedUrl$dateTime$guid'.toLowerCase();
    final mac = Hmac(sha256, _privateKey).convert(utf8.encode(message));
    return 'MSTranslatorAndroidApp::${base64.encode(mac.bytes)}::$dateTime::$guid';
  }

  @override
  Future<String> translate(String text, {required String source, required String target}) async {
    final uri = Uri(
      scheme: 'https',
      host: 'api.cognitive.microsofttranslator.com',
      path: '/translate',
      queryParameters: {
        'api-version': '3.0',
        'to': mapTarget(target),
        if (source != 'auto') 'from': source,
      },
    );
    // -- the signature covers the url **without** the scheme, which is how the
    // app itself signs it; signing the full https url fails with 401.
    final signedUrl = uri.toString().substring('https://'.length);

    final now = DateTime.now().toUtc();
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    String two(int v) => v.toString().padLeft(2, '0');
    final dateTime = '${weekdays[now.weekday - 1]}, ${two(now.day)} ${months[now.month - 1]} ${now.year} '
        '${two(now.hour)}:${two(now.minute)}:${two(now.second)} GMT';
    final guid = aiPseudoUuid();

    final response = await http.postJson(
      uri.toString(),
      json: [
        {'Text': text}
      ],
      headers: {
        'X-MT-Signature': _signature(Uri.encodeComponent(signedUrl), dateTime, guid),
        'Accept': 'application/json',
      },
    ).ensureOk();

    final list = response.jsonList;
    if (list == null || list.isEmpty) throw AiTranslatorException('microsoft: unexpected answer (${response.statusCode}: ${response.snippet})');
    final first = list.first;
    if (first is! Map) throw AiTranslatorException('microsoft: unexpected answer shape: ${response.snippet}');
    final translations = first['translations'];
    if (translations is! List || translations.isEmpty) throw const AiTranslatorException('microsoft: no translation');
    return (translations.first as Map)['text']?.toString() ?? '';
  }
}

/// 必应: the abuse prevention token is scraped out of the translator page.
class BingTranslator extends AiTranslatorEngine {
  @override
  AiTranslatorId get id => AiTranslatorId.bing;

  @override
  final AiTranslatorHttp http = AiTranslatorHttp();

  @override
  Set<String> get supportedTargets => const {'zh-Hans', 'zh-Hant'};

  // -- the regional api only accepts the script codes: zh-CN / zh-TW / zh are
  // all answered with {"statusCode":400}.
  @override
  String mapTarget(String target) => switch (target) {
        'zh' || 'zh-CN' => 'zh-Hans',
        'zh-TW' || 'zh-Hant' => 'zh-Hant',
        _ => target,
      };

  String? _key;
  String? _token;
  String _ig = '';
  String _iid = '';

  bool _initialized = false;
  @override
  Future<void> init() async {
    if (_initialized) return;
    final page = await http.get('https://www.bing.com/Translator').ensureOk();

    // -- var params_AbusePreventionHelper = [ 1791032385390,"token...",3600000 ];
    // the key is a bare number, so grabbing the whole array and stripping quotes
    // would leave the leading `[` glued to it, which the api answers with
    // {"statusCode":205} -- match the two values directly instead.
    final html = page.body;
    final match = RegExp(r'params_AbusePreventionHelper\s*=\s*\[\s*"?([0-9]+)"?\s*,\s*"([^"]*)"').firstMatch(html);
    final key = match?.group(1);
    final token = match?.group(2);
    if (key == null || key.isEmpty || token == null || token.isEmpty) {
      throw const AiTranslatorException('bing: could not read the abuse prevention token, the page changed');
    }
    _key = key;
    _token = token;
    _iid = RegExp(r'<div\s+id="tta_outGDCont"\s+data-iid="([^"]*)">').firstMatch(html)?.group(1) ?? '';
    _ig = RegExp(r'IG:"([^"]*)"').firstMatch(html)?.group(1) ?? '';
    _initialized = true;
  }

  @override
  Future<String> translate(String text, {required String source, required String target}) async {
    await init();

    final form = {
      'text': text,
      'fromLang': source == 'auto' ? 'auto-detect' : source,
      'to': mapTarget(target),
      'tryFetchingGenderDebiasedTranslations': 'true',
      'key': _key!,
      'token': _token!,
    };

    // -- lunaTranslator posts with redirects disabled and, on 302, re-posts the
    // whole form to the Location: following it as a GET (what a browser does)
    // drops the body, and the regional host answers that with 200 + empty body.
    var response = await http.post(
      'https://www.bing.com/ttranslatev3',
      // -- the reference sends these swapped (IG carries the data-iid, IID the
      // IG:"..." value); that order is what is proven at volume, keep it.
      query: {'IG': _iid, 'IID': _ig, 'isVertical': '1'},
      form: form,
      followRedirects: false,
    );
    final location = response.location;
    if ((response.statusCode == 301 || response.statusCode == 302) && location != null) {
      response = await http.post(
        Uri.parse('https://www.bing.com').resolve(location).toString(),
        query: {'IG': _iid, 'IID': _ig, 'isVertical': '1'},
        form: form,
        followRedirects: false,
      );
    }

    final list = response.jsonList;
    if (list == null || list.isEmpty) throw AiTranslatorException('bing: unexpected answer (${response.statusCode}: ${response.snippet})');
    final translations = (list.first as Map)['translations'];
    if (translations is! List || translations.isEmpty) throw const AiTranslatorException('bing: no translation');
    return (translations.first as Map)['text']?.toString() ?? '';
  }
}

/// 谷歌: a public web key with a protobuf-ish json body.
class GoogleTranslator extends AiTranslatorEngine {
  @override
  AiTranslatorId get id => AiTranslatorId.google;

  @override
  final AiTranslatorHttp http = AiTranslatorHttp();

  @override
  Set<String> get supportedTargets => const {'zh-CN', 'zh-TW'};

  static const _apiKey = 'AIzaSyATBXajvzQLTDHEQbcpq0Ihe0vWDHmO520';

  @override
  Future<String> translate(String text, {required String source, required String target}) async {
    if (text.isEmpty) return '';

    // -- the payload looks like protobuf over json: [[[text], from, to], "wt_lib"]
    final payload = jsonEncode([
      [
        [text],
        source == 'auto' ? 'auto' : source,
        mapTarget(target),
      ],
      'wt_lib',
    ]);

    final response = await http.postJson(
      'https://translate-pa.googleapis.com/v1/translateHtml',
      rawBody: payload,
      headers: {
        'Accept': '*/*',
        'Accept-Language': 'en-US,en;q=0.9',
        'X-Goog-Api-Key': _apiKey,
        'Content-Type': 'application/json+protobuf',
      },
    ).ensureOk();

    final list = response.jsonList;
    if (list == null || list.isEmpty) throw AiTranslatorException('google: unexpected answer (${response.statusCode}: ${response.snippet})');
    final inner = list.first;
    if (inner is! List || inner.isEmpty) throw const AiTranslatorException('google: unexpected answer');
    return aiHtmlUnescape(inner.first?.toString() ?? '');
  }
}

/// ModernMT: the web key is a md5 over a timestamp, same as the site does.
class ModernMtTranslator extends AiTranslatorEngine {
  @override
  AiTranslatorId get id => AiTranslatorId.modernMt;

  @override
  final AiTranslatorHttp http = AiTranslatorHttp();

  @override
  Set<String> get supportedTargets => const {'zh-CN', 'zh-TW'};

  @override
  bool get supportsAutoDetect => false;

  bool _initialized = false;

  @override
  Future<void> init() async {
    if (_initialized) return;
    await http.get(
      'https://www.modernmt.com/translate',
      headers: const {'Referer': 'https://www.modernmt.com/translate'},
    );
    _initialized = true;
  }

  @override
  Future<String> translate(String text, {required String source, required String target}) async {
    await init();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final response = await http.postJson(
      'https://webapi.modernmt.com/translate',
      json: {
        'q': text,
        'source': source == 'auto' ? '' : source,
        'target': mapTarget(target),
        'ts': ts,
        'verify': aiMd5Hex('webkey_E3sTuMjpP8Jez49GcYpDVH7r#$ts#$text'),
        'hints': '',
        'multiline': 'true',
      },
      headers: const {
        'Origin': 'https://www.modernmt.com',
        'Referer': 'https://www.modernmt.com/translate',
        'X-Requested-With': 'XMLHttpRequest',
        'X-HTTP-Method-Override': 'GET',
      },
    ).ensureOk();

    final data = response.json?['data'];
    if (data is! Map) throw const AiTranslatorException('ModernMT: unexpected answer');
    return data['translation']?.toString() ?? '';
  }
}

/// 有道: the desktop dictionary endpoint, it only answers to its own UA.
class YoudaoTranslator extends AiTranslatorEngine {
  @override
  AiTranslatorId get id => AiTranslatorId.youdao;

  @override
  final AiTranslatorHttp http = AiTranslatorHttp();

  @override
  Set<String> get supportedTargets => const {'zh-CHS', 'zh-CHT'};

  @override
  String mapTarget(String target) => switch (target) {
        'zh' || 'zh-CN' => 'zh-CHS',
        'zh-TW' || 'zh-Hant' => 'zh-CHT',
        _ => target,
      };

  @override
  Future<String> translate(String text, {required String source, required String target}) async {
    final mysticTime = '${DateTime.now().millisecondsSinceEpoch}';
    const key = 'cybibtzhdwayqjmrncst';

    final response = await http.post(
      'https://dict.youdao.com/dicttranslate',
      query: {
        'keyfrom': 'deskdict.main',
        'client': 'deskdict',
        'from': source == 'auto' ? 'auto' : source,
        'to': mapTarget(target),
        'keyid': 'deskdict',
        'mysticTime': mysticTime,
        'pointParam': 'client,product,mysticTime',
        'sign': aiMd5Hex('client=deskdict&mysticTime=$mysticTime&product=deskdict&key=$key'),
        'domain': '0',
        'useTerm': 'false',
        'noCheckPrivate': 'false',
        'recTerms': '[]',
        'id': '0a464aedddbc6e4b9',
        'vendor': 'fanyiweb_navigation',
        'in': 'YoudaoDict_fanyiweb_navigation',
        'appVer': '11.2.0.0',
        'appZengqiang': '0',
        'abTest': '0',
        'model': 'LENOVO',
        'screen': '1920*1080',
        'OsVersion': '10.0.19045',
        'network': 'none',
        'mid': 'windows10.0.19045',
        'appVersion': '11.2.0.0',
        'product': 'deskdict',
        'source': 'mine_transtab_realtime',
      },
      form: {'i': text},
      headers: const {
        'Accept': '*/*',
        // -- the endpoint rejects anything that is not the desktop app
        'User-Agent': 'Youdao Desktop Dict (Windows NT 10.0)',
      },
    ).ensureOk();

    final result = response.json?['translateResult'];
    if (result is! List) throw const AiTranslatorException('有道: unexpected answer');
    // -- a list of segments, each holding a list of {src, tgt} entries
    final buffer = StringBuffer();
    for (final segment in result) {
      if (segment is! List) continue;
      for (final part in segment) {
        if (part is Map) buffer.write(part['tgt']?.toString() ?? '');
      }
    }
    return buffer.toString();
  }
}
