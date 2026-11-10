import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../logic/status_rules.dart';
import '../models/models.dart';
import 'local_database_codec.dart';

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
        await db.execute('create table conflicts (id text primary key, json text not null)');
        await db.execute('create table sync_queue (id integer primary key autoincrement, op text not null, payload text not null)');
      },
    );
    return LocalDatabase(database);
  }

  Future<void> upsertCustomer(Customer customer, {String? baseJson, bool? pending}) async {
    await db.insert('customers', {
      'id': customer.id,
      'json': jsonEncode(customerToJson(customer)),
      'pending': (pending ?? customer.pendingSync) ? 1 : 0,
      'base_json': baseJson,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Customer>> customers() async {
    final rows = await db.query('customers');
    return rows.map((row) => customerFromJson(decodeMap(row['json']! as String))).toList();
  }

  Future<Customer?> customer(String id) async {
    final rows = await db.query('customers', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return customerFromJson(decodeMap(rows.first['json']! as String));
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
      await db.insert('statuses', {'id': status.id, 'json': jsonEncode(statusToJson(status))});
    }
  }

  Future<List<CustomerStatus>> statuses() async {
    final rows = await db.query('statuses');
    return rows.map((row) => statusFromJson(decodeMap(row['json']! as String))).toList();
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
      final json = decodeMap(row['json']! as String);
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
