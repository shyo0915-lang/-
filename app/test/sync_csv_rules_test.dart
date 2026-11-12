import 'package:field_sales/logic/cluster.dart';
import 'package:field_sales/logic/csv_customers.dart';
import 'package:field_sales/logic/geo.dart';
import 'package:field_sales/logic/price_tiers.dart';
import 'package:field_sales/logic/status_rules.dart';
import 'package:field_sales/logic/sync_merge.dart';
import 'package:field_sales/logic/validators.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> baseRow() => {
  'name': '青葉工務店',
  'phone': '090-0000-1101',
  'address': '東京都架空区みどり町1-2-3',
  'memo': '屋根',
  'statusId': 'active',
  'lat': 35.68,
  'lng': 139.76,
  'locationSource': 'geocoded',
  'contractDate': '2026-04-01',
  'unitPrice': 240000,
};

void main() {
  test('別項目の同時編集はマージし、同じ項目はサーバーを残して競合にする', () {
    final base = baseRow();
    final local = {...base, 'memo': '屋根の見積を持参', 'unitPrice': 250000};
    final server = {...base, 'unitPrice': 260000, 'phone': '090-0000-1199'};
    final merged = mergeCustomerFields(base: base, local: local, server: server);
    expect(merged.merged['memo'], '屋根の見積を持参');
    expect(merged.merged['phone'], '090-0000-1199');
    expect(merged.merged['unitPrice'], 260000);
    expect(merged.conflicts.map((conflict) => conflict.field), ['unitPrice']);
    expect(merged.conflicts.single.deviceValue, 250000);
    expect(merged.conflicts.single.serverValue, 260000);
  });

  test('手動ピンは後からジオコーディングしても上書きしない', () {
    final base = baseRow();
    final local = {...base, 'lat': 35.70, 'lng': 139.80, 'locationSource': 'manual'};
    final server = {...base, 'lat': 35.00, 'lng': 139.00, 'locationSource': 'geocoded'};
    final merged = mergeCustomerFields(base: base, local: local, server: server);
    expect(merged.merged['locationSource'], 'manual');
    expect(merged.merged['lat'], 35.70);
    expect(merged.conflicts, isEmpty);
  });

  test('200m以上離れた手動ピンは確認が必要', () {
    expect(
      shouldAskLocationChoice(manualLat: 35.681, manualLng: 139.767, geocodedLat: 35.6812, geocodedLng: 139.7672),
      isFalse,
    );
    expect(
      shouldAskLocationChoice(manualLat: 35.681, manualLng: 139.767, geocodedLat: 35.690, geocodedLng: 139.790),
      isTrue,
    );
  });

  test('精度50mは地図の縮尺でピクセル半径になる', () {
    expect(accuracyRadiusPixels(meters: 0, pixelsPerDegree: 14000), 0);
    expect(accuracyRadiusPixels(meters: 50, pixelsPerDegree: 14000), closeTo(50 * 14000 / 111320, 0.01));
  });

  test('単価帯の初期値と検証', () {
    const tiers = PriceTierConfig.defaults;
    expect(tiers.tierOf(49999), 0);
    expect(tiers.tierOf(50000), 1);
    expect(tiers.tierOf(200000), 2);
    expect(pinDiameterForTier(0), lessThan(pinDiameterForTier(2)));
    expect(const PriceTierConfig([200000, 50000]).validate(), isNotNull);
    expect(const PriceTierConfig([1000]).validate(), isNull);
    expect(const PriceTierConfig([1, 2, 3, 4, 5]).validate(), isNotNull);
  });

  test('ステータスは10個まで、色と形の重複を拒む', () {
    final existing = List.generate(
      4,
      (index) => CustomerStatus(
        id: '$index',
        label: 's$index',
        colorHex: statusPalette[index],
        shape: statusShapes[index],
        sortOrder: index,
        isDefault: true,
        hidden: false,
      ),
    );
    expect(
      validateStatusEdit(
        existing,
        const CustomerStatus(
          id: 'new',
          label: '要注意',
          colorHex: '#1A73E8',
          shape: 'check',
          sortOrder: 4,
          isDefault: false,
          hidden: false,
        ),
      ),
      '同じ色と形の組み合わせは使えません',
    );
    final full = [...existing, ...List.generate(6, (index) => CustomerStatus(
      id: 'c$index',
      label: '追加$index',
      colorHex: statusPalette[(index + 4) % statusPalette.length],
      shape: statusShapes[(index + 2) % statusShapes.length],
      sortOrder: 10 + index,
      isDefault: false,
      hidden: false,
    ))];
    // 色と形が既存と被らないよう最後の1件だけを検査する。10件ちょうどなら追加不可。
    expect(full.length, 10);
    expect(
      validateStatusEdit(
        full,
        const CustomerStatus(
          id: 'overflow',
          label: '十一',
          colorHex: '#112233',
          shape: 'square',
          sortOrder: 11,
          isDefault: false,
          hidden: false,
        ),
      ),
      'ステータスは10個までです',
    );
  });

  test('顧客入力の検証とメモの抜粋', () {
    final bad = validateCustomer(
      const CustomerDraft(name: '', phone: '123', address: '', memo: '', contractDate: '', price: 0, statusId: ''),
    );
    expect(bad.errors['name'], '顧客名を入力してください');
    expect(bad.errors['phone'], contains('10'));
    expect(bad.errors['price'], '1円以上で入力してください');
    final future = validateCustomer(
      const CustomerDraft(
        name: '青葉',
        phone: '090-0000-1101',
        address: '東京都架空区1-2-3',
        memo: '一行目\n二行目の長いメモです',
        contractDate: '2027-01-01',
        price: 1000,
        statusId: 'active',
      ),
      today: DateTime(2026, 11, 10),
    );
    expect(future.ok, isTrue);
    expect(future.warnings, ['未来の日付です']);
    expect(memoExcerpt('一行目\n二行目の長いメモです'), '一行目 二行目の長いメモです');
  });

  test('CSVはメモのカンマと改行を往復できる', () {
    const row = CsvCustomerRow(
      id: '1',
      name: '青葉工務店',
      phone: '090-0000-1101',
      address: '東京都架空区みどり町1-2-3',
      memo: '見積, "特急"\n午前中',
      contractDate: '2026-04-01',
      unitPrice: 240000,
      status: '契約中',
      ownerName: '山田 太郎',
      lat: 35.68,
      lng: 139.76,
    );
    final csv = exportCustomersCsv([row]);
    final parsed = importCustomersCsv(csv);
    expect(parsed.ok, isTrue);
    expect(parsed.rows.single.memo, row.memo);
    expect(parsed.rows.single.unitPrice, 240000);
    final missing = importCustomersCsv('name,phone,address\n青葉,,東京都架空区1-2-3\n');
    expect(missing.rows, isEmpty);
    expect(missing.errors, isNotEmpty);
  });

  test('近いピンはクラスタになる', () {
    final clusters = clusterPins(const [
      PinPos('a', 0, 0),
      PinPos('b', 10, 10),
      PinPos('c', 200, 0),
    ]);
    expect(clusters.length, 2);
    expect(clusters.first.ids, ['a', 'b']);
    expect(clusters.last.isCluster, isFalse);
  });
}
