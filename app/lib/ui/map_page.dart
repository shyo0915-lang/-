import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../logic/validators.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import 'conflict_page.dart';
import 'edit_form.dart';
import 'fallback_map.dart';
import 'format.dart';
import 'google_map_view.dart';
import 'ocr_page.dart';
import 'settings_page.dart';
import 'share_sheet.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key, required this.state});
  final AppState state;

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final _search = TextEditingController();
  final _fallbackKey = GlobalKey<FallbackMapState>();
  final _googleKey = GlobalKey<SalesGoogleMapState>();

  AppState get app => widget.state;

  @override
  void initState() {
    super.initState();
    app.confirm = _confirm;
    app.choose = _choose;
    Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((result) => result != ConnectivityResult.none);
      app.repo.setConnectivity(online);
      if (online) {
        app.repo.sync().then((report) {
          app.refresh();
          if (report.conflicts > 0 && mounted) app.showToast(report.message);
        });
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final sheetHeight = switch (app.sheet) {
      SheetLevel.closed => 0.0,
      SheetLevel.peak => 110.0,
      SheetLevel.half => height * 0.46,
      SheetLevel.full => height,
    };
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: app.config.hasMaps
                ? SalesGoogleMap(key: _googleKey, state: app, onLongPress: _placePin)
                : FallbackMap(key: _fallbackKey, state: app, onLongPress: _placePin),
          ),
          if (!app.repo.isOnline)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Material(
                  color: Color(0xFF3C4043),
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('オフライン', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 15)),
                  ),
                ),
              ),
            ),
          Positioned(
            top: app.repo.isOnline ? 12 : 48,
            left: 12,
            right: 12,
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Material(
                          elevation: 2,
                          borderRadius: BorderRadius.circular(24),
                          child: TextField(
                            controller: _search,
                            style: const TextStyle(fontSize: 16),
                            decoration: const InputDecoration(
                              hintText: '顧客名・住所・電話・メモで検索',
                              prefixIcon: Icon(Icons.search),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(vertical: 14),
                            ),
                            onChanged: app.setQuery,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (kIsWeb)
                        _roundButton(Icons.list_alt, '管理画面', () {
                          launchUrl(Uri.base.resolve('admin/'));
                        }),
                      if (kIsWeb) const SizedBox(width: 8),
                      _roundButton(Icons.tune, '設定', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsPage(state: app)))),
                      if (app.conflicts.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        _roundButton(Icons.sync_problem, '競合', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ConflictPage(state: app)))),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final status in app.statuses)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(status.label, style: const TextStyle(fontSize: 14)),
                              avatar: CircleAvatar(backgroundColor: colorFromHex(status.colorHex), radius: 7),
                              selected: !app.hiddenFilters.contains(status.id),
                              onSelected: (_) => app.toggleStatus(status.id),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (app.repo.sampleMode)
            Positioned(
              left: 12,
              bottom: 28 + safeBottom,
              child: DecoratedBox(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.all(Radius.circular(8))),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text('サンプルデータ', style: TextStyle(fontSize: 12, color: Color(0xFF5F6368))),
                ),
              ),
            ),
          if (app.sheet == SheetLevel.closed)
            Positioned(
              right: 16,
              bottom: 108 + safeBottom,
              child: _roundButton(Icons.my_location, '現在地', _myLocation),
            ),
          if (app.sheet == SheetLevel.closed)
            Positioned(
              right: 16,
              bottom: 28 + safeBottom,
              child: FloatingActionButton.large(
                heroTag: 'camera',
                tooltip: '契約書を撮影して新規登録',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OcrPage(state: app))),
                child: const Icon(Icons.add_a_photo, size: 30),
              ),
            ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 280),
            curve: const Cubic(0.22, 1, 0.36, 1),
            left: 0,
            right: 0,
            bottom: 0,
            height: sheetHeight,
            child: app.selected == null
                ? const SizedBox.shrink()
                : Material(
                    color: Theme.of(context).colorScheme.surface,
                    elevation: 12,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(app.sheet == SheetLevel.full ? 0 : 22)),
                    child: app.sheet == SheetLevel.full ? _full(app.selected!) : _preview(app.selected!),
                  ),
          ),
          if (app.toast != null)
            Positioned(
              top: 120,
              left: 32,
              right: 32,
              child: Material(
                color: const Color(0xFF202124),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Text(app.toast!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _roundButton(IconData icon, String tooltip, VoidCallback onTap) {
    return Material(
      elevation: 2,
      shape: const CircleBorder(),
      color: Colors.white,
      child: IconButton(tooltip: tooltip, onPressed: onTap, icon: Icon(icon), constraints: const BoxConstraints(minWidth: 48, minHeight: 48)),
    );
  }

  Widget _preview(Customer customer) {
    final status = app.statusOf(customer.statusId);
    return GestureDetector(
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -800 || velocity < 0 && app.sheet == SheetLevel.half) {
          _openFull();
        } else if (velocity > 800) {
          if (app.sheet == SheetLevel.peak) {
            app.setSheet(SheetLevel.closed);
          } else {
            app.setSheet(SheetLevel.peak);
          }
        }
      },
      onTap: app.sheet == SheetLevel.half ? _openFull : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 44, height: 5, decoration: BoxDecoration(color: const Color(0xFFDADCE0), borderRadius: BorderRadius.circular(3)))),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.circle, size: 14, color: colorFromHex(status?.colorHex ?? '#1A73E8')),
                const SizedBox(width: 6),
                Text(status?.label ?? '', style: const TextStyle(fontSize: 14, color: Color(0xFF5F6368))),
                if (customer.pendingSync) ...[
                  const SizedBox(width: 8),
                  const Text('同期待ち', style: TextStyle(fontSize: 13, color: Color(0xFF8A5A00))),
                ],
                if (customer.sharedWithMe) ...[
                  const SizedBox(width: 8),
                  const Text('共有', style: TextStyle(fontSize: 13, color: Color(0xFF1A73E8))),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(customer.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            if (app.sheet != SheetLevel.peak) ...[
              const SizedBox(height: 4),
              Text(customer.address, style: const TextStyle(fontSize: 16, color: Color(0xFF3C4043))),
              GestureDetector(
                onLongPress: () {
                  Clipboard.setData(ClipboardData(text: customer.phone));
                  app.showToast('電話番号をコピーしました');
                },
                child: Text(customer.phone, style: const TextStyle(fontSize: 16, color: Color(0xFF3C4043))),
              ),
              if (customer.memo.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(memoExcerpt(customer.memo), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _metric('契約日', formatIso(customer.contractDate)),
                  const SizedBox(width: 20),
                  _metric('単価（1回）', formatYen(customer.unitPrice)),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(child: SizedBox(height: 56, child: FilledButton(onPressed: () => _call(customer.phone), child: const Text('電話する', style: TextStyle(fontSize: 18))))),
                  const SizedBox(width: 10),
                  Expanded(child: SizedBox(height: 56, child: OutlinedButton(onPressed: () => _nav(customer), child: const Text('ナビ', style: TextStyle(fontSize: 18))))),
                ],
              ),
              const SizedBox(height: 6),
              const Center(child: Text('タップ／上スワイプで詳細・編集', style: TextStyle(fontSize: 13, color: Color(0xFF80868B)))),
            ],
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF80868B))),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _full(Customer customer) {
    final updated = customer.updatedByName == null ? null : '最終更新 ${formatIso(customer.updatedAt)} ${customer.updatedByName}';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 8, 0),
          child: Row(
            children: [
              TextButton(onPressed: () => app.setSheet(SheetLevel.half), child: const Text('‹ 地図', style: TextStyle(fontSize: 17))),
              const Expanded(child: Text('詳細・編集', textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
              OutlinedButton(onPressed: () => showShareSheet(context, app, customer), child: const Text('共有')),
              IconButton(
                tooltip: 'アーカイブ',
                onPressed: () async {
                  final ok = await _confirm('この顧客をアーカイブしますか');
                  if (!ok) return;
                  await app.repo.archiveCustomer(customer.id);
                  await app.refresh();
                  app.setSheet(SheetLevel.closed);
                  app.showToast('アーカイブしました');
                },
                icon: const Icon(Icons.archive_outlined),
              ),
            ],
          ),
        ),
        Expanded(
          child: CustomerEditForm(
            key: ValueKey(customer.id),
            initial: app.draftOf(customer),
            statuses: app.statuses,
            originalAddress: customer.address,
            onSuggest: app.suggest,
            updatedLabel: updated,
            onSave: (draft) => app.saveExisting(customer, draft),
          ),
        ),
      ],
    );
  }

  void _openFull() {
    HapticFeedback.selectionClick();
    app.setSheet(SheetLevel.full);
  }

  Future<void> _call(String phone) async {
    final uri = Uri.parse('tel:${phone.replaceAll('-', '')}');
    await launchUrl(uri);
  }

  Future<void> _nav(Customer customer) async {
    final destination = customer.hasLocation ? '${customer.lat},${customer.lng}' : Uri.encodeComponent(customer.address);
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$destination');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _myLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        app.showToast('位置情報の権限がありません');
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      if (app.config.hasMaps) {
        await _googleKey.currentState?.moveTo(position.latitude, position.longitude);
      } else {
        _fallbackKey.currentState?.focus(position.latitude, position.longitude);
      }
      app.showToast('現在地に移動しました');
    } catch (_) {
      app.showToast('現在地を取得できませんでした');
    }
  }

  Future<void> _placePin(double lat, double lng) async {
    if (app.selected == null) {
      app.showToast('先に顧客を選ぶか、契約書から登録してください');
      return;
    }
    app.moveSelectedPin(lat, lng);
    await app.persistSelectedPin();
  }

  Future<bool> _confirm(String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(message, style: const TextStyle(fontSize: 17)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('OK')),
        ],
      ),
    );
    return result ?? false;
  }

  Future<int?> _choose(String title, List<String> options) {
    return showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(padding: const EdgeInsets.all(16), child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
            for (var i = 0; i < options.length; i++)
              ListTile(title: Text(options[i], style: const TextStyle(fontSize: 17)), onTap: () => Navigator.pop(context, i)),
          ],
        ),
      ),
    );
  }
}
