import 'package:crypto/crypto.dart';

import 'package:namida/controller/ai_subtitle/translators/ai_translator.dart';
import 'package:namida/controller/ai_subtitle/translators/ai_translator_engines.dart';
import 'package:namida/controller/ai_subtitle/translators/ai_translator_http.dart';

/// papago: the auth key is scraped from a js chunk, then an HMAC-MD5 per call.
class PapagoTranslator extends AiTranslatorEngine {
  @override
  AiTranslatorId get id => AiTranslatorId.papago;

  @override
  final AiTranslatorHttp http = AiTranslatorHttp();

  @override
  Set<String> get supportedTargets => const {'zh-CN', 'zh-TW'};

  static const url = 'https://papago.naver.com/apis/n2mt/translate';
  static const browserHeaders = {'Accept-Language': 'zh-CN,zh;q=0.9'};

  /// the chunk embeds the key right after a PPG prefixed call; splitting on the
  /// double quote yields the parts, and the key is the middle one.
  static String? extractKey(String script) {
    final index = script.indexOf('PPG ');
    if (index < 0) return null;
    final parts = script.substring(index + 4).split(String.fromCharCode(34));
    if (parts.length < 3) return null;
    return parts[2].isEmpty ? null : parts[2];
  }

  String? authKey;
  String? uuid;
  bool initialized = false;

  @override
  Future<void> init() async {
    if (initialized) return;

    final home = (await http.get('https://papago.naver.com/', headers: browserHeaders).ensureOk()).body;
    final chunk = RegExp(r'/main\.(.*?)\.chunk\.js').firstMatch(home)?.group(0);
    if (chunk == null) throw const AiTranslatorException('papago: could not find the js chunk');

    final script = (await http.get('https://papago.naver.com$chunk', headers: browserHeaders).ensureOk()).body;
    final key = extractKey(script);
    if (key == null) throw const AiTranslatorException('papago: could not read the auth key');

    authKey = key;
    uuid = aiPseudoUuid();
    initialized = true;
  }

  @override
  Future<String> translate(String text, {required String source, required String target}) async {
    await init();
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final to = mapTarget(target);
    // the signature covers deviceId, the url and the timestamp, newline joined
    final message = <String>[uuid!, url, timestamp].join(String.fromCharCode(10));
    final signature = aiHmacBase64(authKey!, message, md5);

    final response = await http.post(
      url,
      headers: {
        'Accept': 'application/json',
        'authorization': 'PPG $uuid:$signature',
        'device-type': 'pc',
        'Origin': 'https://papago.naver.com',
        'Referer': 'https://papago.naver.com/',
        'timestamp': timestamp,
        'x-apigw-partnerid': 'papago',
      },
      form: {
        'deviceId': uuid!,
        'locale': to,
        'dict': 'true',
        'dictDisplay': '30',
        'honorific': 'false',
        'instant': 'false',
        'paging': 'false',
        'source': source == 'auto' ? 'auto' : source,
        'target': to,
        'text': text,
      },
    ).ensureOk();

    final translated = response.json?['translatedText'];
    if (translated == null) throw const AiTranslatorException('papago: no translation');
    return translated.toString();
  }
}