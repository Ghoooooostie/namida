import 'dart:convert';
import 'dart:io';

import 'package:rhttp/rhttp.dart';

import 'package:namida/class/subtitle_srt.dart';
import 'package:namida/controller/ai_subtitle/ai_asr_shared.dart';
import 'package:namida/controller/ai_subtitle/ai_subtitle_config.dart';

/// Gemini has no transcription endpoint: the audio is handed to the model as an
/// inline blob and it is asked for SRT. Fine for clips, a long file can exceed
/// the inline size limit, so it stays an explicit choice.
class GeminiAsr implements AiAsrEngine {
  static const _host = 'https://generativelanguage.googleapis.com/v1beta';

  @override
  String get label => 'Gemini';

  @override
  Future<List<SubtitleSrtCue>> transcribe(
    File audio, {
    required AiAsrSettings settings,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (settings.apiKey.isEmpty) throw const AiAsrException('The API key is empty');
    if (settings.model.isEmpty) throw const AiAsrException('The model name is empty');

    final client = await RhttpClient.create();
    try {
      onProgress?.call(0.1);
      final data = base64Encode(await audio.readAsBytes());
      onProgress?.call(0.4);

      final response = await client.post(
        '$_host/models/${settings.model}:generateContent',
        headers: HttpHeaders.rawMap({
          'x-goog-api-key': settings.apiKey,
          'Content-Type': 'application/json',
        }),
        body: HttpBody.json({
          'contents': [
            {
              'parts': [
                {'text': _instructions(settings)},
                {
                  'inline_data': {
                    'mime_type': AiAsrShared.mimeTypeFor(audio.path),
                    'data': data,
                  }
                }
              ]
            }
          ]
        }),
        cancelToken: cancelToken,
        onSendProgress: (sent, total) {
          if (total > 0) onProgress?.call((0.4 + 0.55 * (sent / total)).clamp(0, 0.95));
        },
      );

      if (response.statusCode != 200) {
        throw AiAsrException(AiAsrShared.describeHttpFailure(response.statusCode, response.body));
      }

      onProgress?.call(1);
      final cues = SubtitleSrt.parse(AiAsrShared.stripFence(AiAsrShared.extractGeminiText(response.body)));
      if (cues.isEmpty) throw const AiAsrException('Gemini returned no usable subtitles');
      return cues;
    } finally {
      client.dispose(cancelRunningRequests: true);
    }
  }
  static String _instructions(AiAsrSettings settings) {
    return <String>[
      'Transcribe the attached audio into SubRip (SRT) subtitles.',
      'Rules:',
      '- one cue per utterance, split where the speaker pauses',
      '- keep the original language, never translate',
      if (settings.languageCode.isNotEmpty) '- the language is ${settings.languageCode}',
      if (settings.prompt.isNotEmpty) '- ${settings.prompt}',
      '- output only the SRT body, starting from the first timestamp',
      '- no markdown fence, no commentary',
    ].join('\n');
  }

  @override
  Future<void> testConnection(AiAsrSettings settings, {CancelToken? cancelToken}) async {
    if (settings.apiKey.isEmpty) throw const AiAsrException('The API key is empty');
    if (settings.model.isEmpty) throw const AiAsrException('The model name is empty');

    final client = await RhttpClient.create();
    try {
      final response = await client.get(
        '$_host/models',
        headers: HttpHeaders.rawMap({'x-goog-api-key': settings.apiKey}),
        cancelToken: cancelToken,
      );
      if (response.statusCode != 200) {
        throw AiAsrException(AiAsrShared.describeHttpFailure(response.statusCode, response.body));
      }
    } finally {
      client.dispose(cancelRunningRequests: true);
    }
  }
}
