import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../logic/map_camera.dart';
import '../logic/validators.dart';
import '../services/map_camera_store.dart';
import '../models/models.dart';
import '../services/maps_loader.dart';
import '../state/app_state.dart';
import 'back_button.dart';
import 'conflict_page.dart';
import 'customer_photos.dart';
import 'edit_form.dart';
import 'new_customer_page.dart';
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

class _MapPageState extends State<MapPage> with WidgetsBindingObserver {
  final _search = TextEditingController();
  final _fallbackKey = GlobalKey<FallbackMapState>();
  final _googleKey = GlobalKey<SalesGoogleMapState>();
  bool _mapsBroken = false;
  StreamSubscription<Position>? _fixSub;
  Position? _here;
  CustomerDraft? _editDraft;
  MapCamera _view = MapCamera.initial;
  var _cameraDecided = false;
  var _userMovedMap = false;

  AppState get app => widget.state;
  bool get _showGoogle => app.config.hasMaps && googleMapsAvailable && !_mapsBroken;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    app.confirm = _confirm;
    app.choose = _choose;
    app.addListener(_onAppChanged);
    _startIfGranted();
    _decideCamera();
    if (app.config.hasMaps) {
      _watchMaps();
    }
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
    WidgetsBinding.instance.removeObserver(this);
    _stopWatch();
    app.removeListener(_onAppChanged);
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startIfGranted();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden || state == AppLifecycleState.detached) {
      _stopWatch();
    }
  }

  void _stopWatch() {
    _fixSub?.cancel();
    _fixSub = null;
  }

  Future<void> _startIfGranted() async {
    final permission = await Geolocator.checkPermission();
    if (!mounted) return;
    if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
      await _watch(moveCamera: false);
    }
  }

  Future<void> _decideCamera() async {
    final saved = await MapCameraStore.load();
    if (!mounted || _userMovedMap) return;
    if (saved != null) {
      setState(() {
        _view = saved;
        _cameraDecided = true;
      });
      return;
    }
    final permission = await Geolocator.checkPermission();
    if (!mounted || _userMovedMap) return;
    if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
      try {
        final position = await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 6));
        if (!mounted || _userMovedMap) return;
        setState(() {
          _view = MapCamera(position.latitude, position.longitude, MapCamera.streetZoom);
          _cameraDecided = true;
        });
        return;
      } catch (_) {}
    }
    if (app.customers.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (!mounted || _userMovedMap) return;
    final pins = [
      for (final customer in app.customers)
        if (customer.hasLocation) (lat: customer.lat!, lng: customer.lng!),
    ];
    setState(() {
      _view = fitPins(pins) ?? MapCamera.initial;
      _cameraDecided = true;
    });
  }

  void _onCameraSettled(MapCamera camera) {
    final shifted = (camera.lat - _view.lat).abs() > 0.0002 || (camera.lng - _view.lng).abs() > 0.0002 || (camera.zoom - _view.zoom).abs() > 0.2;
    if (!_cameraDecided && shifted) _userMovedMap = true;
    if (_cameraDecided || _userMovedMap) MapCameraStore.save(camera);
  }

  LocationSettings get _locationSettings => kIsWeb
      ? WebSettings(accuracy: LocationAccuracy.high, distanceFilter: 8)
      : const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 8);

  Future<void> _watch({required bool moveCamera}) async {
    _fixSub ??= Geolocator.getPositionStream(locationSettings: _locationSettings).listen(
      (position) {
        if (!mounted) return;
        setState(() => _here = position);
      },
      onError: (_) {
        _stopWatch();
        if (mounted) app.showToast('現在地を取得できませんでした');
      },
    );
    if (!moveCamera) return;
    final position = await Geolocator.getCurrentPosition();
    if (!mounted) return;
    setState(() => _here = position);
    if (_showGoogle) {
      await _googleKey.currentState?.moveTo(position.latitude, position.longitude);
    } else {
      _fallbackKey.currentState?.focus(position.latitude, position.longitude);
    }
    app.showToast('現在地に移動しました');
  }

  String? _pannedId;

  void _onAppChanged() {
    if (!mounted) return;
    final customer = app.selected;
    if (customer == null || !customer.hasLocation || app.sheet == SheetLevel.closed) {
      _pannedId = null;
      return;
    }
    if (_pannedId == customer.id) return;
    _pannedId = customer.id;
    if (_showGoogle) {
      _googleKey.currentState?.moveTo(customer.lat!, customer.lng!);
    } else {
      _fallbackKey.currentState?.focus(customer.lat!, customer.lng!);
    }
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
            child: _showGoogle
                ? SalesGoogleMap(key: _googleKey, state: app, onLongPress: _placePin, here: _here, camera: _view, onCameraSettled: _onCameraSettled)
                : FallbackMap(key: _fallbackKey, state: app, onLongPress: _placePin, here: _here, camera: _view, onCameraSettled: _onCameraSettled),
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
              left: 12,
              right: 96,
              bottom: 28 + safeBottom,
              child: FilledButton(
                onPressed: _registerAtCenter,
                style: FilledButton.styleFrom(minimumSize: const Size(64, 56)),
                child: const Text('＋ここに登録', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ),
          if (app.sheet == SheetLevel.closed && _recall != null)
            Positioned(
              left: 12,
              bottom: 96 + safeBottom,
              child: FilledButton.icon(
                onPressed: () => app.selectCustomer(_recall!.id),
                icon: const Icon(Icons.assignment_ind),
                label: const Text('顧客情報に戻る', style: TextStyle(fontSize: 18)),
                style: FilledButton.styleFrom(minimumSize: const Size(64, 56)),
              ),
            ),
          if (app.sheet == SheetLevel.closed && app.drop != null)
            Positioned(
              left: 12,
              bottom: 164 + safeBottom,
              child: FilledButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NewCustomerPage(state: app))),
                child: const Text('新規登録を続ける', style: TextStyle(fontSize: 18)),
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
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                      if (customer.photos.isNotEmpty) CustomerPhotoStrip(state: app, customer: customer, compact: true),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _metric('契約日', formatIso(customer.contractDate)),
                          const SizedBox(width: 20),
                          _metric('単価（1回）', formatYen(customer.unitPrice)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
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
              LargeBackButton(onPressed: () => _backToCard(customer)),
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
            initial: app.drafts[customer.id] ?? app.draftOf(customer),
            statuses: app.statuses,
            originalAddress: customer.address,
            onChanged: (draft) => _editDraft = draft,
            onSuggest: app.suggest,
            updatedLabel: updated,
            onSave: (draft) => app.saveExisting(customer, draft),
            header: CustomerPhotoStrip(state: app, customer: customer, allowEdit: true),
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
    final destination = customer.hasLocation ? '${customer.lat},${customer.lng}' : customer.address;
    final apple = Uri.https('maps.apple.com', '/', {'daddr': destination, 'dirflg': 'd'});
    final google = Uri.https('www.google.com', '/maps/dir/', {'api': '1', 'destination': destination, 'travelmode': 'driving'});
    final choice = await showModalBottomSheet<Uri>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('ルート案内', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              SizedBox(height: 56, child: FilledButton(onPressed: () => Navigator.pop(context, apple), child: const Text('Appleマップで案内', style: TextStyle(fontSize: 18)))),
              const SizedBox(height: 8),
              SizedBox(height: 56, child: OutlinedButton(onPressed: () => Navigator.pop(context, google), child: const Text('Googleマップで案内', style: TextStyle(fontSize: 18)))),
            ],
          ),
        ),
      ),
    );
    if (choice == null) return;
    await launchUrl(choice, mode: LaunchMode.externalApplication);
  }

  Future<void> _myLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        app.showToast('位置情報の権限がありません');
        return;
      }
      await _watch(moveCamera: true);
    } catch (_) {
      app.showToast('現在地を取得できませんでした');
    }
  }

  Customer? get _recall {
    final id = app.recallId;
    if (id == null) return null;
    for (final customer in app.customers) {
      if (customer.id == id) return customer;
    }
    return null;
  }

  bool _dirty(Customer customer, CustomerDraft draft) {
    final origin = app.draftOf(customer);
    return draft.name.trim() != origin.name.trim() ||
        draft.phone.trim() != origin.phone.trim() ||
        draft.address.trim() != origin.address.trim() ||
        draft.memo.trim() != origin.memo.trim() ||
        draft.contractDate != origin.contractDate ||
        draft.price != origin.price ||
        draft.statusId != origin.statusId;
  }

  Future<void> _backToCard(Customer customer) async {
    final draft = _editDraft ?? app.drafts[customer.id] ?? app.draftOf(customer);
    if (!_dirty(customer, draft)) {
      app.forgetDraft(customer.id);
      app.setSheet(SheetLevel.half);
      return;
    }
    final choice = await app.choose?.call('変更があります', ['保存する', '下書きとして残す', '破棄する']);
    if (!mounted || choice == null) return;
    if (choice == 0) {
      await app.saveExisting(customer, draft);
      app.forgetDraft(customer.id);
      return;
    }
    if (choice == 1) {
      app.rememberDraft(customer.id, draft);
      app.setSheet(SheetLevel.half);
      return;
    }
    app.forgetDraft(customer.id);
    _editDraft = null;
    app.setSheet(SheetLevel.half);
  }

  Future<void> _registerAtCenter() async {
    final lat = _showGoogle ? _googleKey.currentState?.center.latitude : _fallbackKey.currentState?.centerLat;
    final lng = _showGoogle ? _googleKey.currentState?.center.longitude : _fallbackKey.currentState?.centerLng;
    await _placePin(lat ?? 35.682, lng ?? 139.772);
  }

  DateTime? _lastDrop;

  Future<void> _placePin(double lat, double lng) async {
    final now = DateTime.now();
    if (_lastDrop != null && now.difference(_lastDrop!) < const Duration(milliseconds: 800)) return;
    _lastDrop = now;
    if (app.placingPin && app.selected != null) {
      app.moveSelectedPin(lat, lng);
      await app.persistSelectedPin();
      return;
    }
    final statusId = app.prospectStatusId();
    var draft = CustomerDraft(
      name: '',
      phone: '',
      address: '',
      memo: '',
      contractDate: '',
      price: 0,
      statusId: statusId,
      lat: lat,
      lng: lng,
      locationSource: 'manual',
    );
    app.setDrop(MapDrop(lat: lat, lng: lng, draft: draft));
    final address = await app.geocoder.reverseGeocode(lat, lng);
    if (!mounted) return;
    if (address != null && app.drop != null) {
      draft = draft.copyWith(address: address);
      app.setDrop(MapDrop(lat: lat, lng: lng, draft: draft));
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => NewCustomerPage(state: app)));
  }

  void _watchMaps() {
    var ticks = 0;
    Timer.periodic(const Duration(milliseconds: 500), (timer) {
      ticks += 1;
      if (!mounted || ticks > 20 || _mapsBroken) {
        timer.cancel();
        return;
      }
      if (!mapsErrorOnPage()) return;
      timer.cancel();
      setState(() => _mapsBroken = true);
      final detail = googleMapsError;
      app.showToast(detail == null || detail.isEmpty ? 'Googleマップを表示できないため、簡易地図に切り替えました' : detail);
    });
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
