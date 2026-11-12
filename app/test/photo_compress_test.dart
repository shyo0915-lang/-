import 'dart:typed_data';

import 'package:field_sales/logic/photo_compress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('大きい画像は長辺1600のJPEGになる', () {
    final source = img.Image(width: 2400, height: 1200);
    img.fill(source, color: img.ColorRgb8(30, 90, 200));
    final raw = Uint8List.fromList(img.encodePng(source));
    final jpeg = compressCustomerPhoto(raw);
    expect(jpeg[0], 0xFF);
    expect(jpeg[1], 0xD8);
    final decoded = img.decodeJpg(jpeg);
    expect(decoded, isNotNull);
    expect(decoded!.width, 1600);
    expect(decoded.height, lessThanOrEqualTo(1600));
  });

  test('小さい画像は拡大しない', () {
    final source = img.Image(width: 320, height: 200);
    img.fill(source, color: img.ColorRgb8(10, 10, 10));
    final jpeg = compressCustomerPhoto(Uint8List.fromList(img.encodePng(source)));
    final decoded = img.decodeJpg(jpeg)!;
    expect(decoded.width, 320);
    expect(decoded.height, 200);
  });
}
