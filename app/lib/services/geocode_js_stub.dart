class BrowserGeoHit {
  const BrowserGeoHit(this.lat, this.lng, this.formattedAddress);
  final double lat;
  final double lng;
  final String formattedAddress;
}

Future<List<BrowserGeoHit>> geocodeWithMapsJs(String address) async => const [];
