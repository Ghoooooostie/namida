import 'package:namida/controller/ai_subtitle/translators/ai_translator_http.dart';
import 'package:namida/controller/ai_subtitle/translators/ai_translator_engines.dart';
import 'package:namida/controller/ai_subtitle/translators/ai_translator_engines_cn.dart';
import 'package:namida/controller/ai_subtitle/translators/ai_translator_engines_huoshan.dart';
import 'package:namida/controller/ai_subtitle/translators/ai_translator_engines_papago.dart';
import 'package:namida/controller/ai_subtitle/translators/ai_translator_engines_qq.dart';

/// The key-less ("传统") engines, in the order LunaTranslator lists them.
///
/// The order matters: the settings screen shows them in a 3 column grid exactly
/// like the reference, and the first enabled one wins at translation time.
enum AiTranslatorId {
  microsoft('microsoft', 'microsoft'),
  bing('bing', '必应'),
  google('google', '谷歌'),
  modernMt('modernMt', 'ModernMT'),
  qqTranSmart('qqTranSmart', 'qqTranSmart'),
  ali('ali', '阿里'),
  youdao('youdao', '有道'),
  caiyun('caiyun', '彩云'),
  translateCom('translateCom', 'TranslateCom'),
  yandex('yandex', 'yandex'),
  qqimt('qqimt', 'qqimt'),
  huoshan('huoshan', '火山'),
  papago('papago', 'papago');

  const AiTranslatorId(this.id, this.label);

  /// stable id, used as the settings value
  final String id;

  /// what the switch shows
  final String label;

  static AiTranslatorId? fromId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final value in values) {
      if (value.id == id) return value;
    }
    return null;
  }
}

/// One translation engine.
///
/// None of these need a key: they are the free endpoints the desktop
/// dictionaries and browser extensions use, with the same headers, tokens and
/// cookies those clients send. [init] is the optional "fetch a token first"
/// step, cached for the lifetime of the instance.
abstract class AiTranslatorEngine {
  AiTranslatorId get id;

  AiTranslatorHttp get http;

  /// A short note shown under the grid.
  String? get note => null;

  /// whether this engine can be used right now
  bool get isReady => true;

  /// the language codes this engine accepts as `to`, per its langmap.
  ///
  /// An empty set means "anything the standard code covers".
  Set<String> get supportedTargets => const {};

  /// whether the engine can auto detect the source language.
  bool get supportsAutoDetect => true;

  /// fetch a cookie/token, called lazily and only once per instance.
  Future<void> init() async {}

  /// translate a single piece of text, [source] may be `auto`.
  ///
  /// Throws [AiTranslatorException] with something readable on failure.
  Future<String> translate(String text, {required String source, required String target});

  /// whether the engine can output simplified chinese directly.
  bool get supportsSimplified =>
      supportedTargets.contains('zh-CN') || supportedTargets.contains('zh-Hans') || supportedTargets.contains('zh-CHS');

  /// whether the engine can output traditional chinese.
  bool get supportsTraditional =>
      supportedTargets.contains('zh-TW') || supportedTargets.contains('zh-Hant') || supportedTargets.contains('zh-CHT');

  /// `zh` -> the engine's own spelling of simplified/traditional, see
  /// [aiResolveTarget]; engines with non standard codes (必应, 有道) override this.
  String mapTarget(String target) =>
      aiResolveTarget(target, supportsSimplified: supportsSimplified, supportsTraditional: supportsTraditional);

  String mapSource(String source) => source;
}

/// Builds the engine for an id. Each engine keeps its own [AiTranslatorHttp], so
/// the cookies and tokens of one provider never leak into another.
AiTranslatorEngine createAiTranslator(AiTranslatorId id) => switch (id) {
      AiTranslatorId.microsoft => MicrosoftTranslator(),
      AiTranslatorId.bing => BingTranslator(),
      AiTranslatorId.google => GoogleTranslator(),
      AiTranslatorId.modernMt => ModernMtTranslator(),
      AiTranslatorId.qqTranSmart => QqTranSmartTranslator(),
      AiTranslatorId.ali => AliTranslator(),
      AiTranslatorId.youdao => YoudaoTranslator(),
      AiTranslatorId.caiyun => CaiyunTranslator(),
      AiTranslatorId.translateCom => TranslateComTranslator(),
      AiTranslatorId.yandex => YandexTranslator(),
      AiTranslatorId.qqimt => QqimtTranslator(),
      AiTranslatorId.huoshan => HuoshanTranslator(),
      AiTranslatorId.papago => PapagoTranslator(),
    };
