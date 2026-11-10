import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../config.dart';
import '../data/repository.dart';
import '../logic/geo.dart';
import '../logic/price_tiers.dart';
import '../logic/status_rules.dart';
import '../logic/text_parse.dart';
import '../logic/validators.dart';
import '../models/models.dart';
import '../services/geocoder.dart';

enum SheetLevel { closed, peak, half, full }

class AppState extends ChangeNotifier {
  AppState({required this.repo, required this.config, required this.geocoder});

  final AppRepository repo;
  final AppConfig config;
  final Geocoder geocoder;
  final _ids = const Uuid();

  List<Customer> customers = [];
  List<CustomerStatus> statuses = [];
  PriceTierConfig tiers = PriceTierConfig.defaults;
  List<SyncConflict> conflicts = [];
  String query = '';
  final Set<String> hiddenFilters = {};
  String? selectedId;
  SheetLevel sheet = SheetLevel.closed;
  String? toast;
  bool busy = false;
  bool placingPin = false;
  String? startupError;

  Future<bool> Function(String message)? confirm;
  Future<int?> Function(String title, List<String> options)? choose;

  Customer? get selected {
    for (final customer in customers) {
      if (customer.id == selectedId) return customer;
    }
    return null;
  }

  List<Customer> get visible {
    final needle = query.trim().toLowerCase();
    final items = customers.where((customer) {
      if (hiddenFilters.contains(customer.statusId)) return false;
      if (needle.isEmpty) return true;
      return customer.name.toLowerCase().contains(needle) ||
          customer.address.toLowerCase().contains(needle) ||
          customer.phone.contains(needle) ||
          customer.memo.toLowerCase().contains(needle);
    }).toList();
    items.sort((a, b) => _order(a.statusId).compareTo(_order(b.statusId)));
    return items;
  }

  int _order(String statusId) {
    final status = statuses.cast<CustomerStatus?>().firstWhere((item) => item!.id == statusId, orElse: () => null);
    return status?.sortOrder ?? 99;
  }

  CustomerStatus? statusOf(String id) {
    for (final status in statuses) {
      if (status.id == id) return status;
    }
    return null;
  }

  Future<void> bootstrap() async {
    try {
      customers = await repo.loadCustomers();
      statuses = await repo.loadStatuses();
      tiers = await repo.loadPriceTiers();
      conflicts = await repo.loadConflicts();
    } catch (error) {
      startupError = '$error';
    }
    notifyListeners();
  }

  void showToast(String message) {
    toast = message;
    notifyListeners();
  }

  void clearToast() {
    toast = null;
    notifyListeners();
  }

  void setQuery(String value) {
    query = value;
    notifyListeners();
  }

  void toggleStatus(String id) {
    if (hiddenFilters.contains(id)) {
      hiddenFilters.remove(id);
    } else {
      hiddenFilters.add(id);
    }
    notifyListeners();
  }

  void selectCustomer(String id) {
    selectedId = id;
    sheet = SheetLevel.half;
    placingPin = false;
    notifyListeners();
  }

  void setSheet(SheetLevel level) {
    sheet = level;
    if (level == SheetLevel.closed) {
      selectedId = null;
      placingPin = false;
    }
    notifyListeners();
  }

  Future<void> refresh() async {
    customers = await repo.loadCustomers();
    statuses = await repo.loadStatuses();
    tiers = await repo.loadPriceTiers();
    conflicts = await repo.loadConflicts();
    notifyListeners();
  }

  CustomerDraft draftOf(Customer customer) => CustomerDraft(
    name: customer.name,
    phone: customer.phone,
    address: customer.address,
    memo: customer.memo,
    contractDate: customer.contractDate == null
        ? ''
        : '${customer.contractDate!.year.toString().padLeft(4, '0')}-${customer.contractDate!.month.toString().padLeft(2, '0')}-${customer.contractDate!.day.toString().padLeft(2, '0')}',
    price: customer.unitPrice,
    statusId: customer.statusId,
    lat: customer.lat,
    lng: customer.lng,
    locationSource: customer.locationSource,
  );

  Future<void> saveExisting(Customer original, CustomerDraft draft) async {
    final validation = validateCustomer(draft);
    if (!validation.ok) {
      showToast('入力内容を確認してください');
      return;
    }
    busy = true;
    notifyListeners();
    var lat = draft.lat ?? original.lat;
    var lng = draft.lng ?? original.lng;
    var source = original.locationSource;
    final moved = draft.address.trim() != original.address.trim();
    if (moved) {
      final hits = await geocoder.geocode(draft.address.trim());
      if (hits.length == 1) {
        final hit = hits.single;
        var useGeocode = true;
        if (original.locationSource == 'manual' && original.lat != null && original.lng != null && shouldAskLocationChoice(manualLat: original.lat!, manualLng: original.lng!, geocodedLat: hit.lat, geocodedLng: hit.lng)) {
          final meters = distanceMeters(original.lat!, original.lng!, hit.lat, hit.lng);
          final choice = await choose?.call('位置が${meters.round()}m離れています', ['手動で置いたピンを使う', '住所から求めた位置を使う']);
          useGeocode = choice == 1;
        }
        if (useGeocode) {
          lat = hit.lat;
          lng = hit.lng;
          source = 'geocoded';
        } else {
          source = 'manual';
        }
      } else if (hits.length > 1) {
        final index = await choose?.call('住所の候補', hits.map((hit) => hit.formattedAddress).toList());
        if (index != null && index >= 0 && index < hits.length) {
          lat = hits[index].lat;
          lng = hits[index].lng;
          source = 'geocoded';
        }
      } else {
        source = lat == null ? 'pending' : 'manual';
        placingPin = true;
        showToast('住所を位置に変換できませんでした。地図を長押ししてピンを置いてください');
      }
    }
    final saved = original.copyWith(
      name: draft.name.trim(),
      phone: formatJpPhone(draft.phone),
      address: draft.address.trim(),
      memo: draft.memo.trim(),
      statusId: draft.statusId,
      lat: lat,
      lng: lng,
      locationSource: source,
      contractDate: DateTime.tryParse(draft.contractDate),
      unitPrice: draft.price,
      pendingSync: !repo.isOnline,
    );
    final stored = await repo.saveCustomer(saved);
    customers = await repo.loadCustomers();
    selectedId = stored.id;
    sheet = SheetLevel.half;
    busy = false;
    if (toast == null || !placingPin) {
      showToast(moved ? '住所変更を検知し再ジオコーディングしました。ピン位置を確認してください' : '保存しました');
    } else {
      notifyListeners();
    }
  }

  Future<Customer?> createCustomer(CustomerDraft draft, {String format = 'template', double? confidence, bool appendToExisting = true}) async {
    final validation = validateCustomer(draft, requireLocation: draft.lat == null);
    if (!validation.ok) {
      showToast(validation.errors.values.join(' / '));
      return null;
    }
    if (appendToExisting) {
      final duplicate = _duplicate(draft);
      if (duplicate != null) {
        final choice = await choose?.call('${duplicate.name} と名前または電話番号が一致します', ['既存の顧客に契約を追加', '新規作成']);
        if (choice == 0) {
          final updated = duplicate.copyWith(
            contractDate: DateTime.tryParse(draft.contractDate),
            unitPrice: draft.price,
            contractFormat: format,
            ocrConfidence: confidence,
            address: draft.address.trim(),
            memo: draft.memo.trim().isEmpty ? duplicate.memo : draft.memo.trim(),
            lat: draft.lat ?? duplicate.lat,
            lng: draft.lng ?? duplicate.lng,
            locationSource: draft.lat == null ? duplicate.locationSource : draft.locationSource,
          );
          final stored = await repo.saveCustomer(updated, appendContract: true);
          await refresh();
          selectCustomer(stored.id);
          showToast('既存の顧客に契約を追加しました');
          return stored;
        }
      }
    }
    final me = repo.session;
    final customer = Customer(
      id: _ids.v4(),
      orgId: me?.orgId ?? '',
      ownerId: me?.userId ?? '',
      ownerName: me?.displayName ?? '',
      name: draft.name.trim(),
      phone: formatJpPhone(draft.phone),
      address: draft.address.trim(),
      memo: draft.memo.trim(),
      lat: draft.lat,
      lng: draft.lng,
      locationSource: draft.locationSource,
      statusId: draft.statusId,
      version: 1,
      updatedAt: DateTime.now(),
      contractId: _ids.v4(),
      contractDate: DateTime.tryParse(draft.contractDate),
      unitPrice: draft.price,
      contractFormat: format,
      ocrConfidence: confidence,
      pendingSync: !repo.isOnline,
      sharedWithMe: false,
    );
    final stored = await repo.saveCustomer(customer, creating: true);
    await refresh();
    selectCustomer(stored.id);
    showToast(draft.locationSource == 'manual' ? 'ピンを追加しました' : '住所を位置情報に変換し、ピンを追加しました');
    return stored;
  }

  Customer? _duplicate(CustomerDraft draft) {
    final phone = digitsOnly(draft.phone);
    for (final customer in customers) {
      if (customer.name.trim() == draft.name.trim() || (phone.isNotEmpty && digitsOnly(customer.phone) == phone)) {
        return customer;
      }
    }
    return null;
  }

  void moveSelectedPin(double lat, double lng) {
    final current = selected;
    if (current == null) return;
    final index = customers.indexWhere((customer) => customer.id == current.id);
    if (index < 0) return;
    customers[index] = current.copyWith(lat: lat, lng: lng, locationSource: 'manual');
    placingPin = false;
    notifyListeners();
  }

  Future<void> persistSelectedPin() async {
    final current = selected;
    if (current == null) return;
    await repo.saveCustomer(current);
    await refresh();
    showToast('ピン位置を保存しました');
  }

  Future<List<String>> suggest(String query) => geocoder.suggest(query);
}
