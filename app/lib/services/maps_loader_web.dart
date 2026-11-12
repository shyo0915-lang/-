import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

bool _ready = false;
String? _mapsError;

bool get googleMapsAvailable => _ready;

String? get googleMapsError => _mapsError;

/// Maps JavaScript API を読み込む。認証エラーなら false。
Future<bool> prepareGoogleMaps(String apiKey) async {
  if (apiKey.isEmpty) return false;
  if (web.document.getElementById('google-maps-js') != null && _ready) return true;
  final done = Completer<void>();
  web.window.setProperty(
    'gm_authFailure'.toJS,
    (() {
      _mapsError = 'Google Maps authentication failed';
      _ready = false;
      web.window.setProperty('__mapsAuthFailed'.toJS, true.toJS);
      if (!done.isCompleted) done.complete();
    }).toJS,
  );
  web.window.setProperty(
    '__mapsReady'.toJS,
    (() {
      if (!done.isCompleted) done.complete();
    }).toJS,
  );
  final script = web.HTMLScriptElement()
    ..id = 'google-maps-js'
    ..async = true
    ..src = 'https://maps.googleapis.com/maps/api/js?key=$apiKey&v=weekly&loading=async&callback=__mapsReady';
  script.addEventListener(
    'error',
    ((web.Event _) {
      _mapsError = 'Google Maps script failed to load';
      if (!done.isCompleted) done.complete();
    }).toJS,
  );
  web.document.head!.append(script);
  await done.future.timeout(const Duration(seconds: 20), onTimeout: () {
    _mapsError ??= 'Google Maps timed out';
  });
  final failed = web.window.getProperty('__mapsAuthFailed'.toJS)?.dartify() == true;
  _ready = !failed && _mapsError == null;
  return _ready;
}

bool mapsErrorOnPage() {
  if (web.window.getProperty('__mapsAuthFailed'.toJS)?.dartify() == true) return true;
  final box = web.document.querySelector('.gm-err-container');
  if (box == null) return false;
  final text = box.textContent?.trim() ?? '';
  if (text.isNotEmpty) _mapsError = text;
  return true;
}
