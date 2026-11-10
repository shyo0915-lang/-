import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../logic/price_tiers.dart';
import '../logic/status_rules.dart';
import '../state/app_state.dart';
import 'format.dart';
import 'pin_painter.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.state});
  final AppState state;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late List<CustomerStatus> _statuses;
  late List<TextEditingController> _bounds;

  @override
  void initState() {
    super.initState();
    _statuses = [...widget.state.statuses]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    _bounds = widget.state.tiers.boundaries.map((value) => TextEditingController(text: '$value')).toList();
  }

  @override
  void dispose() {
    for (final controller in _bounds) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('ステータス', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('初期の4つは削除できません。名前と色の変更は管理者、非表示と並び順は自分の操作として保存します。', style: TextStyle(fontSize: 14, height: 1.4)),
          const SizedBox(height: 8),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onReorderItem: (oldIndex, newIndex) async {
              final item = _statuses.removeAt(oldIndex);
              _statuses.insert(newIndex, item);
              setState(() {});
              await widget.state.repo.reorderStatuses(_statuses.map((status) => status.id).toList());
              await widget.state.refresh();
            },
            children: [
              for (final status in _statuses)
                ListTile(
                  key: ValueKey(status.id),
                  contentPadding: EdgeInsets.zero,
                  leading: SizedBox(width: 36, height: 42, child: CustomPaint(painter: PinGlyphPainter(fill: colorFromHex(status.colorHex), shape: status.shape))),
                  title: Text(status.label, style: const TextStyle(fontSize: 17)),
                  subtitle: Text(status.isDefault ? '初期' : '追加', style: const TextStyle(fontSize: 13)),
                  trailing: Switch(
                    value: !status.hidden,
                    onChanged: (shown) async {
                      final next = status.copyWith(hidden: !shown);
                      final error = await widget.state.repo.saveStatus(next);
                      if (error != null) {
                        widget.state.showToast(error);
                        return;
                      }
                      await widget.state.refresh();
                      setState(() => _statuses = [...widget.state.statuses]);
                    },
                  ),
                  onTap: () => _editStatus(status),
                ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _statuses.length >= 10 ? null : _addStatus,
            child: const Text('ステータスを追加'),
          ),
          const SizedBox(height: 28),
          const Text('単価帯（1回の金額）', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('境界は小さい順に、1円単位で入力します。段階は2〜5です。自分の地図表示だけに反映されます。', style: TextStyle(fontSize: 14, height: 1.4)),
          const SizedBox(height: 8),
          for (var i = 0; i < _bounds.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _bounds[i],
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 18),
                      decoration: InputDecoration(labelText: '境界 ${i + 1}（円）', prefixText: '¥ '),
                    ),
                  ),
                  if (_bounds.length > 1)
                    IconButton(
                      onPressed: () => setState(() {
                        _bounds.removeAt(i).dispose();
                      }),
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
            ),
          if (_bounds.length < 4)
            TextButton(
              onPressed: () => setState(() => _bounds.add(TextEditingController())),
              child: const Text('境界を追加'),
            ),
          const SizedBox(height: 8),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _saveTiers,
            child: const Text('単価帯を保存'),
          ),
          const SizedBox(height: 16),
          const Text('プレビュー', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          _preview(),
        ],
      ),
    );
  }

  Widget _preview() {
    final boundaries = _bounds.map((controller) => int.tryParse(controller.text.replaceAll(',', '')) ?? 0).toList();
    final config = PriceTierConfig(boundaries.isEmpty ? [1] : boundaries);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        for (var tier = 0; tier < config.tierCount && tier < 5; tier++)
          Column(
            children: [
              SizedBox(
                width: pinDiameterForTier(tier),
                height: pinDiameterForTier(tier) * 1.35,
                child: CustomPaint(painter: PinGlyphPainter(fill: const Color(0xFF1A73E8), shape: 'check')),
              ),
              Text('${widget.state.customers.where((customer) => config.tierOf(customer.unitPrice) == tier).length}件', style: const TextStyle(fontSize: 13)),
            ],
          ),
      ],
    );
  }

  Future<void> _saveTiers() async {
    final boundaries = _bounds.map((controller) => int.tryParse(controller.text.replaceAll(',', '')) ?? 0).toList();
    final error = await widget.state.repo.savePriceTiers(PriceTierConfig(boundaries, personal: true));
    if (error != null) {
      widget.state.showToast(error);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    await widget.state.refresh();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('単価帯を保存しました')));
  }

  Future<void> _addStatus() => _editStatus(null);

  Future<void> _editStatus(CustomerStatus? existing) async {
    final label = TextEditingController(text: existing?.label ?? '');
    var color = existing?.colorHex ?? statusPalette.firstWhere((item) => _statuses.every((status) => status.colorHex.toLowerCase() != item.toLowerCase() || status.shape != 'star'), orElse: () => statusPalette.last);
    var shape = existing?.shape ?? 'star';
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(existing == null ? 'ステータスを追加' : 'ステータスを編集'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: label, decoration: const InputDecoration(labelText: '名前'), style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final item in statusPalette)
                    GestureDetector(
                      onTap: () => setLocal(() => color = item),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: colorFromHex(item),
                          shape: BoxShape.circle,
                          border: Border.all(color: color == item ? Colors.black : Colors.transparent, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final item in statusShapes)
                    ChoiceChip(label: Text(_shapeLabel(item)), selected: shape == item, onSelected: (_) => setLocal(() => shape = item)),
                ],
              ),
            ],
          ),
          actions: [
            if (existing != null && !existing.isDefault)
              TextButton(
                onPressed: () async {
                  final move = await _pickMoveTarget(existing.id);
                  final error = await widget.state.repo.deleteStatus(existing.id, moveToStatusId: move);
                  if (error != null && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
                    return;
                  }
                  if (context.mounted) Navigator.pop(context, true);
                },
                child: const Text('削除'),
              ),
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
            FilledButton(
              onPressed: () async {
                final next = CustomerStatus(
                  id: existing?.id ?? const Uuid().v4(),
                  label: label.text,
                  colorHex: color,
                  shape: shape,
                  sortOrder: existing?.sortOrder ?? _statuses.length,
                  isDefault: existing?.isDefault ?? false,
                  hidden: existing?.hidden ?? false,
                );
                final error = await widget.state.repo.saveStatus(next, creating: existing == null);
                if (error != null && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
                  return;
                }
                if (context.mounted) Navigator.pop(context, true);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    label.dispose();
    if (saved == true) {
      await widget.state.refresh();
      setState(() => _statuses = [...widget.state.statuses]);
    }
  }

  Future<String?> _pickMoveTarget(String currentId) async {
    final others = _statuses.where((status) => status.id != currentId).toList();
    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('顧客の移し替え先'),
        children: [
          for (final status in others)
            SimpleDialogOption(onPressed: () => Navigator.pop(context, status.id), child: Text(status.label)),
          SimpleDialogOption(onPressed: () => Navigator.pop(context), child: const Text('使用中でなければそのまま削除')),
        ],
      ),
    );
  }

  String _shapeLabel(String shape) => switch (shape) {
    'check' => 'チェック',
    'diamond' => 'ひし形',
    'ring' => 'リング',
    'cross' => 'バツ',
    'star' => '星',
    'square' => '四角',
    _ => shape,
  };
}
