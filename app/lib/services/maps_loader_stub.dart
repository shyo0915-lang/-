bool _ready = false;

bool get googleMapsAvailable => _ready;

String? get googleMapsError => null;

Future<bool> prepareGoogleMaps(String apiKey) async {
  _ready = apiKey.isNotEmpty;
  return _ready;
}

bool mapsErrorOnPage() => false;
