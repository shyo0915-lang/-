import 'dart:math' as math;

class MapCamera {
  const MapCamera(this.lat, this.lng, this.zoom);

  final double lat;
  final double lng;
  final double zoom;

  static const initial = MapCamera(35.682, 139.772, 15);
  static const streetZoom = 16.5;

  bool get sensible => zoom >= 10 && zoom <= 20 && lat >= -85 && lat <= 85 && lng >= -180 && lng <= 180;

  Map<String, Object> toJson() => {'lat': lat, 'lng': lng, 'zoom': zoom};

  static MapCamera? parse(Object? json) {
    if (json is! Map) return null;
    final lat = json['lat'];
    final lng = json['lng'];
    final zoom = json['zoom'];
    if (lat is! num || lng is! num || zoom is! num) return null;
    final camera = MapCamera(lat.toDouble(), lng.toDouble(), zoom.toDouble());
    return camera.sensible ? camera : null;
  }
}

double fallbackScaleForZoom(double zoom) => 256 * math.pow(2, zoom) / 360;

double zoomForFallbackScale(double scale) {
  if (scale <= 0) return MapCamera.initial.zoom;
  return math.log(scale * 360 / 256) / math.ln2;
}

/// ピン全体が見える縮尺。離れすぎているときはズーム14より引かない。
MapCamera? fitPins(List<({double lat, double lng})> points) {
  if (points.isEmpty) return null;
  if (points.length == 1) return MapCamera(points.first.lat, points.first.lng, 16);
  var minLat = points.first.lat;
  var maxLat = points.first.lat;
  var minLng = points.first.lng;
  var maxLng = points.first.lng;
  for (final point in points) {
    minLat = math.min(minLat, point.lat);
    maxLat = math.max(maxLat, point.lat);
    minLng = math.min(minLng, point.lng);
    maxLng = math.max(maxLng, point.lng);
  }
  final latSpan = math.max(maxLat - minLat, 0.0008);
  final lngSpan = math.max(maxLng - minLng, 0.0008);
  final span = math.max(latSpan, lngSpan);
  final zoom = zoomForFallbackScale(520 / span).clamp(14.0, 17.0);
  return MapCamera((minLat + maxLat) / 2, (minLng + maxLng) / 2, zoom);
}
