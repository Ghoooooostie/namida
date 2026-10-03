// AI 字幕翻译服务：优先使用无密钥传统引擎，否则调用 OpenAI/Gemini。
import 'dart:convert';

import 'package:rhttp/rhttp.dart';

import 'package:namida/class/subtitle_srt.dart';
import 'package:namida/controller/ai_subtitle/ai_asr_shared.dart';
import 'package:namida/controller/ai_subtitle/ai_subtitle_config.dart';
import 'package:namida/controller/ai_subtitle/translators/ai_translator.dart';

class AiTranslationException implements Exception {
  final String message;
  const AiTranslationException(this.message);

  @override
  String toString() => message;
}

typedef AiTranslatorFactory = AiTranslatorEngine Function(AiTranslatorId id);

/// 翻译字幕并保留时间轴，传统引擎一次只选优先级最高的启用项。
class AiTranslationService {
  /// cues per request, small enough to fit comfortably in any context window
  static const batchSize = 40;

  /// 免费传统引擎对突发请求限流（返回 200 + 空 body），逐条之间隔一小会。
  static const _traditionalPacing = Duration(milliseconds: 150);

  /// 单条失败后的退避重试等待，用完仍失败才把错误暴露给任务。
  static const _traditionalRetries = [
    Duration(milliseconds: 600),
    Duration(milliseconds: 1500),
    Duration(milliseconds: 3000),
  ];

  AiTranslationService({AiTranslatorFactory? translatorFactory}) : _translatorFactory = translatorFactory ?? createAiTranslator;

  final AiTranslatorFactory _translatorFactory;

  /// 按设置选择传统引擎或 API 翻译路径。
  Future<List<SubtitleSrtCue>> translate(
    List<SubtitleSrtCue> cues,
    AiTranslationSettings settings, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (cues.isEmpty) return const [];
    if (settings.enabledTraditionalEngines.isNotEmpty) {
      return _translateWithTraditionalEngine(cues, settings, onProgress: onProgress, cancelToken: cancelToken);
    }
    if (settings.apiKey.isEmpty) throw const AiTranslationException('The API key is empty');
    if (settings.model.isEmpty) throw const AiTranslationException('The model name is empty');

    final translated = <SubtitleSrtCue>[];
    final batches = _batched(cues, batchSize);
    var done = 0;

    for (final batch in batches) {
      if (cancelToken?.isCancelled ?? false) break;
      final texts = await _translateBatch(batch, settings, cancelToken: cancelToken);

      for (var i = 0; i < batch.length; i++) {
        final text = texts[i]?.trim() ?? '';
        final original = batch[i];
        if (text.isEmpty) continue;
        translated.add(original.copyWith(text: text));
      }

      done += batch.length;
      onProgress?.call(done / cues.length);
    }

    return SubtitleSrt.normalize(translated);
  }

  /// 使用一个传统引擎完成整批字幕，逐条限速，失败退避重试后仍失败才暴露错误。
  Future<List<SubtitleSrtCue>> _translateWithTraditionalEngine(
    List<SubtitleSrtCue> cues,
    AiTranslationSettings settings, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final engineId = settings.enabledTraditionalEngines.first;
    final engine = _translatorFactory(engineId);
    await engine.init();

    final translated = <SubtitleSrtCue>[];
    for (var i = 0; i < cues.length; i++) {
      if (cancelToken?.isCancelled ?? false) break;
      final original = cues[i];
      final text = await _translateCueWithRetries(engine, engineId, original.text, settings.targetLanguage.code, cancelToken: cancelToken);
      translated.add(original.copyWith(text: text));
      onProgress?.call((i + 1) / cues.length);
      if (i + 1 < cues.length) await Future<void>.delayed(_traditionalPacing);
    }

    return SubtitleSrt.normalize(translated);
  }

  /// 单条翻译，带退避重试：空译文与引擎异常都算失败，最后一次的错误原样抛出。
  Future<String> _translateCueWithRetries(
    AiTranslatorEngine engine,
    AiTranslatorId engineId,
    String text,
    String target, {
    required CancelToken? cancelToken,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt <= _traditionalRetries.length; attempt++) {
      if (attempt > 0) await Future<void>.delayed(_traditionalRetries[attempt - 1]);
      try {
        final result = (await engine.translate(text, source: 'auto', target: target)).trim();
        if (result.isNotEmpty) return result;
      } catch (e) {
        if (cancelToken?.isCancelled ?? false) rethrow;
        lastError = e;
      }
    }
    throw AiTranslationException('${engineId.label}: ${lastError ?? 'empty translation (throttled?)'}');
  }

  /// 调用 API 翻译一个批次。
  Future<List<String?>> _translateBatch(
    List<SubtitleSrtCue> batch,
    AiTranslationSettings settings, {
    required CancelToken? cancelToken,
  }) async {
    final result = List<String?>.filled(batch.length, null);
    final payload = jsonEncode([
      for (var i = 0; i < batch.length; i++) {'id': i, 'text': batch[i].text},
    ]);

    final body = settings.provider.isOpenAiCompatible
        ? await _askOpenAiCompatible(payload, settings, cancelToken)
        : await _askGemini(payload, settings, cancelToken);

    return _merge(body, result);
  }

  /// 合并模型返回的字幕文本并保持原顺序。
  List<String?> _merge(String body, List<String?> result) {
    final cleaned = AiAsrShared.stripFence(body);
    List<dynamic>? parsed;
    try {
      final decoded = jsonDecode(cleaned);
      parsed = decoded is List ? decoded : (decoded as Map<String, dynamic>)['translations'] as List<dynamic>?;
    } catch (_) {
      parsed = null;
    }

    if (parsed != null) {
      for (final item in parsed) {
        if (item is! Map) continue;
        final id = item['id'];
        final text = item['text']?.toString();
        if (id is int && id >= 0 && id < result.length && text != null) result[id] = text;
      }
      return result;
    }

    // -- not json, treat the whole answer as one line per cue.
    final lines = cleaned.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    for (var i = 0; i < result.length && i < lines.length; i++) {
      result[i] = lines[i];
    }
    return result;
  }

  static const _systemPrompt = '''You translate subtitles.
Rules you must follow exactly:
- reply with a json array only, no markdown fence, no commentary
- each element is {"id": <int>, "text": "<translation>"}
- keep every id, in the same order, never merge or split entries
- keep the line count of each entry, a two line cue stays two lines
- preserve names, numbers and units
- never add explanations, notes or quotation marks that were not there
- never translate into a language other than the requested target''';

  Future<String> _askOpenAiCompatible(String payload, AiTranslationSettings settings, CancelToken? cancelToken) async {
    final client = await RhttpClient.create();
    try {
      final response = await client.post(
        '${AiAsrShared.trimTrailingSlash(settings.baseUrl)}/chat/completions',
        headers: HttpHeaders.rawMap({
          'Authorization': 'Bearer ${settings.apiKey}',
          'Content-Type': 'application/json',
        }),
        body: HttpBody.json({
          'model': settings.model,
          'temperature': 0.2,
          'messages': [
            {'role': 'system', 'content': _systemPrompt},
            {'role': 'user', 'content': _userPrompt(payload, settings)},
          ],
        }),
        cancelToken: cancelToken,
      );

      if (response.statusCode != 200) {
        throw AiTranslationException(AiAsrShared.describeHttpFailure(response.statusCode, response.body));
      }
      return _extractChatText(response.body);
    } finally {
      client.dispose(cancelRunningRequests: true);
    }
  }

  Future<String> _askGemini(String payload, AiTranslationSettings settings, CancelToken? cancelToken) async {
    final client = await RhttpClient.create();
    try {
      final response = await client.post(
        'https://generativelanguage.googleapis.com/v1beta/models/${settings.model}:generateContent',
        headers: HttpHeaders.rawMap({
          'x-goog-api-key': settings.apiKey,
          'Content-Type': 'application/json',
        }),
        body: HttpBody.json({
          'contents': [
            {
              'parts': [
                {'text': _userPrompt(payload, settings)},
              ]
            }
          ]
        }),
        cancelToken: cancelToken,
      );

      if (response.statusCode != 200) {
        throw AiTranslationException(AiAsrShared.describeHttpFailure(response.statusCode, response.body));
      }
      return AiAsrShared.extractGeminiText(response.body);
    } finally {
      client.dispose(cancelRunningRequests: true);
    }
  }

  /// 组合 API 请求提示词。
  static String _userPrompt(String payload, AiTranslationSettings settings) {
    return <String>[
      'Translate the subtitles into ${settings.targetLanguage.label}.',
      if (settings.stylePrompt.isNotEmpty) 'Style: ${settings.stylePrompt}',
      'The output format is fixed, do not change it.',
      'Input:',
      payload,
    ].join('\n');
  }

  static String _extractChatText(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final choices = json['choices'];
      if (choices is List && choices.isNotEmpty) {
        return (choices.first as Map)['message']?['content']?.toString() ?? '';
      }
    } catch (_) {}
    return '';
  }

  /// 测试当前优先级最高的传统引擎，或测试 API 配置。
  Future<void> testConnection(AiTranslationSettings settings, {CancelToken? cancelToken}) async {
    if (settings.enabledTraditionalEngines.isNotEmpty) {
      if (cancelToken?.isCancelled ?? false) return;
      final engineId = settings.enabledTraditionalEngines.first;
      final engine = _translatorFactory(engineId);
      await engine.init();
      final result = await engine.translate('hello', source: 'en', target: settings.targetLanguage.code);
      if (result.trim().isEmpty) throw AiTranslationException('${engineId.label}: empty translation');
      return;
    }
    if (settings.apiKey.isEmpty) throw const AiTranslationException('The API key is empty');
    if (settings.model.isEmpty) throw const AiTranslationException('The model name is empty');

    final client = await RhttpClient.create();
    try {
      final response = await client.post(
        '${AiAsrShared.trimTrailingSlash(settings.baseUrl)}/chat/completions',
        headers: HttpHeaders.rawMap({
          'Authorization': 'Bearer ${settings.apiKey}',
          'Content-Type': 'application/json',
        }),
        body: HttpBody.json({
          'model': settings.model,
          'max_tokens': 16,
          'messages': [
            {'role': 'user', 'content': 'Reply with the single word: ok'},
          ],
        }),
        cancelToken: cancelToken,
      );

      if (response.statusCode != 200) {
        throw AiTranslationException(AiAsrShared.describeHttpFailure(response.statusCode, response.body));
      }
    } finally {
      client.dispose(cancelRunningRequests: true);
    }
  }
}

/// 按固定大小切分字幕批次。
List<List<SubtitleSrtCue>> _batched(List<SubtitleSrtCue> cues, int size) {
  final result = <List<SubtitleSrtCue>>[];
  for (var i = 0; i < cues.length; i += size) {
    result.add(cues.sublist(i, (i + size).clamp(0, cues.length)));
  }
  return result;
}