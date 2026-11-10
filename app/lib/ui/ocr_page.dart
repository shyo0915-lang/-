import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../logic/ocr_flow.dart';
import '../logic/ocr_parser.dart';
import '../logic/validators.dart';
import '../services/cloud_ocr.dart';
import '../services/image_vault.dart';
import '../services/mlkit_text.dart';
import '../state/app_state.dart';
import 'format.dart';

class OcrPage extends StatefulWidget {
  const OcrPage({super.key, required this.state});
  final AppState state;

  @override
  State<OcrPage> createState() => _OcrPageState();
}

class _OcrPageState extends State<OcrPage> {
  String _format = 'auto';
  String _step = 'camera';
  int _proc = 0;
  List<OcrField> _fields = const [];
  String? _message;
  String _statusId = '';
  String? _imagePath;
  bool _busy = false;

  AppState get app => widget.state;

  @override
  void initState() {
    super.initState();
    final visible = app.statuses.where((status) => !status.hidden);
    _statusId = visible.isEmpty ? '' : visible.first.id;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _step == 'review' ? null : const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: _step == 'review' ? null : const Color(0xFF121212),
        foregroundColor: _step == 'review' ? null : Colors.white,
        title: Text(_step == 'review' ? '読み取り結果の確認' : '契約書を撮影', style: const TextStyle(fontSize: 18)),
        actions: [
          if (_step == 'review')
            TextButton(
              onPressed: () => setState(() => _step = 'camera'),
              child: const Text('撮り直す'),
            ),
        ],
      ),
      body: switch (_step) {
        'processing' => _processing(),
        'review' => _review(),
        _ => _camera(),
      },
    );
  }

  Widget _camera() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Expanded(
            child: Center(
              child: Text(
                '書類を枠に収めて撮影するか、写真を選んでください。\n書類の自動検出は次の版で対応します。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 17, height: 1.5),
              ),
            ),
          ),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'auto', label: Text('自動')),
              ButtonSegment(value: 'template', label: Text('定型')),
              ButtonSegment(value: 'handwritten', label: Text('手書き')),
            ],
            selected: {_format},
            onSelectionChanged: (value) => setState(() => _format = value.first),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white, minimumSize: const Size.fromHeight(56)),
                  onPressed: () => _capture(ImageSource.gallery),
                  child: const Text('写真を選ぶ'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                  onPressed: () => _capture(ImageSource.camera),
                  child: const Text('撮影'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _processing() {
    const steps = ['切り抜き・台形補正', '文字認識（OCR）', '項目の抽出・割り当て', '信頼度チェック'];
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                '${i < _proc ? '✓' : i == _proc ? '…' : '・'} ${steps[i]}',
                style: TextStyle(color: Colors.white.withValues(alpha: i <= _proc ? 1 : 0.4), fontSize: 17),
              ),
            ),
        ],
      ),
    );
  }

  Widget _review() {
    final unresolved = _fields.where((field) => field.blocksSave).length;
    return Column(
      children: [
        if (_message != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(_message!, style: const TextStyle(fontSize: 15, color: Color(0xFF8A5A00))),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('枠が強調された項目は読み取りの信頼度が低いため、確認してください。', style: TextStyle(fontSize: 15)),
              const SizedBox(height: 12),
              for (final field in _fields) _ocrField(field),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final status in app.statuses.where((status) => !status.hidden))
                    ChoiceChip(
                      label: Text(status.label),
                      selected: status.id == _statusId,
                      onSelected: (_) => setState(() => _statusId = status.id),
                    ),
                ],
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton(
                onPressed: unresolved > 0 || _busy ? null : _save,
                child: Text(unresolved > 0 ? '要確認 $unresolved件を確認してください' : '確認して地図に保存', style: const TextStyle(fontSize: 17)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _ocrField(OcrField field) {
    final warn = field.blocksSave;
    final isPrice = field.key == 'price';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(field.label, style: const TextStyle(fontSize: 14)),
              const Spacer(),
              Text(
                warn ? '要確認 ${(field.confidence * 100).round()}%' : '信頼度 ${(field.confidence * 100).round()}%',
                style: TextStyle(color: warn ? const Color(0xFF8A5A00) : const Color(0xFF80868B), fontSize: 13),
              ),
            ],
          ),
          if (field.hint != null) Text('候補: ${field.hint}', style: const TextStyle(fontSize: 13, color: Color(0xFF8A5A00))),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: isPrice && field.value.isNotEmpty ? formatYen(int.parse(field.value)).replaceFirst('¥', '') : field.value,
                  style: const TextStyle(fontSize: 18),
                  keyboardType: isPrice ? TextInputType.number : field.key == 'phone' ? TextInputType.phone : TextInputType.text,
                  decoration: InputDecoration(
                    filled: warn,
                    fillColor: warn ? const Color(0xFFFFF4D6) : null,
                    prefixText: isPrice ? '¥ ' : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: warn ? const Color(0xFFF9AB00) : const Color(0xFFDADCE0), width: warn ? 2 : 1),
                    ),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _fields = [
                        for (final item in _fields)
                          if (item.key == field.key)
                            item.copyWith(value: isPrice ? value.replaceAll(RegExp(r'[^0-9]'), '') : value, confirmed: true)
                          else
                            item,
                      ];
                    });
                  },
                ),
              ),
              if (warn) ...[
                const SizedBox(width: 8),
                SizedBox(
                  height: 52,
                  width: 64,
                  child: OutlinedButton(
                    onPressed: field.value.trim().isEmpty
                        ? null
                        : () => setState(() {
                            _fields = [for (final item in _fields) item.key == field.key ? item.copyWith(confirmed: true) : item];
                          }),
                    child: const Text('OK'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _capture(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(source: source, imageQuality: 80, maxWidth: 2000);
      if (file == null) return;
      final bytes = await File(file.path).readAsBytes();
      if (bytes.length < 20 * 1024) {
        app.showToast('画像が小さすぎます。明るい場所で、書類を大きく撮ってください');
      }
      final stored = await ImageVault().save(bytes);
      setState(() {
        _step = 'processing';
        _proc = 0;
        _imagePath = stored;
      });
      final text = await recognizeJapaneseText(file.path);
      if (!mounted) return;
      setState(() => _proc = 2);
      final online = app.repo.isOnline && app.config.hasSupabase;
      final result = await runOcr(
        onDeviceText: text,
        formatChoice: _format,
        online: online,
        imageBytes: bytes,
        cloud: app.config.hasSupabase
            ? EdgeCloudOcr(config: app.config, accessToken: () => Supabase.instance.client.auth.currentSession?.accessToken)
            : null,
      );
      if (!mounted) return;
      setState(() {
        _proc = 4;
        _fields = result.fields;
        _message = result.message;
        _step = 'review';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _step = 'camera');
      app.showToast('写真を利用できませんでした: $error');
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    String value(String key) => _fields.firstWhere((field) => field.key == key).value.trim();
    var draft = CustomerDraft(
      name: value('name'),
      phone: value('phone'),
      address: value('address'),
      memo: '',
      contractDate: value('date'),
      price: int.tryParse(value('price')) ?? 0,
      statusId: _statusId,
    );
    final hits = await app.geocoder.geocode(draft.address);
    if (hits.length == 1) {
      draft = draft.copyWith(lat: hits.single.lat, lng: hits.single.lng, locationSource: 'geocoded');
    } else if (hits.length > 1 && mounted) {
      final index = await app.choose?.call('住所の候補', hits.map((hit) => hit.formattedAddress).toList());
      if (index != null) {
        draft = draft.copyWith(lat: hits[index].lat, lng: hits[index].lng, locationSource: 'geocoded');
      }
    }
    if (draft.lat == null) {
      try {
        final position = await Geolocator.getCurrentPosition();
        draft = draft.copyWith(lat: position.latitude, lng: position.longitude, locationSource: 'manual');
        app.showToast('現在地に仮ピンを置きました。あとでドラッグして直せます');
      } catch (_) {
        draft = draft.copyWith(lat: 35.682, lng: 139.772, locationSource: 'manual');
        app.showToast('仮の位置にピンを置きました。地図でドラッグして直してください');
      }
    }
    final confidence = _fields.map((field) => field.confidence).fold<double>(1, (min, value) => value < min ? value : min);
    final format = _message != null ? 'handwritten' : (_format == 'handwritten' ? 'handwritten' : 'template');
    final created = await app.createCustomer(draft, format: format, confidence: confidence);
    if (!mounted) return;
    setState(() => _busy = false);
    if (created != null) {
      if (_imagePath != null) await app.repo.saveLocalImage(created.id, _imagePath!);
      if (mounted) Navigator.of(context).pop();
    }
  }
}
