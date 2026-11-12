import 'package:flutter/material.dart';

import '../state/app_state.dart';
import 'back_button.dart';

const _labels = {
  'name': '顧客名',
  'phone': '電話番号',
  'address': '住所',
  'memo': 'メモ',
  'statusId': 'ステータス',
  'contractDate': '契約日',
  'unitPrice': '単価（1回）',
  'lat': '緯度',
  'lng': '経度',
  'locationSource': '位置の由来',
};

class ConflictPage extends StatelessWidget {
  const ConflictPage({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => Scaffold(
      appBar: largeBackBar('同期の競合', () => Navigator.maybePop(context)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('同じ項目を同時に変えた場合は、サーバーの値を残しています。採用する値を選んでください。', style: TextStyle(fontSize: 15, height: 1.4)),
          const SizedBox(height: 12),
          if (state.conflicts.isEmpty) const Text('競合はありません'),
          for (final conflict in state.conflicts)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(conflict.customerName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    Text(_labels[conflict.field] ?? conflict.field, style: const TextStyle(fontSize: 14)),
                    const SizedBox(height: 8),
                    Text('この端末: ${conflict.deviceValue}', style: const TextStyle(fontSize: 16)),
                    Text('サーバー: ${conflict.serverValue}', style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              await state.repo.resolveConflict(conflict: conflict, useDevice: true);
                              await state.refresh();
                            },
                            child: const Text('端末の値'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: () async {
                              await state.repo.resolveConflict(conflict: conflict, useDevice: false);
                              await state.refresh();
                            },
                            child: const Text('サーバーの値'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
    );
  }
}
