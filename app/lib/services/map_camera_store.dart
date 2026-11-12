import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../logic/map_camera.dart';

class MapCameraStore {
  static const _key = 'map_camera_v1';

  static Future<MapCamera?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return MapCamera.parse(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(MapCamera camera) async {
    if (!camera.sensible) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(camera.toJson()));
  }
}
