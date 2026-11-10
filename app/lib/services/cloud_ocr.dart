import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../logic/ocr_flow.dart';
import '../logic/ocr_parser.dart';

class EdgeCloudOcr implements CloudOcrClient {
  EdgeCloudOcr({required this.config, required this.accessToken, http.Client? client}) : _client = client ?? http.Client();

  final AppConfig config;
  final String? Function() accessToken;
  final http.Client _client;

  @override
  Future<CloudOcrResponse> recognize(List<int> imageBytes, {required String mimeType}) async {
    if (!config.hasSupabase) {
      throw StateError('Supabase が未設定です');
    }
    final token = accessToken() ?? '';
    final response = await _client.post(
      Uri.parse('${config.supabaseUrl}/functions/v1/ocr'),
      headers: {
        'Authorization': 'Bearer $token',
        'apikey': config.supabaseAnonKey,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'imageBase64': base64Encode(imageBytes), 'mimeType': mimeType}),
    );
    if (response.statusCode == 501) {
      throw StateError('クラウドOCRが未設定です');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('クラウドOCRに失敗しました (${response.statusCode})');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final fields = json['fields'];
    if (fields is List) {
      return CloudOcrResponse(
        text: json['text'] as String?,
        fields: fields.map((item) {
          final row = item as Map<String, dynamic>;
          return OcrField(
            key: row['key'] as String? ?? 'name',
            label: row['label'] as String? ?? '',
            value: row['value'] as String? ?? '',
            confidence: (row['confidence'] as num?)?.toDouble() ?? 0,
          );
        }).toList(),
      );
    }
    return CloudOcrResponse(text: json['text'] as String?);
  }
}
