import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// 端末内OCR（ML Kit 日本語）。失敗したときは空文字を返し、画面側で手入力にする。
Future<String> recognizeJapaneseText(Uint8List bytes, {String? path}) async {
  if (path == null || path.isEmpty || !File(path).existsSync()) return '';
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
