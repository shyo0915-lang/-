import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

@JS('Tesseract.createWorker')
external JSPromise<JSObject> _createWorker(JSString language);

extension type _Worker._(JSObject _) implements JSObject {
  external JSPromise<JSObject> recognize(JSString imageUrl);
  external JSPromise<JSAny?> terminate();
}

extension type _RecognizeResult._(JSObject _) implements JSObject {
  external _RecognizeData get data;
}

extension type _RecognizeData._(JSObject _) implements JSObject {
  external String get text;
}

/// ブラウザ上の日本語OCR（tesseract.js）。読めないときは空文字を返し、手入力に回す。
Future<String> recognizeJapaneseText(Uint8List bytes, {String? path}) async {
  if (bytes.isEmpty) return '';
  String? url;
  try {
    await _ensureTesseract();
    final worker = _Worker._(await _createWorker('jpn'.toJS).toDart);
    final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: 'image/jpeg'));
    url = web.URL.createObjectURL(blob);
    final result = _RecognizeResult._(await worker.recognize(url.toJS).toDart);
    await worker.terminate().toDart;
    return result.data.text;
  } catch (_) {
    return '';
  } finally {
    if (url != null) web.URL.revokeObjectURL(url);
  }
}

Future<void> _ensureTesseract() async {
  if (_scriptReady) return;
  final existing = web.document.getElementById('tesseract-js');
  if (existing != null) {
    _scriptReady = true;
    return;
  }
  final done = Completer<void>();
  final script = web.HTMLScriptElement()
    ..id = 'tesseract-js'
    ..src = 'https://cdn.jsdelivr.net/npm/tesseract.js@5.1.1/dist/tesseract.min.js'
    ..async = true;
  script.addEventListener(
    'load',
    ((web.Event _) {
      if (!done.isCompleted) done.complete();
    }).toJS,
  );
  script.addEventListener(
    'error',
    ((web.Event _) {
      if (!done.isCompleted) done.completeError(StateError('tesseract.js を読み込めませんでした'));
    }).toJS,
  );
  web.document.head!.append(script);
  await done.future.timeout(const Duration(seconds: 40));
  _scriptReady = true;
}

bool _scriptReady = false;
