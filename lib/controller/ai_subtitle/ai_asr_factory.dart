import 'package:namida/controller/ai_subtitle/ai_asr_gemini.dart';
import 'package:namida/controller/ai_subtitle/ai_asr_openai.dart';
import 'package:namida/controller/ai_subtitle/ai_asr_shared.dart';
import 'package:namida/controller/ai_subtitle/ai_asr_sherpa.dart';
import 'package:namida/controller/ai_subtitle/ai_asr_vosk.dart';
import 'package:namida/controller/ai_subtitle/ai_subtitle_config.dart';

/// Picks the engine the user asked for. Kept apart from the engines so they do
/// not have to import each other.
class AiAsrEngineFactory {
  static AiAsrEngine create(AiAsrSettings settings) {
    if (settings.isLocal) {
      return switch (settings.engine) {
        AiLocalAsrEngine.vosk => VoskAsrEngine(),
        _ => SherpaOnnxAsrEngine(),
      };
    }
    return settings.provider.isOpenAiCompatible ? OpenAiCompatibleAsr() : GeminiAsr();
  }
}
