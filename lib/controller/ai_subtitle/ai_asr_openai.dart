import 'dart:convert';
import 'dart:io';

import 'package:rhttp/rhttp.dart';

import 'package:namida/class/subtitle_srt.dart';
import 'package:namida/controller/ai_subtitle/ai_asr_shared.dart';
import 'package:namida/controller/ai_subtitle/ai_subtitle_config.dart';
import 'package:namida/core/extensions.dart';

/// `POST {baseUrl}/audio/transcriptions`, the shape shared by OpenAI, Groq,
/// SiliconFlow, DashScope FunAudioLLM and self hosted whisper.cpp servers.
class OpenAiCompatibleAsr implements AiAsrEngine {
  @override
  String get label => 'OpenAI compatible';

  @override
  Future<List<SubtitleSrtCue>> transcribe(
    File audio, {
    required AiAsrSettings settings,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (settings.apiKey.isEmpty) throw const AiAsrException('The API key is empty');
    if (settings.baseUrl.isEmpty) throw const AiAsrException('The base url is empty');

    final upload = await AiAsrShared.prepareUploadFile(audio);
    final isTemporary = upload.path != audio.path;
    final client = await RhttpClient.create();

    try {
      final formData = <String, MultipartItem>{
        'model': MultipartItem.text(text: settings.model),
        // -- verbose_json is the only format that carries per segment timings,
        // -- plain text could only be spread over the whole duration.
        'response_format': MultipartItem.text(text: 'verbose_json'),
        if (settings.languageCode.isNotEmpty) 'language': MultipartItem.text(text: settings.languageCode),
        if (settings.prompt.isNotEmpty) 'prompt': MultipartItem.text(text: settings.prompt),
        'file': MultipartItem.file(
          file: upload.path,
          fileName: upload.uri.pathSegments.last,
          contentType: AiAsrShared.mimeTypeFor(upload.path),
        ),
      };

      final response = await client.post(
        '${AiAsrShared.trimTrailingSlash(settings.baseUrl)}/audio/transcriptions',
        headers: HttpHeaders.rawMap({'Authorization': 'Bearer ${settings.apiKey}'}),
        body: HttpBody.multipart(formData),
        cancelToken: cancelToken,
        onSendProgress: (sent, total) {
          // -- recognition happens server side, the upload is all we can report.
          if (total > 0) onProgress?.call((sent / total).clamp(0, 0.95));
        },
      );

      if (response.statusCode != 200) {
        throw AiAsrException(AiAsrShared.describeHttpFailure(response.statusCode, response.body));
      }

      onProgress?.call(1);
      return parseResponse(response.body);
    } finally {
      client.dispose(cancelRunningRequests: true);
      if (isTemporary) upload.delete().ignoreError();
    }
  }
  /// Also used by the translation flow, a provider can answer with an srt body
  /// instead of json even when json was asked for.
  static List<SubtitleSrtCue> parseResponse(String body) {
    Map<String, dynamic> json;
    try {
      json = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      final parsed = SubtitleSrt.parse(body);
      if (parsed.isNotEmpty) return parsed;
      throw const AiAsrException('The API returned an unexpected response');
    }

    final segments = json['segments'];
    if (segments is List && segments.isNotEmpty) {
      final cues = <SubtitleSrtCue>[];
      for (final segment in segments) {
        if (segment is! Map) continue;
        final text = segment['text']?.toString().trim() ?? '';
        if (text.isEmpty) continue;
        final startMS = AiAsrShared.toMS(segment['start']);
        final endMS = AiAsrShared.toMS(segment['end']);
        cues.add(SubtitleSrtCue(
          startMS: startMS,
          endMS: endMS > startMS ? endMS : startMS + 200,
          text: text,
        ));
      }
      if (cues.isNotEmpty) return SubtitleSrt.normalize(cues);
    }

    // -- no usable segments (some providers only return `text`), spreading it
    // -- over the duration is worse than useless, so it is reported as empty.
    final text = json['text']?.toString().trim() ?? '';
    if (text.isEmpty) return const [];
    throw const AiAsrException('The provider returned text without timings, try a model that reports segments');
  }

  @override
  Future<void> testConnection(AiAsrSettings settings, {CancelToken? cancelToken}) async {
    if (settings.apiKey.isEmpty) throw const AiAsrException('The API key is empty');
    if (settings.baseUrl.isEmpty) throw const AiAsrException('The base url is empty');

    final client = await RhttpClient.create();
    try {
      final response = await client.get(
        '${AiAsrShared.trimTrailingSlash(settings.baseUrl)}/models',
        headers: HttpHeaders.rawMap({'Authorization': 'Bearer ${settings.apiKey}'}),
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
