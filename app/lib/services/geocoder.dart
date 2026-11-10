import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';

class GeoHit {
  const GeoHit(this.lat, this.lng, this.formattedAddress);
  final double lat;
  final double lng;
  final String formattedAddress;
}

abstract class Geocoder {
  Future<List<GeoHit>> geocode(String address);
  Future<List<String>> suggest(String input);
}

class RoutingGeocoder implements Geocoder {
  RoutingGeocoder({required this.config, http.Client? client, this.accessToken}) : _client = client ?? http.Client();

  final AppConfig config;
  final http.Client _client;
  final String? Function()? accessToken;

  @override
  Future<List<GeoHit>> geocode(String address) async {
    final query = address.trim();
    if (query.isEmpty) return const [];
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
