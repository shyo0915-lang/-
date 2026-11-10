import 'package:field_sales/logic/text_parse.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('日本の電話番号を検証しハイフン整形する', () {
    expect(isValidJpPhone('090-0000-1101'), isTrue);
    expect(isValidJpPhone('０９０ー００００ー１１０１'), isTrue);
    expect(formatJpPhone('09000001101'), '090-0000-1101');
    expect(formatJpPhone('03-1234-5678'), '03-1234-5678');
    expect(formatJpPhone('0451234567'), '045-123-4567');
    expect(isValidJpPhone('12345'), isFalse);
    expect(isValidJpPhone('090-000-110'), isFalse);
  });

  test('文章から電話番号を取り出す', () {
    final hit = findPhone('ご連絡は TEL 090-0000-1107 まで');
    expect(hit?.formatted, '090-0000-1107');
    expect(hit!.confidence, greaterThanOrEqualTo(0.9));
  });

  test('和暦と西暦の日付を解釈する', () {
    expect(parseDateToken('令和8年11月10日')?.iso, '2026-11-10');
    expect(parseDateToken('令和元年5月1日')?.iso, '2019-05-01');
    expect(parseDateToken('R8.11.10')?.iso, '2026-11-10');
    expect(parseDateToken('平成31年4月30日')?.iso, '2019-04-30');
    expect(parseDateToken('昭和64年1月7日')?.iso, '1989-01-07');
    expect(parseDateToken('２０２６年１１月１０日')?.iso, '2026-11-10');
    expect(parseDateToken('2026/11/10')?.iso, '2026-11-10');
    expect(parseDateToken('2026-02-31'), isNull);
    expect(findDate('契約日: 令和8年4月1日\n備考')?.iso, '2026-04-01');
  });

  test('円金額を解釈する', () {
    expect(parseYen('¥68,000'), 68000);
    expect(parseYen('６８，０００円'), 68000);
    expect(parseYen('￥240000'), 240000);
    expect(parseYen('0円'), isNull);
    final hit = findYen('電話 090-0000-1101\n契約日 2026-04-01\n単価 240,000円');
    expect(hit?.amount, 240000);
    expect(hit!.confidence, greaterThanOrEqualTo(0.9));
  });

  test('都道府県から住所を取り出す', () {
    final hit = findAddress('住所: 東京都架空区みどり町1-2-3');
    expect(hit?.address, '東京都架空区みどり町1-2-3');
    expect(hit!.confidence, greaterThanOrEqualTo(0.9));
    expect(findAddress('大阪府架空市北区1-1')?.address, contains('大阪府'));
    expect(findAddress('架空区だけ'), isNull);
  });
}
