import 'package:field_sales/services/geocoder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('国土地理院の結果は経度・緯度の順でピンになる', () {
    const body = '''
[{"geometry":{"coordinates":[139.767242,35.681252],"type":"Point"},"type":"Feature","properties":{"addressCode":"","title":"東京都千代田区丸の内一丁目９番"}}]
''';
    final hits = parseGsiAddressSearch(body, '東京都千代田区丸の内1-9-1');
    expect(hits, hasLength(1));
    expect(hits.single.lng, closeTo(139.767242, 0.000001));
    expect(hits.single.lat, closeTo(35.681252, 0.000001));
    expect(hits.single.formattedAddress, '東京都千代田区丸の内一丁目９番');
  });

  test('CSISのXMLは国土地理院と同じ緯度経度になる', () {
    const body = '''
<?xml version="1.0" encoding="UTF-8" ?>
<results>
<candidate>
<address>東京都/千代田区/丸の内/一丁目/９番</address>
<longitude>139.767242</longitude>
<latitude>35.681252</latitude>
</candidate>
</results>
''';
    final hits = parseCsisGeocode(body, '東京都千代田区丸の内1-9-1');
    expect(hits, hasLength(1));
    expect(hits.single.lat, closeTo(35.681252, 0.000001));
    expect(hits.single.lng, closeTo(139.767242, 0.000001));
    expect(hits.single.formattedAddress, '東京都千代田区丸の内一丁目９番');
  });

  test('逆ジオコードは市区町村と町名をつなぐ', () {
    const source = '''GSI.MUNI_ARRAY["13101"] = '13,東京都,13101,千代田区';''';
    final names = parseGsiMuniScript(source);
    expect(names['13101'], '東京都千代田区');
    expect(
      formatGsiReverseAddress({'results': {'muniCd': '13101', 'lv01Nm': '丸の内一丁目'}}, names),
      '東京都千代田区丸の内一丁目',
    );
    expect(formatGsiReverseAddress({'results': null}, names), isNull);
  });

  test('空や壊れた応答は候補なし', () {
    expect(parseGsiAddressSearch('[]', '住所'), isEmpty);
    expect(parseGsiAddressSearch('{"error":true}', '住所'), isEmpty);
    expect(parseGsiAddressSearch('[{"geometry":{"coordinates":["x",1]}}]', '住所'), isEmpty);
  });
}
