import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:sembast_web/sembast_web.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:encrypt/encrypt.dart' as enc;

import 'image_vault_codec.dart';

/// 契約書画像を IndexedDB に暗号化して保存する。カメラロールには残さない。
class ImageVault {
  static final _store = stringMapStoreFactory.store('contract_images');

  Future<String> save(Uint8List bytes) async {
    final db = await databaseFactoryWeb.openDatabase('field_sales');
    final id = 'idb-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}';
    final payload = encryptPayload(bytes, await _key());
    await _store.record(id).put(db, {'payload': base64Encode(payload)});
    return id;
  }

  Future<Uint8List?> read(String path) async {
    if (!path.startsWith('idb-')) return null;
    final db = await databaseFactoryWeb.openDatabase('field_sales');
    final row = await _store.record(path).get(db);
    final encoded = row?['payload'] as String?;
    if (encoded == null) return null;
    return decryptPayload(base64Decode(encoded), await _key());
  }

  Future<enc.Key> _key() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(vaultKeyName);
    if (existing != null && existing.isNotEmpty) return enc.Key.fromBase64(existing);
    final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    final encoded = base64Encode(bytes);
    await prefs.setString(vaultKeyName, encoded);
    return enc.Key.fromBase64(encoded);
  }
}
