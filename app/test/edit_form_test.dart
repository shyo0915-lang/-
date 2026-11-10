import 'package:field_sales/logic/status_rules.dart';
import 'package:field_sales/logic/validators.dart';
import 'package:field_sales/ui/edit_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('空の顧客名では保存できず、メモ欄がある', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    CustomerDraft? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomerEditForm(
            initial: const CustomerDraft(name: '', phone: '', address: '', memo: '', contractDate: '', price: 0, statusId: 's1'),
            statuses: const [
              CustomerStatus(id: 's1', label: '契約中', colorHex: '#1A73E8', shape: 'check', sortOrder: 0, isDefault: true, hidden: false),
            ],
            onSave: (draft) => saved = draft,
          ),
        ),
      ),
    );
    expect(find.text('メモ'), findsOneWidget);
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(find.text('顧客名を入力してください'), findsOneWidget);
    expect(saved, isNull);
  });
}
