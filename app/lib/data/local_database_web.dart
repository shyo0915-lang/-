import 'dart:convert';

import 'package:sembast_web/sembast_web.dart';

import '../logic/status_rules.dart';
import '../models/models.dart';
import 'local_database_codec.dart';

/// Safari の IndexedDB に顧客・送信キュー・競合を置く。
class LocalDatabase {
  LocalDatabase(this._db);
  final Database _db;

  static final _customers = stringMapStoreFactory.store('customers');
  static final _statuses = stringMapStoreFactory.store('statuses');
  static final _meta = stringMapStoreFactory.store('meta');
  static final _conflicts = stringMapStoreFactory.store('conflicts');
  static final _queue = intMapStoreFactory.store('sync_queue');

  static Future<LocalDatabase> open() async {
    final database = await databaseFactoryWeb.openDatabase('field_sales');
    return LocalDatabase(database);
  }

  Future<void> upsertCustomer(Customer customer, {String? baseJson, bool? pending}) async {
    await _customers.record(customer.id).put(_db, {
      'json': jsonEncode(customerToJson(customer)),
      'pending': (pending ?? customer.pendingSync) ? 1 : 0,
      'base_json': baseJson,
    });
  }

  Future<List<Customer>> customers() async {
    final rows = await _customers.find(_db);
    return rows.map((row) => customerFromJson(decodeMap(row.value['json']! as String))).toList();
  }

  Future<Customer?> customer(String id) async {
    final row = await _customers.record(id).get(_db);
    if (row == null) return null;
    return customerFromJson(decodeMap(row['json']! as String));
  }

  Future<String?> baseJson(String id) async {
    final row = await _customers.record(id).get(_db);
    return row?['base_json'] as String?;
  }

  Future<void> deleteCustomer(String id) async {
    await _customers.record(id).delete(_db);
  }

  Future<void> saveStatuses(List<CustomerStatus> statuses) async {
    await _statuses.delete(_db);
    for (final status in statuses) {
      await _statuses.record(status.id).put(_db, {'json': jsonEncode(statusToJson(status))});
    }
  }

  Future<List<CustomerStatus>> statuses() async {
    final rows = await _statuses.find(_db);
    return rows.map((row) => statusFromJson(decodeMap(row.value['json']! as String))).toList();
  }

  Future<void> setMeta(String key, String value) async {
    await _meta.record(key).put(_db, {'value': value});
  }

  Future<String?> meta(String key) async {
    final row = await _meta.record(key).get(_db);
    return row?['value'] as String?;
  }

  Future<void> enqueue(String op, Map<String, Object?> payload) async {
    await _queue.add(_db, {'op': op, 'payload': jsonEncode(payload)});
  }

  Future<List<Map<String, Object?>>> queue() async {
    final rows = await _queue.find(_db, finder: Finder(sortOrders: [SortOrder(Field.key, true)]));
    return rows
        .map((row) => {
          'id': row.key,
          'op': row.value['op'],
          'payload': jsonDecode(row.value['payload']! as String),
        })
        .toList();
  }

  Future<void> removeQueue(int id) async {
    await _queue.record(id).delete(_db);
  }

  Future<void> saveConflicts(List<SyncConflict> conflicts) async {
    await _conflicts.delete(_db);
    for (final conflict in conflicts) {
      await _conflicts.record(conflict.id).put(_db, {
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
  }

  Future<List<SyncConflict>> conflicts() async {
    final rows = await _conflicts.find(_db);
    return rows.map((row) {
      final json = decodeMap(row.value['json']! as String);
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
