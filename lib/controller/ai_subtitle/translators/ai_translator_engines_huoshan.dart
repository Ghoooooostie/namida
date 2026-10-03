import 'package:namida/controller/ai_subtitle/translators/ai_translator.dart';
import 'package:namida/controller/ai_subtitle/translators/ai_translator_http.dart';

/// 火山: the browser extension endpoint, it insists on the extension origin.
class HuoshanTranslator extends AiTranslatorEngine {
  @override
  AiTranslatorId get id => AiTranslatorId.huoshan;

  @override
  final AiTranslatorHttp http = AiTranslatorHttp();

  @override
  Set<String> get supportedTargets => const {'zh-Hant'};

  @override
  Future<String> translate(String text, {required String source, required String target}) async {
    final response = await http.postJson(
      'https://translate.volcengine.com/crx/translate/v1/',
      json: {
        'text': text,
        'target_language': mapTarget(target),
        'enable_user_glossary': false,
        'glossary_list': <dynamic>[],
        'category': '',
        if (source != 'auto') 'source_language': source,
      },
      headers: {
        'Accept': 'application/json, text/plain, */*',
        // -- has to look like the extension call, otherwise it answers 403
        'Origin': 'chrome-extension://klgfhbiooeogdfodpopgppeadghjjemk',
        'Sec-Fetch-Dest': 'empty',
        'Sec-Fetch-Mode': 'cors',
        'Sec-Fetch-Site': 'none',
      },
    ).ensureOk();

    final translation = response.json?['translation'];
    if (translation == null) throw const AiTranslatorException('火山: no translation');
    return translation.toString();
  }
}
