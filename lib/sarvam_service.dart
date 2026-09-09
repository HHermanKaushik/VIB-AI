import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class SarvamSttResult {
  const SarvamSttResult({required this.transcript, this.languageCode});

  final String transcript;
  final String? languageCode;
}

/// REST adapter following Karigar Samarthan's Sarvam integration pattern.
/// The API key is loaded from .env and never embedded in Dart source.
class SarvamService {
  SarvamService()
      : _dio = Dio(
          BaseOptions(
            baseUrl: 'https://api.sarvam.ai',
            connectTimeout: const Duration(seconds: 30),
            receiveTimeout: const Duration(seconds: 60),
          ),
        );

  final Dio _dio;

  String get _apiKey {
    try {
      return dotenv.env['SARVAM_API_KEY'] ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<SarvamSttResult?> speechToText({
    required File audioFile,
    required String languageCode,
  }) async {
    if (_apiKey.isEmpty) return null;
    try {
      final formData = FormData.fromMap({
        'model': 'saaras:v3',
        'mode': 'transcribe',
        'language_code': languageCode,
        'file': await MultipartFile.fromFile(
          audioFile.path,
          filename: 'speech.wav',
        ),
      });
      final response = await _dio.post(
        '/speech-to-text',
        data: formData,
        options: Options(headers: {'api-subscription-key': _apiKey}),
      );
      final transcript = (response.data['transcript'] as String?)?.trim();
      if (transcript == null || transcript.isEmpty) return null;
      return SarvamSttResult(
        transcript: transcript,
        languageCode: response.data['language_code'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  Future<SarvamSttResult?> speechToTextAutoDetect({
    required File audioFile,
    required List<String> candidateLanguageCodes,
  }) async {
    if (_apiKey.isEmpty || candidateLanguageCodes.isEmpty) return null;
    try {
      final formData = FormData.fromMap({
        'model': 'saaras:v3',
        'mode': 'transcribe',
        'language_code': 'unknown',
        'file': await MultipartFile.fromFile(
          audioFile.path,
          filename: 'speech.wav',
        ),
      });
      final response = await _dio.post(
        '/speech-to-text',
        data: formData,
        options: Options(headers: {
          'api-subscription-key': _apiKey,
          'x-candidate-language-codes': candidateLanguageCodes.join(','),
        }),
      );
      final transcript = (response.data['transcript'] as String?)?.trim();
      final languageCode = response.data['language_code'] as String?;
      if (transcript == null ||
          transcript.isEmpty ||
          !candidateLanguageCodes.contains(languageCode)) {
        return null;
      }
      return SarvamSttResult(
        transcript: transcript,
        languageCode: languageCode,
      );
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> textToSpeech({
    required String text,
    required String languageCode,
  }) async {
    if (_apiKey.isEmpty || text.trim().isEmpty) return null;
    try {
      final response = await _dio.post(
        '/text-to-speech',
        data: {
          'text': text.trim().substring(0, text.trim().length.clamp(0, 2500)),
          'target_language_code': languageCode,
          'speaker': languageCode == 'hi-IN' ? 'priya' : 'kavya',
          'model': 'bulbul:v3',
          'pace': 1.0,
        },
        options: Options(headers: {'api-subscription-key': _apiKey}),
      );
      final raw = response.data;
      final body = raw is Map
          ? raw.cast<String, dynamic>()
          : (raw is String
              ? (jsonDecode(raw) as Map).cast<String, dynamic>()
              : null);
      final audios = body?['audios'] as List?;
      if (audios == null || audios.isEmpty) return null;
      return base64Decode(audios.first as String);
    } catch (_) {
      return null;
    }
  }
}
