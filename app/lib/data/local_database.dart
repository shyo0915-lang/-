import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../logic/price_tiers.dart';
import '../logic/status_rules.dart';
import '../models/models.dart';

class LocalDatabase {
  LocalDatabase(this.db);
  final Database db;

  static Future<LocalDatabase> open() async {
    final path = p.join(await getDatabasesPath(), 'field_sales.db');
    final database = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          create table customers (
            id text primary key,
            json text not null,
            pending integer not null default 0,
            base_json text
          )
        ''');
        await db.execute('create table statuses (id text primary key, json text not null)');
        await db.execute('create table meta (key text primary key, value text not null)');
        await db.execute('create table shares (customer_id text, user_id text, json text not null, primary key (customer_id, user_id))');
        await db.execute('create table conflicts (id text primary key, json text not null)');
        await db.execute('create table sync_queue (id integer primary key autoincrement, op text not null, payload text not null)');
      },
    );
    return LocalDatabase(database);
  }

  Future<void> upsertCustomer(Customer customer, {String? baseJson, bool? pending}) async {
    await db.insert('customers', {
      'id': customer.id,
      'json': jsonEncode(_customerJson(customer)),
      'pending': (pending ?? customer.pendingSync) ? 1 : 0,
      'base_json': baseJson,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Customer>> customers() async {
    final rows = await db.query('customers');
    return rows.map((row) => _customerFrom(jsonDecode(row['json']! as String) as Map<String, dynamic>)).toList();
  }

  Future<Customer?> customer(String id) async {
    final rows = await db.query('customers', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return _customerFrom(jsonDecode(rows.first['json']! as String) as Map<String, dynamic>);
  }

  Future<String?> baseJson(String id) async {
    final rows = await db.query('customers', columns: ['base_json'], where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return rows.first['base_json'] as String?;
  }

  Future<void> deleteCustomer(String id) async {
    await db.delete('customers', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> saveStatuses(List<CustomerStatus> statuses) async {
    await db.delete('statuses');
    for (final status in statuses) {
      await db.insert('statuses', {'id': status.id, 'json': jsonEncode(_statusJson(status))});
    }
  }

  Future<List<CustomerStatus>> statuses() async {
    final rows = await db.query('statuses');
    return rows.map((row) => _statusFrom(jsonDecode(row['json']! as String) as Map<String, dynamic>)).toList();
  }

  Future<void> setMeta(String key, String value) async {
    await db.insert('meta', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> meta(String key) async {
    final rows = await db.query('meta', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> enqueue(String op, Map<String, Object?> payload) async {
    await db.insert('sync_queue', {'op': op, 'payload': jsonEncode(payload)});
  }

  Future<List<Map<String, Object?>>> queue() async {
    final rows = await db.query('sync_queue', orderBy: 'id');
    return rows
        .map((row) => {
          'id': row['id'],
          'op': row['op'],
          'payload': jsonDecode(row['payload']! as String),
        })
        .toList();
  }

  Future<void> removeQueue(int id) async {
    await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> saveConflicts(List<SyncConflict> conflicts) async {
    final batch = db.batch();
    batch.delete('conflicts');
    for (final conflict in conflicts) {
      batch.insert('conflicts', {
        'id': conflict.id,
        'json': jsonEncode({
          'id': conflict.id,
          'customerId': conflict.customerId,
          'customerName': conflict.customerName,
          'field': conflict.field,
          'deviceValue': conflict.deviceValue,
          'serverValue': conflict.serverValue,
        }),
      });
    }
    await batch.commit(noResult: true);
  }

  Future<List<SyncConflict>> conflicts() async {
    final rows = await db.query('conflicts');
    return rows.map((row) {
      final json = jsonDecode(row['json']! as String) as Map<String, dynamic>;
      return SyncConflict(
        id: json['id'] as String,
        customerId: json['customerId'] as String,
        customerName: json['customerName'] as String? ?? '',
        field: json['field'] as String,
        deviceValue: json['deviceValue'] as String? ?? '',
        serverValue: json['serverValue'] as String? ?? '',
      );
    }).toList();
  }
}

Map<String, Object?> _customerJson(Customer customer) => {
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
  'pendingSync': customer.pendingSync,
  'sharedWithMe': customer.sharedWithMe,
  'updatedByName': customer.updatedByName,
  'baseVersion': customer.baseVersion,
};

Customer _customerFrom(Map<String, dynamic> json) {
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
    pendingSync: json['pendingSync'] as bool? ?? false,
    sharedWithMe: json['sharedWithMe'] as bool? ?? false,
    updatedByName: json['updatedByName'] as String?,
    baseVersion: json['baseVersion'] as int?,
  );
}

Map<String, Object?> _statusJson(CustomerStatus status) => {
  'id': status.id,
  'label': status.label,
  'colorHex': status.colorHex,
  'shape': status.shape,
  'sortOrder': status.sortOrder,
  'isDefault': status.isDefault,
  'hidden': status.hidden,
};

CustomerStatus _statusFrom(Map<String, dynamic> json) => CustomerStatus(
  id: json['id'] as String,
  label: json['label'] as String? ?? '',
  colorHex: json['colorHex'] as String? ?? '#1A73E8',
  shape: json['shape'] as String? ?? 'check',
  sortOrder: json['sortOrder'] as int? ?? 0,
  isDefault: json['isDefault'] as bool? ?? false,
  hidden: json['hidden'] as bool? ?? false,
);

String encodeTier(PriceTierConfig config) => jsonEncode({'boundaries': config.boundaries, 'personal': config.personal});

PriceTierConfig decodeTier(String raw) {
  final json = jsonDecode(raw) as Map<String, dynamic>;
  return PriceTierConfig(List<int>.from(json['boundaries'] as List), personal: json['personal'] as bool? ?? false);
}
