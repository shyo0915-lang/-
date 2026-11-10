import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 契約書画像をアプリ専用領域に AES で保存する。カメラロールには残さない。
/// 鍵は端末内の共有設定に置く暫定実装で、本番はハードウェア鍵保管に置き換える。
class ImageVault {
  static const _keyName = 'image_vault_key';

  Future<String> save(Uint8List bytes) async {
    final dir = await _directory();
    final key = await _key();
    final iv = enc.IV.fromSecureRandom(16);
    final encrypted = enc.Encrypter(enc.AES(key)).encryptBytes(bytes, iv: iv);
    final file = File(p.join(dir.path, '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}.bin'));
    final payload = Uint8List(iv.bytes.length + encrypted.bytes.length);
    payload.setRange(0, iv.bytes.length, iv.bytes);
    payload.setRange(iv.bytes.length, payload.length, encrypted.bytes);
    await file.writeAsBytes(payload, flush: true);
    return file.path;
  }

  Future<Uint8List?> read(String path) async {
    final file = File(path);
    if (!file.existsSync()) return null;
    final payload = await file.readAsBytes();
    if (payload.length <= 16) return null;
    final iv = enc.IV(Uint8List.sublistView(payload, 0, 16));
    final cipher = enc.Encrypted(Uint8List.sublistView(payload, 16));
    final plain = enc.Encrypter(enc.AES(await _key())).decryptBytes(cipher, iv: iv);
    return Uint8List.fromList(plain);
  }

  Future<Directory> _directory() async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory(p.join(root.path, 'contracts'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  Future<enc.Key> _key() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_keyName);
    if (existing != null && existing.isNotEmpty) return enc.Key.fromBase64(existing);
    final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    final encoded = base64Encode(bytes);
    await prefs.setString(_keyName, encoded);
    return enc.Key.fromBase64(encoded);
  }
}
