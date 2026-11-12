import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 長辺1600px、JPEG品質70に縮める。これ以上小さくしない。
Uint8List compressCustomerPhoto(Uint8List bytes, {int maxSide = 1600, int quality = 70}) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  var image = decoded;
  final longest = image.width > image.height ? image.width : image.height;
  if (longest > maxSide) {
    if (image.width >= image.height) {
      image = img.copyResize(image, width: maxSide);
    } else {
      image = img.copyResize(image, height: maxSide);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: quality));
}
