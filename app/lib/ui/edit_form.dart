import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../logic/status_rules.dart';
import '../logic/text_parse.dart';
import '../logic/validators.dart';
import 'format.dart';

class CustomerEditForm extends StatefulWidget {
  const CustomerEditForm({
    super.key,
    required this.initial,
    required this.statuses,
    required this.onSave,
    this.originalAddress,
    this.onSuggest,
    this.updatedLabel,
    this.warning,
    this.embedded = false,
  });

  final CustomerDraft initial;
  final List<CustomerStatus> statuses;
  final ValueChanged<CustomerDraft> onSave;
  final String? originalAddress;
  final Future<List<String>> Function(String query)? onSuggest;
  final String? updatedLabel;
  final String? warning;
  final bool embedded;

  @override
  State<CustomerEditForm> createState() => _CustomerEditFormState();
}

class _CustomerEditFormState extends State<CustomerEditForm> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  late final TextEditingController _memo;
  late final TextEditingController _price;
  late String _date;
  late String _statusId;
  var _tried = false;
  List<String> _suggestions = const [];

  @override
  void initState() {
    super.initState();
    _apply(widget.initial);
  }

  void _apply(CustomerDraft draft) {
    _name = TextEditingController(text: draft.name);
    _phone = TextEditingController(text: draft.phone);
    _address = TextEditingController(text: draft.address);
    _memo = TextEditingController(text: draft.memo);
    _price = TextEditingController(text: draft.price > 0 ? formatYen(draft.price).replaceFirst('¥', '') : '');
    _date = draft.contractDate;
    _statusId = draft.statusId;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _memo.dispose();
    _price.dispose();
    super.dispose();
  }

  CustomerDraft get _draft => CustomerDraft(
    name: _name.text,
    phone: _phone.text,
    address: _address.text,
    memo: _memo.text,
    contractDate: _date,
    price: parseLooseInt(_price.text),
    statusId: _statusId,
    lat: widget.initial.lat,
    lng: widget.initial.lng,
    locationSource: widget.initial.locationSource,
  );

  @override
  Widget build(BuildContext context) {
    final result = _tried ? validateCustomer(_draft) : const ValidationResult({}, []);
    final addressChanged = widget.originalAddress != null && _address.text.trim() != widget.originalAddress!.trim();
    final choices = widget.statuses.where((status) => !status.hidden || status.id == _statusId).toList();
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              _field(
                '顧客名',
                TextField(
                  controller: _name,
                  style: const TextStyle(fontSize: 18),
                  decoration: _decoration(result.errors['name']),
                  textInputAction: TextInputAction.next,
                ),
                result.errors['name'],
              ),
              _field(
                '電話番号',
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(fontSize: 18),
                  decoration: _decoration(result.errors['phone']),
                ),
                result.errors['phone'],
              ),
              _field(
                '住所',
                TextField(
                  controller: _address,
                  style: const TextStyle(fontSize: 18),
                  decoration: _decoration(result.errors['address']),
                  onChanged: (value) async {
                    final suggest = widget.onSuggest;
                    if (suggest == null) return;
                    final items = await suggest(value);
                    if (!mounted) return;
                    setState(() => _suggestions = items);
                  },
                ),
                result.errors['address'],
                trailing: addressChanged ? '保存時にピン位置を再計算' : null,
              ),
              if (_suggestions.isNotEmpty)
                Wrap(
                  spacing: 8,
                  children: _suggestions
                      .map(
                        (item) => ActionChip(
                          label: Text(item),
                          onPressed: () => setState(() {
                            _address.text = item;
                            _suggestions = const [];
                          }),
                        ),
                      )
                      .toList(),
                ),
              _field(
                'メモ',
                TextField(
                  controller: _memo,
                  minLines: 4,
                  maxLines: 8,
                  style: const TextStyle(fontSize: 18, height: 1.4),
                  decoration: _decoration(result.errors['memo']).copyWith(alignLabelWithHint: true, hintText: '訪問のメモ、次回の約束など'),
                ),
                result.errors['memo'],
              ),
              _field(
                '契約日',
                InkWell(
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: _decoration(result.errors['date']),
                    child: Text(_date.isEmpty ? '日付を選択' : _date.replaceAll('-', '/'), style: const TextStyle(fontSize: 18)),
                  ),
                ),
                result.errors['date'],
              ),
              _field(
                '単価（1回・円）',
                TextField(
                  controller: _price,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,]'))],
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  decoration: _decoration(result.errors['price']).copyWith(prefixText: '¥ '),
                  onChanged: (value) {
                    final amount = parseLooseInt(value);
                    final formatted = amount == 0 ? '' : formatYen(amount).replaceFirst('¥', '');
                    if (formatted != value) {
                      _price.value = TextEditingValue(text: formatted, selection: TextSelection.collapsed(offset: formatted.length));
                    }
                  },
                ),
                result.errors['price'],
              ),
              Text('ステータス', style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: choices.map((status) {
                  final selected = status.id == _statusId;
                  return Material(
                    color: selected ? Theme.of(context).colorScheme.secondaryContainer : Theme.of(context).colorScheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: selected ? Theme.of(context).colorScheme.onSurface : Theme.of(context).dividerColor, width: selected ? 2 : 1),
                    ),
                    child: InkWell(
                      onTap: () => setState(() => _statusId = status.id),
                      borderRadius: BorderRadius.circular(12),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(width: 14, height: 14, decoration: BoxDecoration(color: colorFromHex(status.colorHex), shape: BoxShape.circle)),
                              const SizedBox(width: 6),
                              Text(status.label, style: const TextStyle(fontSize: 16)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              if (result.errors['status'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(result.errors['status']!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 14)),
                ),
              if (result.warnings.isNotEmpty || widget.warning != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    widget.warning ?? result.warnings.join(' '),
                    style: const TextStyle(color: Color(0xFF8A5A00), fontSize: 15),
                  ),
                ),
              if (widget.updatedLabel != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(widget.updatedLabel!, style: const TextStyle(fontSize: 14, color: Color(0xFF5F6368))),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton(
                onPressed: () {
                  final draft = _draft.copyWith(phone: formatJpPhone(_phone.text));
                  final validation = validateCustomer(draft);
                  if (!validation.ok) {
                    setState(() => _tried = true);
                    return;
                  }
                  widget.onSave(draft.copyWith(phone: formatJpPhone(draft.phone)));
                },
                child: const Text('保存', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final initial = DateTime.tryParse(_date) ?? DateTime.now();
    final picked = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(1990), lastDate: DateTime(2100), locale: const Locale('ja'));
    if (picked == null) return;
    setState(() => _date = formatInputDate(picked));
  }

  Widget _field(String label, Widget child, String? error, {String? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF5F6368))),
              const Spacer(),
              if (trailing != null) Text(trailing, style: const TextStyle(fontSize: 13, color: Color(0xFF8A5A00))),
            ],
          ),
          const SizedBox(height: 6),
          child,
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 14)),
            ),
        ],
      ),
    );
  }

  InputDecoration _decoration(String? error) {
    return InputDecoration(
      errorText: null,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: error == null ? const Color(0xFFDADCE0) : Theme.of(context).colorScheme.error, width: error == null ? 1 : 2),
      ),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    );
  }
}
