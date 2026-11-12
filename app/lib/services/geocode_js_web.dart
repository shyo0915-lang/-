import 'dart:js_interop';

import 'maps_loader_web.dart';

class BrowserGeoHit {
  const BrowserGeoHit(this.lat, this.lng, this.formattedAddress);
  final double lat;
  final double lng;
  final String formattedAddress;
}

@JS('google.maps.Geocoder')
extension type _Geocoder._(JSObject _) implements JSObject {
  external factory _Geocoder();
  external JSPromise<JSObject> geocode(JSObject request);
}

extension type _GeocodeResponse._(JSObject _) implements JSObject {
  external JSArray<_GeocodeResult> get results;
}

extension type _GeocodeResult._(JSObject _) implements JSObject {
  @JS('formatted_address')
  external String get formattedAddress;
  external _Geometry get geometry;
}

extension type _Geometry._(JSObject _) implements JSObject {
  external _LatLng get location;
}

extension type _LatLng._(JSObject _) implements JSObject {
  external double lat();
  external double lng();
}

/// Maps JavaScript API の Geocoder。ブラウザ用キーのまま住所を緯度経度にする。
Future<List<BrowserGeoHit>> geocodeWithMapsJs(String address) async {
  final query = address.trim();
  if (query.isEmpty || !googleMapsAvailable) return const [];
  try {
    final geocoder = _Geocoder();
    final request = <String, String>{'address': query, 'region': 'jp', 'language': 'ja'}.jsify()! as JSObject;
    final response = _GeocodeResponse._(await geocoder.geocode(request).toDart);
    final hits = <BrowserGeoHit>[];
    final results = response.results.toDart;
    for (final result in results.take(5)) {
      final location = result.geometry.location;
      hits.add(BrowserGeoHit(location.lat(), location.lng(), result.formattedAddress));
    }
    return hits;
  } catch (_) {
    return const [];
  }
}
