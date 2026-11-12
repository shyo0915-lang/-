import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;

const vaultKeyName = 'image_vault_key';

Uint8List encryptPayload(Uint8List bytes, enc.Key key) {
  final iv = enc.IV.fromSecureRandom(16);
  final encrypted = enc.Encrypter(enc.AES(key)).encryptBytes(bytes, iv: iv);
  final payload = Uint8List(iv.bytes.length + encrypted.bytes.length);
  payload.setRange(0, iv.bytes.length, iv.bytes);
  payload.setRange(iv.bytes.length, payload.length, encrypted.bytes);
  return payload;
}

Uint8List? decryptPayload(Uint8List payload, enc.Key key) {
  if (payload.length <= 16) return null;
  final iv = enc.IV(Uint8List.sublistView(payload, 0, 16));
  final cipher = enc.Encrypted(Uint8List.sublistView(payload, 16));
  final plain = enc.Encrypter(enc.AES(key)).decryptBytes(cipher, iv: iv);
  return Uint8List.fromList(plain);
}
