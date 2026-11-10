import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// 端末内OCR（ML Kit 日本語）。テストやキー未設定の開発機では失敗を空文字で返す。
Future<String> recognizeJapaneseText(String path) async {
  if (path.isEmpty || !File(path).existsSync()) return '';
  final recognizer = TextRecognizer(script: TextRecognitionScript.japanese);
  try {
    final result = await recognizer.processImage(InputImage.fromFilePath(path));
    return result.text;
  } catch (_) {
    return '';
  } finally {
    await recognizer.close();
  }
}
