import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'geocode_js.dart';

class GeoHit {
  const GeoHit(this.lat, this.lng, this.formattedAddress);
  final double lat;
  final double lng;
  final String formattedAddress;
}

/// 国土地理院の住所検索。`coordinates` は [経度, 緯度]。
List<GeoHit> parseGsiAddressSearch(String body, String fallbackAddress) {
  final decoded = jsonDecode(body);
  if (decoded is! List) return const [];
  final hits = <GeoHit>[];
  for (final item in decoded.take(5)) {
    if (item is! Map) continue;
    final geometry = item['geometry'];
    if (geometry is! Map) continue;
    final coordinates = geometry['coordinates'];
    if (coordinates is! List || coordinates.length < 2) continue;
    final lng = coordinates[0];
    final lat = coordinates[1];
    if (lng is! num || lat is! num) continue;
    final properties = item['properties'];
    final title = properties is Map ? properties['title'] : null;
    final label = title is String && title.trim().isNotEmpty ? title.trim() : fallbackAddress;
    hits.add(GeoHit(lat.toDouble(), lng.toDouble(), label));
  }
  return hits;
}

/// 国土地理院が参照している東京大学CSISシンプルジオコーディング。
List<GeoHit> parseCsisGeocode(String body, String fallbackAddress) {
  final hits = <GeoHit>[];
  for (final match in RegExp(r'<candidate>([\s\S]*?)</candidate>').allMatches(body).take(5)) {
    final block = match.group(1) ?? '';
    final lng = double.tryParse(RegExp(r'<longitude>([^<]+)</longitude>').firstMatch(block)?.group(1)?.trim() ?? '');
    final lat = double.tryParse(RegExp(r'<latitude>([^<]+)</latitude>').firstMatch(block)?.group(1)?.trim() ?? '');
    if (lat == null || lng == null) continue;
    final raw = RegExp(r'<address>([^<]*)</address>').firstMatch(block)?.group(1)?.trim() ?? '';
    hits.add(GeoHit(lat, lng, raw.isEmpty ? fallbackAddress : raw.replaceAll('/', '')));
  }
  return hits;
}

/// 国土地理院の市区町村コード表。`13,東京都,13101,千代田区` を都道府県＋市区町村にする。
Map<String, String> parseGsiMuniScript(String source) {
  final names = <String, String>{};
  for (final match in RegExp('\\["(\\d+)"\\]\\s*=\\s*\'([^\']*)\'').allMatches(source)) {
    final parts = (match.group(2) ?? '').split(',');
    if (parts.length < 4) continue;
    names[match.group(1)!] = '${parts[1]}${parts[3]}';
  }
  return names;
}

/// 逆ジオコーダーの応答と市区町村名から、番地のない住所を作る。
String? formatGsiReverseAddress(Object? json, Map<String, String> municipalities) {
  if (json is! Map) return null;
  final results = json['results'];
  if (results is! Map) return null;
  final code = results['muniCd']?.toString() ?? '';
  final town = (results['lv01Nm'] as String?)?.trim() ?? '';
  final text = '${municipalities[code] ?? ''}$town'.trim();
  return text.isEmpty ? null : text;
}

abstract class Geocoder {
  Future<List<GeoHit>> geocode(String address);
  Future<List<String>> suggest(String input);
  Future<String?> reverseGeocode(double lat, double lng) async => null;
}

class RoutingGeocoder implements Geocoder {
  RoutingGeocoder({required this.config, http.Client? client, this.accessToken}) : _client = client ?? http.Client();

  final AppConfig config;
  final http.Client _client;
  final String? Function()? accessToken;
  Map<String, String>? _municipalities;

  @override
  Future<List<GeoHit>> geocode(String address) async {
    final query = address.trim();
    if (query.isEmpty) return const [];
    final fromGsi = await _geocodeViaGsi(query);
    if (fromGsi != null) return fromGsi;
    final fromCsis = await _geocodeViaCsis(query);
    if (fromCsis.isNotEmpty) return fromCsis;
    try {
      final browserHits = await geocodeWithMapsJs(query);
      if (browserHits.isNotEmpty) {
        return browserHits.map((hit) => GeoHit(hit.lat, hit.lng, hit.formattedAddress)).toList();
      }
    } catch (_) {}
    if (config.hasSupabase) {
      final fromEdge = await _geocodeViaEdge(query);
      if (fromEdge != null) return fromEdge;
    }
    if (config.geocodingKey.isEmpty) return const [];
    final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
      'address': query,
      'language': 'ja',
      'region': 'jp',
      'key': config.geocodingKey,
    });
    try {
      final response = await _client.get(uri);
      if (response.statusCode != 200) return const [];
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final results = (json['results'] as List?) ?? const [];
      return results.take(5).map((item) {
        final row = item as Map<String, dynamic>;
        final location = (row['geometry'] as Map)['location'] as Map;
        return GeoHit((location['lat'] as num).toDouble(), (location['lng'] as num).toDouble(), row['formatted_address'] as String? ?? query);
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  /// 成功時は候補（0件を含む）。通信失敗やHTMLエラーのときは null。
  Future<List<GeoHit>?> _geocodeViaGsi(String address) async {
    final uri = Uri.https('msearch.gsi.go.jp', '/address-search/AddressSearch', {'q': address});
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 8));
      final body = response.body.trimLeft();
      if (response.statusCode != 200 || !body.startsWith('[')) return null;
      return parseGsiAddressSearch(body, address);
    } catch (_) {
      return null;
    }
  }

  /// 緯度経度から町名まで。失敗したら null（住所は空欄のまま）。
  @override
  Future<String?> reverseGeocode(double lat, double lng) async {
    const hosts = ['mreversegeo.gsi.go.jp', 'mreversegeocoder.gsi.go.jp'];
    for (final host in hosts) {
      try {
        final uri = Uri.https(host, '/reverse-geocoder/LonLatToAddress', {'lat': '$lat', 'lon': '$lng'});
        final response = await _client.get(uri).timeout(const Duration(seconds: 4));
        if (response.statusCode != 200 || !response.body.trimLeft().startsWith('{')) continue;
        final names = await _loadMunicipalities();
        final address = formatGsiReverseAddress(jsonDecode(response.body), names);
        if (address != null) return address;
      } catch (_) {}
    }
    return null;
  }

  Future<Map<String, String>> _loadMunicipalities() async {
    final cached = _municipalities;
    if (cached != null) return cached;
    try {
      final response = await _client.get(Uri.parse('https://maps.gsi.go.jp/js/muni.js')).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        _municipalities = parseGsiMuniScript(response.body);
        return _municipalities!;
      }
    } catch (_) {}
    return _municipalities = const {};
  }

  Future<List<GeoHit>> _geocodeViaCsis(String address) async {
    final uri = Uri.https('geocode.csis.u-tokyo.ac.jp', '/cgi-bin/simple_geocode.cgi', {'charset': 'UTF8', 'addr': address});
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return const [];
      return parseCsisGeocode(response.body, address);
    } catch (_) {
      return const [];
    }
  }

  Future<List<GeoHit>?> _geocodeViaEdge(String address) async {
    final token = accessToken?.call();
    if (token == null || token.isEmpty) return null;
    try {
      final response = await _client.post(
        Uri.parse('${config.supabaseUrl}/functions/v1/geocode'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json', 'apikey': config.supabaseAnonKey},
        body: jsonEncode({'address': address}),
      );
      if (response.statusCode == 501) return const [];
      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final results = (json['results'] as List?) ?? const [];
      return results.map((item) {
        final row = item as Map<String, dynamic>;
        return GeoHit((row['lat'] as num).toDouble(), (row['lng'] as num).toDouble(), row['formattedAddress'] as String? ?? address);
      }).toList();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<String>> suggest(String input) async {
    final query = input.trim();
    if (query.length < 2 || config.geocodingKey.isEmpty) return const [];
    final uri = Uri.https('maps.googleapis.com', '/maps/api/place/autocomplete/json', {
      'input': query,
      'language': 'ja',
      'components': 'country:jp',
      'key': config.geocodingKey,
    });
    try {
      final response = await _client.get(uri);
      if (response.statusCode != 200) return const [];
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final predictions = (json['predictions'] as List?) ?? const [];
      return predictions.take(5).map((item) => (item as Map)['description'] as String).toList();
    } catch (_) {
      return const [];
    }
  }
}
