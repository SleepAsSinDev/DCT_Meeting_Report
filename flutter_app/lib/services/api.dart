import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';

class BackendApi {
  final Dio dio;
  final String defaultModelSize;
  final String defaultLanguage;
  final String defaultQuality;

  BackendApi(
    String baseUrl, {
    this.defaultModelSize = 'large-v3',
    this.defaultLanguage = 'th',
    this.defaultQuality = 'accurate',
  }) : dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(minutes: 10),
          receiveTimeout: const Duration(hours: 6),
        )) {
    // ignore: avoid_print
    print('[API] BASE URL  = ${dio.options.baseUrl}');
  }

  Future<FormData> _buildFormData(
    String filePath, {
    String? language,
    String? modelSize,
    String? quality,
    String? initialPrompt,
    bool? preprocess,
    bool? fastPreprocess,
  }) async {
    final bytes = await File(filePath).readAsBytes();
    final filename = filePath.split(Platform.pathSeparator).last;
    return FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
      'language': language ?? defaultLanguage,
      'model_size': modelSize ?? defaultModelSize,
      'quality': quality ?? defaultQuality,
      if (initialPrompt != null && initialPrompt.isNotEmpty) 'initial_prompt': initialPrompt,
      if (preprocess != null) 'preprocess': preprocess,
      if (fastPreprocess != null) 'fast_preprocess': fastPreprocess,
    });
  }

  Future<Map<String, dynamic>> transcribe(
    String filePath, {
    String? language,
    String? modelSize,
    String? quality,
    String? initialPrompt,
    bool? preprocess,
    bool? fastPreprocess,
  }) async {
    final formData = await _buildFormData(
      filePath,
      language: language,
      modelSize: modelSize,
      quality: quality,
      initialPrompt: initialPrompt,
      preprocess: preprocess,
      fastPreprocess: fastPreprocess,
    );
    final res = await dio.post(
      '/transcribe',
      data: formData,
      options: Options(
        receiveTimeout: const Duration(hours: 6),
        sendTimeout: const Duration(minutes: 10),
      ),
    );
    return res.data as Map<String, dynamic>;
  }

  Stream<Map<String, dynamic>> transcribeStream(
    String filePath, {
    String? language,
    String? modelSize,
    String? quality,
    String? initialPrompt,
    bool? preprocess,
    bool? fastPreprocess,
  }) async* {
    final formData = await _buildFormData(
      filePath,
      language: language,
      modelSize: modelSize,
      quality: quality,
      initialPrompt: initialPrompt,
      preprocess: preprocess,
      fastPreprocess: fastPreprocess,
    );
    final res = await dio.post(
      '/transcribe_stream',
      data: formData,
      options: Options(
        responseType: ResponseType.stream,
        receiveTimeout: const Duration(hours: 6),
        sendTimeout: const Duration(minutes: 10),
      ),
    );
    final body = res.data as ResponseBody;
    final lines = body.stream
        .map((chunk) => utf8.decode(chunk))
        .transform(const LineSplitter());
    await for (final line in lines) {
      if (line.trim().isEmpty) continue;
      yield jsonDecode(line);
    }
  }

  Future<String> summarize(String transcript,
      {String style = "thai-formal", List<String>? sections}) async {
    final res = await dio.post('/summarize', data: {
      'transcript': transcript,
      'style': style,
      'sections': sections,
    }, options: Options(receiveTimeout: const Duration(minutes: 2)));
    return (res.data as Map<String, dynamic>)['report_markdown'] as String;
  }
}
