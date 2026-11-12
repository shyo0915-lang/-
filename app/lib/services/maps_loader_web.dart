import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<void> prepareGoogleMaps(String apiKey) async {
  if (apiKey.isEmpty || web.document.getElementById('google-maps-js') != null) return;
  final done = Completer<void>();
  final script = web.HTMLScriptElement()
    ..id = 'google-maps-js'
    ..src = 'https://maps.googleapis.com/maps/api/js?key=$apiKey'
    ..async = false
    ..defer = true;
  script.addEventListener(
    'load',
    ((web.Event _) {
      if (!done.isCompleted) done.complete();
    }).toJS,
  );
  script.addEventListener(
    'error',
    ((web.Event _) {
      if (!done.isCompleted) done.complete();
    }).toJS,
  );
  web.document.head!.append(script);
  await done.future.timeout(const Duration(seconds: 20), onTimeout: () {});
}
