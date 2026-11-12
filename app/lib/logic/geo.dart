import 'dart:math' as math;

/// 緯度1度を約111.32kmとして、精度円の半径を画面上のピクセルにする。
double accuracyRadiusPixels({required double meters, required double pixelsPerDegree}) {
  const metersPerDegree = 111320.0;
  if (meters <= 0 || pixelsPerDegree <= 0) return 0;
  return meters * pixelsPerDegree / metersPerDegree;
}

double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
  const earth = 6371000.0;
  double rad(double degree) => degree * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return earth * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

bool shouldAskLocationChoice({
  required double manualLat,
  required double manualLng,
  required double geocodedLat,
  required double geocodedLng,
  double thresholdMeters = 200,
}) {
  return distanceMeters(manualLat, manualLng, geocodedLat, geocodedLng) >= thresholdMeters;
}
