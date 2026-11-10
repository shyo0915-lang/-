import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'image_vault_codec.dart';

/// 契約書画像をアプリ専用領域に AES で保存する。カメラロールには残さない。
class ImageVault {
  Future<String> save(Uint8List bytes) async {
    final dir = await _directory();
    final payload = encryptPayload(bytes, await vaultKey());
    final file = File(p.join(dir.path, '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}.bin'));
    await file.writeAsBytes(payload, flush: true);
    return file.path;
  }

  Future<Uint8List?> read(String path) async {
    final file = File(path);
    if (!file.existsSync()) return null;
    final payload = await file.readAsBytes();
    return decryptPayload(payload, await vaultKey());
  }

  Future<Directory> _directory() async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory(p.join(root.path, 'contracts'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }
}

Future<enc.Key> vaultKey() async {
  final prefs = await SharedPreferences.getInstance();
  final existing = prefs.getString(vaultKeyName);
  if (existing != null && existing.isNotEmpty) return enc.Key.fromBase64(existing);
  final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
  final encoded = base64Encode(bytes);
  await prefs.setString(vaultKeyName, encoded);
  return enc.Key.fromBase64(encoded);
}
