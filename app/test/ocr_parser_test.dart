import 'package:field_sales/logic/ocr_flow.dart';
import 'package:field_sales/logic/ocr_parser.dart';
import 'package:flutter_test/flutter_test.dart';

const template = '''
契約書 FMT:CONTRACT-V1
顧客名: （サンプル）みなと珈琲店
住所: 東京都架空区港南3-4-5
電話: 090-0000-1107
契約日: 令和8年11月10日
単価: 68,000円
''';

const handwritten = '''
みなと珈琲店
東京都架空区港南3-4-5
090-0000-1107
令和8年11月10日
68000円
''';

void main() {
  test('定型書式は見出しから5項目を高信頼度で読む', () {
    expect(OcrParser.looksLikeTemplate(template), isTrue);
    final fields = OcrParser.parse(template);
    expect(fields.map((field) => field.key), ['name', 'address', 'phone', 'date', 'price']);
    expect(fields[0].value, '（サンプル）みなと珈琲店');
    expect(fields[1].value, '東京都架空区港南3-4-5');
    expect(fields[2].value, '090-0000-1107');
    expect(fields[3].value, '2026-11-10');
    expect(fields[4].value, '68000');
    expect(fields.every((field) => field.confidence >= 0.9), isTrue);
    expect(fields.every((field) => !field.blocksSave), isTrue);
  });

  test('手書き相当の本文は低信頼度の項目が要確認になる', () {
    expect(OcrParser.looksLikeTemplate(handwritten), isFalse);
    final fields = OcrParser.parse(handwritten, format: 'handwritten');
    final byKey = {for (final field in fields) field.key: field};
    expect(byKey['name']!.value, 'みなと珈琲店');
    expect(byKey['name']!.blocksSave, isTrue);
    expect(byKey['phone']!.value, '090-0000-1107');
    expect(byKey['phone']!.blocksSave, isTrue);
    expect(byKey['price']!.value, '68000');
  });

  test('信頼度70%未満は空欄扱いにし候補を残す', () {
    final fields = OcrParser.parse('電話: 123\n顧客名: 青葉工務店\n住所: 東京都架空区1-2\n契約日: 2026-01-01\n単価: abc');
    final phone = fields.firstWhere((field) => field.key == 'phone');
    final price = fields.firstWhere((field) => field.key == 'price');
    expect(phone.value, isEmpty);
    expect(phone.hint, isNotEmpty);
    expect(phone.blocksSave, isTrue);
    expect(price.value, isEmpty);
  });

  test('手書きでオフラインならクラウドを待たずに端末内結果を返す', () async {
    final result = await runOcr(onDeviceText: handwritten, formatChoice: 'auto', online: false);
    expect(result.format, 'handwritten');
    expect(result.queuedCloud, isTrue);
    expect(result.usedCloud, isFalse);
    expect(result.fields.first.value, 'みなと珈琲店');
  });

  test('手書きでオンラインならクラウド結果を優先する', () async {
    final result = await runOcr(
      onDeviceText: '読めない',
      formatChoice: 'handwritten',
      online: true,
      imageBytes: [1, 2, 3],
      cloud: _FakeCloud(),
    );
    expect(result.usedCloud, isTrue);
    expect(result.fields.firstWhere((field) => field.key == 'name').value, 'クラウド商事');
  });

  test('確認済みにすると要確認が解消される', () {
    final field = const OcrField(key: 'phone', label: '電話番号', value: '090-0000-1107', confidence: 0.8);
    expect(field.blocksSave, isTrue);
    expect(field.copyWith(confirmed: true).blocksSave, isFalse);
  });
}

class _FakeCloud implements CloudOcrClient {
  @override
  Future<CloudOcrResponse> recognize(List<int> imageBytes, {required String mimeType}) async {
    return CloudOcrResponse(
      fields: const [
        OcrField(key: 'name', label: '顧客名', value: 'クラウド商事', confidence: 0.91),
        OcrField(key: 'address', label: '住所', value: '東京都架空区1-1', confidence: 0.91),
        OcrField(key: 'phone', label: '電話番号', value: '090-0000-2222', confidence: 0.91),
        OcrField(key: 'date', label: '契約日', value: '2026-11-10', confidence: 0.91),
        OcrField(key: 'price', label: '単価（1回）', value: '12000', confidence: 0.91),
      ],
    );
  }
}
