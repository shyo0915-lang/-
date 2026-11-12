import 'dart:typed_data';

import 'mlkit_text_io.dart' if (dart.library.html) 'mlkit_text_web.dart' as impl;

Future<String> recognizeJapaneseText(Uint8List bytes, {String? path}) {
  return impl.recognizeJapaneseText(bytes, path: path);
}
