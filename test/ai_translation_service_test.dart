// 传统翻译引擎优先级与无密钥路径测试。
import 'package:flutter_test/flutter_test.dart';

import 'package:namida/class/subtitle_srt.dart';
import 'package:namida/controller/ai_subtitle/ai_subtitle_config.dart';
import 'package:namida/controller/ai_subtitle/ai_translation_service.dart';
import 'package:namida/controller/ai_subtitle/translators/ai_translator.dart';
import 'package:namida/controller/ai_subtitle/translators/ai_translator_http.dart';

class _FakeTranslator extends AiTranslatorEngine {
  _FakeTranslator(this._id, this.answer);

  final AiTranslatorId _id;
  final String answer;
  int calls = 0;

  @override
  AiTranslatorId get id => _id;

  @override
  final AiTranslatorHttp http = AiTranslatorHttp();

  @override
  Future<String> translate(String text, {required String source, required String target}) async {
    calls++;
    return answer;
  }
}

void main() {
  test('uses the highest-priority traditional engine without an API key', () async {
    final first = _FakeTranslator(AiTranslatorId.google, '传统翻译');
    final second = _FakeTranslator(AiTranslatorId.microsoft, '不应调用');
    final service = AiTranslationService(
      translatorFactory: (id) => id == AiTranslatorId.google ? first : second,
    );
    const settings = AiTranslationSettings(
      enabledTraditionalEngines: [AiTranslatorId.google, AiTranslatorId.microsoft],
      provider: AiApiProvider.openAi,
      baseUrl: '',
      model: '',
      apiKey: '',
      targetLanguage: AiSubtitleTargetLanguage.simplifiedChinese,
      stylePrompt: '',
    );

    final result = await service.translate(
      const [SubtitleSrtCue(startMS: 0, endMS: 1000, text: 'hello')],
      settings,
    );

    expect(result.single.text, '传统翻译');
    expect(first.calls, 1);
    expect(second.calls, 0);
  });

  test('requires the API key only when no traditional engine is enabled', () async {
    const settings = AiTranslationSettings(
      enabledTraditionalEngines: [],
      provider: AiApiProvider.openAi,
      baseUrl: '',
      model: 'gpt-4o-mini',
      apiKey: '',
      targetLanguage: AiSubtitleTargetLanguage.simplifiedChinese,
      stylePrompt: '',
    );

    expect(
      () => AiTranslationService().translate(
        const [SubtitleSrtCue(startMS: 0, endMS: 1000, text: 'hello')],
        settings,
      ),
      throwsA(isA<AiTranslationException>()),
    );
  });
}