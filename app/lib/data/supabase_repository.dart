import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config.dart';
import '../services/image_vault.dart';
import '../logic/price_tiers.dart';
import '../logic/status_rules.dart';
import '../logic/sync_merge.dart';
import '../logic/text_parse.dart';
import '../models/models.dart';
import 'local_database.dart';
import 'repository.dart';

class SupabaseAppRepository implements AppRepository {
  SupabaseAppRepository(this.client, this.config, this.local);

  final SupabaseClient client;
  final AppConfig config;
  final LocalDatabase local;
  AppSession? _session;
  bool _online = true;
  List<CustomerStatus> _statuses = [];
  PriceTierConfig _tiers = PriceTierConfig.defaults;

  @override
  bool get sampleMode => false;

  @override
  AppSession? get session => _session;

  @override
  bool get isOnline => _online;

  @override
  void setConnectivity(bool online) => _online = online;

  @override
  Future<void> init() async {
    final current = client.auth.currentSession;
    if (current != null) {
      await _loadProfile(current.user.id, current.user.email);
      await sync();
    }
  }

  Future<void> _loadProfile(String userId, String? email) async {
    final row = await client.from('profiles').select('id, org_id, display_name, role, active').eq('id', userId).maybeSingle();
    if (row == null) {
      throw StateError('プロフィールがありません。組織名を付けて登録し直してください。');
    }
    if (row['active'] != true) {
      throw StateError('このアカウントは無効です');
    }
    _session = AppSession(
      userId: userId,
      displayName: row['display_name'] as String? ?? email ?? '',
      orgId: row['org_id'] as String,
      role: row['role'] as String? ?? 'member',
    );
  }

  @override
  Future<String?> signIn(String email, String password) async {
    try {
      final result = await client.auth.signInWithPassword(email: email.trim(), password: password);
      final user = result.user;
      if (user == null) return 'ログインできませんでした';
      await _loadProfile(user.id, user.email);
      await sync();
      return null;
    } catch (error) {
      return _humanize(error);
    }
  }

  @override
  Future<String?> signUp({
    required String email,
    required String password,
    required String displayName,
    required String orgName,
  }) async {
    try {
      final result = await client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'display_name': displayName.trim(), 'org_name': orgName.trim()},
      );
      if (result.session == null) {
        return '確認メールを送信しました。メールの手順を終えてからログインしてください。';
      }
      await _loadProfile(result.user!.id, result.user!.email);
      await sync();
      return null;
    } catch (error) {
      return _humanize(error);
    }
  }

  @override
  Future<void> signOut() async {
    await client.auth.signOut();
    _session = null;
  }

  @override
  Future<List<Customer>> loadCustomers() => local.customers();

  @override
  Future<List<CustomerStatus>> loadStatuses() async {
    if (_statuses.isEmpty) {
      _statuses = await local.statuses();
    }
    _statuses.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return _statuses;
  }

  @override
  Future<PriceTierConfig> loadPriceTiers() async {
    final raw = await local.meta('price_tiers');
    if (raw != null) _tiers = decodeTier(raw);
    return _tiers;
  }

  @override
  Future<Customer> saveCustomer(Customer customer, {bool creating = false, bool appendContract = false}) async {
    final pending = customer.copyWith(pendingSync: true);
    final base = creating ? jsonEncode(pending.toSyncMap()) : await local.baseJson(customer.id);
    await local.upsertCustomer(pending, baseJson: base, pending: true);
    await local.enqueue('save_customer', {
      'creating': creating,
      'appendContract': appendContract,
      'customer': _customerJsonPublic(pending),
    });
    await sync();
    return (await local.customer(customer.id)) ?? pending;
  }

  @override
  Future<void> archiveCustomer(String id) async {
    await local.enqueue('archive', {'id': id});
    await local.deleteCustomer(id);
    await sync();
  }

  @override
  Future<String?> saveStatus(CustomerStatus status, {bool creating = false}) async {
    final current = await loadStatuses();
    final message = validateStatusEdit(current, status);
    if (message != null) return message;
    if (creating) {
      _statuses = [...current, status];
    } else {
      _statuses = current.map((item) => item.id == status.id ? status : item).toList();
    }
    await local.saveStatuses(_statuses);
    await local.enqueue('save_status', {'creating': creating, 'status': _statusMap(status)});
    await sync();
    return null;
  }

  @override
  Future<String?> deleteStatus(String id, {String? moveToStatusId}) async {
    await local.enqueue('delete_status', {'id': id, 'moveTo': moveToStatusId});
    final report = await sync();
    if (report.message.contains('失敗') || report.message.contains('使用中') || report.message.contains('削除')) {
      if (report.pushed == 0 && report.message != '同期しました') return report.message;
    }
    await _pullStatuses();
    return null;
  }

  @override
  Future<void> reorderStatuses(List<String> orderedIds) async {
    final current = await loadStatuses();
    final next = <CustomerStatus>[];
    for (var i = 0; i < orderedIds.length; i++) {
      final status = current.cast<CustomerStatus?>().firstWhere((item) => item!.id == orderedIds[i], orElse: () => null);
      if (status != null) next.add(status.copyWith(sortOrder: i));
    }
    _statuses = next;
    await local.saveStatuses(next);
    for (final status in next) {
      await local.enqueue('save_status', {'creating': false, 'status': _statusMap(status)});
    }
    await sync();
  }

  @override
  Future<String?> savePriceTiers(PriceTierConfig config) async {
    final message = config.validate();
    if (message != null) return message;
    _tiers = PriceTierConfig(List<int>.from(config.boundaries), personal: true);
    await local.setMeta('price_tiers', encodeTier(_tiers));
    await local.enqueue('save_tiers', {'boundaries': _tiers.boundaries});
    await sync();
    return null;
  }

  @override
  Future<List<OrgMember>> loadMembers() async {
    final me = _session;
    if (me == null) return const [];
    final rows = await client.from('profiles').select('id, display_name, role, active').eq('org_id', me.orgId);
    return (rows as List).map((item) {
      final row = item as Map<String, dynamic>;
      return OrgMember(
        id: row['id'] as String,
        displayName: row['display_name'] as String? ?? '',
        role: row['role'] as String? ?? 'member',
        active: row['active'] as bool? ?? false,
      );
    }).toList();
  }

  @override
  Future<List<CustomerShare>> loadShares(String customerId) async {
    final rows = await client.from('customer_shares').select('customer_id, user_id, role, expires_at').eq('customer_id', customerId);
    final members = {for (final member in await loadMembers()) member.id: member};
    return (rows as List).map((item) {
      final row = item as Map<String, dynamic>;
      final userId = row['user_id'] as String;
      return CustomerShare(
        customerId: customerId,
        userId: userId,
        userName: members[userId]?.displayName ?? userId,
        role: row['role'] as String? ?? 'viewer',
        expiresAt: DateTime.tryParse(row['expires_at'] as String? ?? ''),
      );
    }).toList();
  }

  @override
  Future<String?> invite({
    required String customerId,
    required String userId,
    required String role,
    DateTime? expiresAt,
  }) async {
    try {
      await client.from('customer_shares').upsert({
        'customer_id': customerId,
        'user_id': userId,
        'role': role,
        'expires_at': expiresAt?.toIso8601String(),
        'invited_by': _session?.userId,
      });
      return null;
    } catch (error) {
      if (!_online || _isOfflineError(error)) {
        await local.enqueue('invite', {
          'customerId': customerId,
          'userId': userId,
          'role': role,
          'expiresAt': expiresAt?.toIso8601String(),
        });
        return null;
      }
      return _humanize(error);
    }
  }

  @override
  Future<String?> revokeShare(String customerId, String userId) async {
    try {
      await client.from('customer_shares').delete().eq('customer_id', customerId).eq('user_id', userId);
      return null;
    } catch (error) {
      return _humanize(error);
    }
  }

  @override
  Future<List<SyncConflict>> loadConflicts() => local.conflicts();

  @override
  Future<void> resolveConflict({required SyncConflict conflict, required bool useDevice}) async {
    final conflicts = await local.conflicts();
    final rest = conflicts.where((item) => item.id != conflict.id).toList();
    await local.saveConflicts(rest);
    if (!useDevice) return;
    final customer = await local.customer(conflict.customerId);
    if (customer == null) return;
    final updated = _applyField(customer, conflict.field, conflict.deviceValue);
    await saveCustomer(updated);
  }

  @override
  Future<void> saveLocalImage(String customerId, String path) async {
    final customer = await local.customer(customerId);
    if (customer == null) return;
    final bytes = await ImageVault().read(path);
    if (bytes == null) return;
    await local.enqueue('upload_image', {
      'customerId': customerId,
      'contractId': customer.contractId,
      'path': path,
      'bytes': base64Encode(bytes),
    });
    await local.upsertCustomer(customer.copyWith(imageLocalPath: path, pendingSync: true), baseJson: await local.baseJson(customerId), pending: true);
    await sync();
  }

  @override
  Future<SyncReport> sync() async {
    if (_session == null) return const SyncReport(pushed: 0, conflicts: 0, message: '未ログインです');
    if (!_online) return const SyncReport(pushed: 0, conflicts: 0, message: 'オフラインです。復帰後に同期します');
    var pushed = 0;
    var conflicts = 0;
    try {
      final queue = await local.queue();
      for (final item in queue) {
        final id = item['id'] as int;
        final op = item['op'] as String;
        final payload = item['payload'] as Map<String, dynamic>;
        final result = await _applyOp(op, payload);
        conflicts += result;
        await local.removeQueue(id);
        pushed += 1;
      }
      await _pull();
    } catch (error) {
      return SyncReport(pushed: pushed, conflicts: conflicts, message: _humanize(error));
    }
    final noun = conflicts == 0 ? '同期しました' : '同期しました。確認が必要な競合が $conflicts 件あります';
    return SyncReport(pushed: pushed, conflicts: conflicts, message: noun);
  }

  Future<int> _applyOp(String op, Map<String, dynamic> payload) async {
    switch (op) {
      case 'save_customer':
        return _pushCustomer(payload);
      case 'archive':
        await client.from('customers').update({'deleted_at': DateTime.now().toIso8601String()}).eq('id', payload['id']);
        return 0;
      case 'save_status':
        final status = Map<String, dynamic>.from(payload['status'] as Map);
        if (payload['creating'] == true) {
          status['org_id'] = _session!.orgId;
          status['is_default'] = false;
          await client.from('statuses').insert(status);
        } else {
          status.remove('is_default');
          await client.from('statuses').update(status).eq('id', status['id']);
        }
        return 0;
      case 'delete_status':
        if (payload['moveTo'] != null) {
          await client.from('customers').update({'status_id': payload['moveTo']}).eq('status_id', payload['id']);
        }
        await client.from('statuses').delete().eq('id', payload['id']);
        return 0;
      case 'save_tiers':
        final me = _session!;
        final boundaries = List<int>.from(payload['boundaries'] as List);
        final existing = await client.from('price_tiers').select('id').eq('user_id', me.userId).maybeSingle();
        if (existing == null) {
          await client.from('price_tiers').insert({'org_id': me.orgId, 'user_id': me.userId, 'boundaries': boundaries});
        } else {
          await client.from('price_tiers').update({'boundaries': boundaries}).eq('id', existing['id']);
        }
        return 0;
      case 'invite':
        await client.from('customer_shares').upsert({
          'customer_id': payload['customerId'],
          'user_id': payload['userId'],
          'role': payload['role'],
          'expires_at': payload['expiresAt'],
          'invited_by': _session?.userId,
        });
        return 0;
      case 'upload_image':
        await _uploadImage(payload);
        return 0;
      default:
        return 0;
    }
  }

  Future<int> _pushCustomer(Map<String, dynamic> payload) async {
    final customer = _customerFromPublic(payload['customer'] as Map<String, dynamic>);
    final creating = payload['creating'] == true;
    final row = {
      'name': customer.name.trim(),
      'phone': formatJpPhone(customer.phone),
      'address': customer.address.trim(),
      'memo': customer.memo.trim().isEmpty ? null : customer.memo.trim(),
      'lat': customer.lat,
      'lng': customer.lng,
      'location_source': customer.locationSource,
      'status_id': customer.statusId,
    };
    if (creating) {
      await client.from('customers').insert({
        'id': customer.id,
        'org_id': customer.orgId,
        'owner_id': customer.ownerId,
        ...row,
      });
      await _writeContract(customer, append: true);
      return 0;
    }
    try {
      await client.from('customers').update({...row, 'version': customer.version}).eq('id', customer.id);
      await _writeContract(customer, append: payload['appendContract'] == true);
      return 0;
    } on PostgrestException catch (error) {
      if (!error.message.contains('version_conflict')) rethrow;
      return _recordConflict(customer);
    }
  }

  Future<int> _recordConflict(Customer device) async {
    final server = await _fetchCustomer(device.id);
    if (server == null) return 0;
    final baseRaw = await localBaseMap(device.id);
    final merged = mergeCustomerFields(base: baseRaw, local: device.toSyncMap(), server: server.toSyncMap());
    final conflicts = <SyncConflict>[
      for (final conflict in merged.conflicts)
        SyncConflict(
          id: const Uuid().v4(),
          customerId: device.id,
          customerName: device.name,
          field: conflict.field,
          deviceValue: '${conflict.deviceValue ?? ''}',
          serverValue: '${conflict.serverValue ?? ''}',
        ),
    ];
    final existing = await localConflicts();
    await local.saveConflicts([...existing, ...conflicts]);
    final kept = _customerFromSync(server, merged.merged).copyWith(pendingSync: false, version: server.version);
    await local.upsertCustomer(kept, baseJson: jsonEncode(kept.toSyncMap()), pending: false);
    if (merged.conflicts.isEmpty) {
      await client.from('customers').update({
        'name': kept.name,
        'phone': kept.phone,
        'address': kept.address,
        'memo': kept.memo.isEmpty ? null : kept.memo,
        'status_id': kept.statusId,
        'lat': kept.lat,
        'lng': kept.lng,
        'location_source': kept.locationSource,
        'version': server.version,
      }).eq('id', kept.id);
    }
    for (final conflict in conflicts) {
      await client.from('sync_conflicts').insert({
        'customer_id': conflict.customerId,
        'field': conflict.field,
        'device_value': conflict.deviceValue,
        'server_value': conflict.serverValue,
      });
    }
    return conflicts.length;
  }

  Future<Map<String, Object?>> localBaseMap(String id) async {
    final raw = await local.baseJson(id);
    if (raw == null || raw.isEmpty) return {};
    return Map<String, Object?>.from(jsonDecode(raw) as Map);
  }

  Future<List<SyncConflict>> localConflicts() => local.conflicts();

  Future<void> _writeContract(Customer customer, {required bool append}) async {
    final body = {
      'customer_id': customer.id,
      'contract_date': _isoDate(customer.contractDate),
      'unit_price': customer.unitPrice < 1 ? 1 : customer.unitPrice,
      'format': customer.contractFormat,
      'ocr_confidence': customer.ocrConfidence,
    };
    if (append || customer.contractId == null) {
      await client.from('contracts').insert({
        if (customer.contractId != null) 'id': customer.contractId,
        ...body,
      });
    } else {
      await client.from('contracts').update(body).eq('id', customer.contractId!);
    }
  }

  Future<void> _uploadImage(Map<String, dynamic> payload) async {
    final Uint8List bytes = base64Decode(payload['bytes'] as String);
    final customerId = payload['customerId'] as String;
    final contractId = payload['contractId'] as String? ?? customerId;
    final me = _session!;
    final path = '${me.orgId}/$customerId/$contractId/1.jpg';
    await client.storage.from('contract-images').uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
    );
    await client.from('contract_images').insert({'contract_id': contractId, 'storage_path': path, 'page_no': 1});
  }

  Future<void> _pull() async {
    await _pullStatuses();
    await _pullTiers();
    final rows = await client.from('customers').select('''
      id, org_id, owner_id, name, phone, address, memo, lat, lng, location_source, status_id, version, updated_at,
      contracts (id, contract_date, unit_price, format, ocr_confidence, created_at, contract_images (storage_path, page_no))
    ''').isFilter('deleted_at', null);
    final members = {for (final member in await loadMembers()) member.id: member.displayName};
    final me = _session!.userId;
    final remoteIds = <String>{};
    for (final item in rows as List) {
      final row = item as Map<String, dynamic>;
      final id = row['id'] as String;
      remoteIds.add(id);
      final existing = await local.customer(id);
      if (existing != null && existing.pendingSync) continue;
      final customer = _customerFromRemote(row, members, me);
      await local.upsertCustomer(customer, baseJson: jsonEncode(customer.toSyncMap()), pending: false);
    }
    for (final customer in await local.customers()) {
      if (!customer.pendingSync && !remoteIds.contains(customer.id)) {
        await local.deleteCustomer(customer.id);
      }
    }
  }

  Future<void> _pullStatuses() async {
    final rows = await client.from('statuses').select('id, label, color, shape, sort_order, is_default, hidden');
    _statuses = (rows as List).map((item) {
      final row = item as Map<String, dynamic>;
      return CustomerStatus(
        id: row['id'] as String,
        label: row['label'] as String,
        colorHex: row['color'] as String,
        shape: row['shape'] as String,
        sortOrder: row['sort_order'] as int? ?? 0,
        isDefault: row['is_default'] as bool? ?? false,
        hidden: row['hidden'] as bool? ?? false,
      );
    }).toList();
    await local.saveStatuses(_statuses);
  }

  Future<void> _pullTiers() async {
    final me = _session!;
    final rows = await client.from('price_tiers').select('user_id, boundaries').eq('org_id', me.orgId);
    PriceTierConfig? personal;
    PriceTierConfig? orgDefault;
    for (final item in rows as List) {
      final row = item as Map<String, dynamic>;
      final boundaries = List<int>.from(row['boundaries'] as List);
      final config = PriceTierConfig(boundaries, personal: row['user_id'] != null);
      if (row['user_id'] == me.userId) personal = config;
      if (row['user_id'] == null) orgDefault = config;
    }
    _tiers = personal ?? orgDefault ?? PriceTierConfig.defaults;
    await local.setMeta('price_tiers', encodeTier(_tiers));
  }

  Future<Customer?> _fetchCustomer(String id) async {
    final row = await client.from('customers').select('''
      id, org_id, owner_id, name, phone, address, memo, lat, lng, location_source, status_id, version, updated_at,
      contracts (id, contract_date, unit_price, format, ocr_confidence, created_at)
    ''').eq('id', id).maybeSingle();
    if (row == null) return null;
    final members = {for (final member in await loadMembers()) member.id: member.displayName};
    return _customerFromRemote(row, members, _session!.userId);
  }

  Future<Uint8List?> downloadImage(String storagePath) async {
    final url = await client.storage.from('contract-images').createSignedUrl(storagePath, 60);
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) return null;
    return response.bodyBytes;
  }
}

Customer _customerFromRemote(Map<String, dynamic> row, Map<String, String> names, String me) {
  final contracts = ((row['contracts'] as List?) ?? const []).cast<Map<String, dynamic>>();
  contracts.sort((a, b) {
    final ad = a['contract_date'] as String? ?? '';
    final bd = b['contract_date'] as String? ?? '';
    return bd.compareTo(ad);
  });
  final contract = contracts.isEmpty ? null : contracts.first;
  String? imagePath;
  if (contract != null) {
    final images = ((contract['contract_images'] as List?) ?? const []).cast<Map<String, dynamic>>();
    if (images.isNotEmpty) imagePath = images.first['storage_path'] as String?;
  }
  final ownerId = row['owner_id'] as String? ?? '';
  return Customer(
    id: row['id'] as String,
    orgId: row['org_id'] as String? ?? '',
    ownerId: ownerId,
    ownerName: names[ownerId] ?? '',
    name: row['name'] as String? ?? '',
    phone: row['phone'] as String? ?? '',
    address: row['address'] as String? ?? '',
    memo: row['memo'] as String? ?? '',
    lat: (row['lat'] as num?)?.toDouble(),
    lng: (row['lng'] as num?)?.toDouble(),
    locationSource: row['location_source'] as String? ?? 'pending',
    statusId: row['status_id'] as String? ?? '',
    version: row['version'] as int? ?? 1,
    updatedAt: DateTime.tryParse(row['updated_at'] as String? ?? '') ?? DateTime.now(),
    contractId: contract?['id'] as String?,
    contractDate: DateTime.tryParse(contract?['contract_date'] as String? ?? ''),
    unitPrice: (contract?['unit_price'] as num?)?.toInt() ?? 0,
    contractFormat: contract?['format'] as String? ?? 'template',
    ocrConfidence: (contract?['ocr_confidence'] as num?)?.toDouble(),
    imageStoragePath: imagePath,
    pendingSync: false,
    sharedWithMe: ownerId != me,
    baseVersion: row['version'] as int? ?? 1,
  );
}

Customer _customerFromSync(Customer server, Map<String, Object?> merged) {
  final date = merged['contractDate'];
  return server.copyWith(
    name: merged['name'] as String? ?? server.name,
    phone: merged['phone'] as String? ?? server.phone,
    address: merged['address'] as String? ?? server.address,
    memo: merged['memo'] as String? ?? '',
    statusId: merged['statusId'] as String? ?? server.statusId,
    lat: merged['lat'] as double?,
    lng: merged['lng'] as double?,
    locationSource: merged['locationSource'] as String? ?? server.locationSource,
    contractDate: date is String && date.isNotEmpty ? DateTime.tryParse(date) : server.contractDate,
    unitPrice: merged['unitPrice'] as int? ?? server.unitPrice,
  );
}

Customer _applyField(Customer customer, String field, String value) {
  return switch (field) {
    'name' => customer.copyWith(name: value),
    'phone' => customer.copyWith(phone: value),
    'address' => customer.copyWith(address: value),
    'memo' => customer.copyWith(memo: value),
    'statusId' => customer.copyWith(statusId: value),
    'unitPrice' => customer.copyWith(unitPrice: int.tryParse(value) ?? customer.unitPrice),
    'contractDate' => customer.copyWith(contractDate: DateTime.tryParse(value)),
    _ => customer,
  };
}

String _isoDate(DateTime? date) {
  final value = date ?? DateTime.now();
  final y = value.year.toString().padLeft(4, '0');
  final m = value.month.toString().padLeft(2, '0');
  final d = value.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

Map<String, Object?> _statusMap(CustomerStatus status) => {
  'id': status.id,
  'label': status.label.trim(),
  'color': status.colorHex,
  'shape': status.shape,
  'sort_order': status.sortOrder,
  'is_default': status.isDefault,
  'hidden': status.hidden,
};

Map<String, Object?> _customerJsonPublic(Customer customer) => {
  'id': customer.id,
  'orgId': customer.orgId,
  'ownerId': customer.ownerId,
  'ownerName': customer.ownerName,
  'name': customer.name,
  'phone': customer.phone,
  'address': customer.address,
  'memo': customer.memo,
  'lat': customer.lat,
  'lng': customer.lng,
  'locationSource': customer.locationSource,
  'statusId': customer.statusId,
  'version': customer.version,
  'updatedAt': customer.updatedAt.toIso8601String(),
  'contractId': customer.contractId,
  'contractDate': customer.contractDate?.toIso8601String(),
  'unitPrice': customer.unitPrice,
  'contractFormat': customer.contractFormat,
  'ocrConfidence': customer.ocrConfidence,
  'imageLocalPath': customer.imageLocalPath,
  'imageStoragePath': customer.imageStoragePath,
  'sharedWithMe': customer.sharedWithMe,
};

Customer _customerFromPublic(Map<String, dynamic> json) {
  return Customer(
    id: json['id'] as String,
    orgId: json['orgId'] as String? ?? '',
    ownerId: json['ownerId'] as String? ?? '',
    ownerName: json['ownerName'] as String? ?? '',
    name: json['name'] as String? ?? '',
    phone: json['phone'] as String? ?? '',
    address: json['address'] as String? ?? '',
    memo: json['memo'] as String? ?? '',
    lat: (json['lat'] as num?)?.toDouble(),
    lng: (json['lng'] as num?)?.toDouble(),
    locationSource: json['locationSource'] as String? ?? 'pending',
    statusId: json['statusId'] as String? ?? '',
    version: json['version'] as int? ?? 1,
    updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
    contractId: json['contractId'] as String?,
    contractDate: DateTime.tryParse(json['contractDate'] as String? ?? ''),
    unitPrice: json['unitPrice'] as int? ?? 0,
    contractFormat: json['contractFormat'] as String? ?? 'template',
    ocrConfidence: (json['ocrConfidence'] as num?)?.toDouble(),
    imageLocalPath: json['imageLocalPath'] as String?,
    imageStoragePath: json['imageStoragePath'] as String?,
    pendingSync: true,
    sharedWithMe: json['sharedWithMe'] as bool? ?? false,
  );
}

bool _isOfflineError(Object error) {
  final text = error.toString();
  return text.contains('SocketException') || text.contains('Failed host lookup') || text.contains('ClientException') || text.contains('XMLHttpRequest');
}

String _humanize(Object error) {
  final text = error.toString();
  if (text.contains('version_conflict')) return '他の端末の更新と競合しました';
  if (text.contains('duplicate_appearance')) return '同じ色と形の組み合わせは使えません';
  if (text.contains('default_status_locked')) return '初期ステータスの名前と色の変更は管理者のみです';
  if (text.contains('status_limit')) return 'ステータスは10個までです';
  if (text.contains('status_in_use')) return '使用中のステータスです。移し替え先を選んでください';
  if (text.contains('archive_forbidden')) return 'アーカイブは担当者のみです';
  if (text.contains('Invalid login')) return 'メールアドレスかパスワードが違います';
  if (text.contains('row-level security') || text.contains('42501')) return 'この操作の権限がありません';
  if (_isOfflineError(error)) return 'オフラインです。復帰後に同期します';
  return '保存できませんでした: $text';
}
