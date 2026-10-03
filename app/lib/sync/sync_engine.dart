import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../data/db/database_helper.dart';
import '../services/api_client.dart';
import 'outbox.dart';

enum SyncStatus { idle, syncing, offline, error }

/// What to do with inventory already on this device when the shop on the
/// server has data too (e.g. second device, or reinstall).
enum LocalDataChoice { merge, discard }

/// A pushed change the server refused because another device changed the
/// same row first (a "conflict"), or rejected outright.
class SyncIssue {
  final int seq;
  final String table;
  final String op; // upsert | delete
  final String rowId;
  final String status; // conflict | rejected
  final String reason;
  final Map<String, Object?> mine;
  final Map<String, Object?>? theirs;
  const SyncIssue(this.seq, this.table, this.op, this.rowId, this.status,
      this.reason, this.mine, this.theirs);

  bool get serverDeleted => theirs?['deleted_at'] != null;
}

/// Keeps this device's inventory in step with the shop on the server.
///
/// Push the outbox, then pull changes. Edits carry the version the device
/// saw; a conflict means another device changed the row first — the
/// server's row is applied locally at once (so a stale price is never
/// shown) and the user's change waits in [issues] for "use theirs / keep
/// mine". Stock is never overwritten: qty = server qty + unsynced moves.
class SyncEngine extends ChangeNotifier {
  SyncEngine({
    required this.tokenProvider,
    required this.userKeyProvider,
    ApiClient? api,
    DatabaseHelper? db,
    Future<String> Function()? deviceId,
  })  : _api = api ?? ApiClient(),
        _db = db ?? DatabaseHelper.instance,
        _deviceIdFn = deviceId;

  final String? Function() tokenProvider;

  /// Identifies the signed-in account (email); local data is tied to it.
  final String? Function() userKeyProvider;
  final ApiClient _api;
  final DatabaseHelper _db;
  final Future<String> Function()? _deviceIdFn;

  /// Called after pulled changes were written, so screens reload.
  VoidCallback? onDataChanged;

  /// Set when this device has inventory and the server shop does too; the
  /// UI must ask the user and call [resolveLocalData].
  bool needsLocalDataChoice = false;

  SyncStatus status = SyncStatus.idle;
  DateTime? lastSuccess;
  String? lastError;
  int pending = 0;
  List<SyncIssue> issues = <SyncIssue>[];

  Timer? _periodic;
  Timer? _debounce;
  bool _running = false;
  bool _again = false;
  String? _deviceId;

  static const int _pushBatch = 200;
  static const int _pullLimit = 500;

  void start({Duration every = const Duration(seconds: 60)}) {
    Outbox.onEnqueued = () {
      _debounce?.cancel();
      _debounce = Timer(const Duration(seconds: 2), syncNow);
    };
    _periodic?.cancel();
    _periodic = Timer.periodic(every, (_) => syncNow());
    syncNow();
  }

  void stop() {
    _periodic?.cancel();
    _debounce?.cancel();
    Outbox.onEnqueued = null;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }

  /// One full cycle. Calls made while a cycle runs schedule one more.
  Future<void> syncNow() async {
    if (_running) {
      _again = true;
      return;
    }
    final String? token = tokenProvider();
    if (token == null || token.isEmpty) return;
    _running = true;
    _set(SyncStatus.syncing);
    try {
      _deviceId ??= await (_deviceIdFn?.call() ?? Future<String>.value('unknown'));
      final bool linked = await _ensureLinked(token);
      if (linked) {
        final bool pushed = await _push(token);
        final bool pulled = pushed && await _pull(token);
        if (pushed && pulled) {
          lastSuccess = DateTime.now();
          lastError = null;
          _set(SyncStatus.idle);
        }
      }
    } catch (e, st) {
      debugPrint('[Sync] failed: $e\n$st');
      lastError = '$e';
      _set(SyncStatus.error);
    } finally {
      _running = false;
      await _refreshCounts();
      notifyListeners();
      if (_again) {
        _again = false;
        unawaited(syncNow());
      }
    }
  }

  /// Seconds since the last successful sync, or null if never.
  int? get secondsSinceSync => lastSuccess == null
      ? null
      : DateTime.now().difference(lastSuccess!).inSeconds;

  // ---- account linking ---------------------------------------------------

  Future<bool> _ensureLinked(String token) async {
    final Database db = await _db.database;
    final String? me = userKeyProvider();
    final String? linked = await _state(db, 'linked_user');
    if (linked != null && linked == me) return true;
    if (needsLocalDataChoice) return false;

    if (linked != null && linked != me) {
      // Another account used this device before: its data is on the server
      // under that account, not this one.
      await _db.clearAll();
    }

    final ({int status, Map<String, dynamic>? body}) r =
        await _api.currentShop(token);
    if (!_ok(r.status)) return _offlineOrError(r.status);
    final bool serverHasData = r.body?['has_data'] == true;
    final bool localHasData = (Sqflite.firstIntValue(await db.rawQuery(
                'SELECT COUNT(*) FROM products WHERE is_deleted = 0')) ??
            0) >
        0;

    if (localHasData && serverHasData) {
      needsLocalDataChoice = true;
      notifyListeners();
      return false;
    }
    if (localHasData) await _queueAllLocal(db);
    await _setState(db, 'linked_user', me ?? '');
    return true;
  }

  /// Answer to [needsLocalDataChoice]: merge = upload this device's items
  /// alongside the shop's; discard = drop them and take the shop's data.
  Future<void> resolveLocalData(LocalDataChoice choice) async {
    final Database db = await _db.database;
    if (choice == LocalDataChoice.discard) {
      await _db.clearAll();
    } else {
      await _queueAllLocal(db);
    }
    await _setState(db, 'linked_user', userKeyProvider() ?? '');
    needsLocalDataChoice = false;
    notifyListeners();
    await syncNow();
    onDataChanged?.call();
  }

  /// First upload of inventory created before this device was linked
  /// (e.g. the v1 -> v2 migration).
  Future<void> _queueAllLocal(Database db) async {
    await db.transaction((Transaction txn) async {
      await txn.delete('outbox');
      for (final Map<String, Object?> p in await txn.query('products', where: 'is_deleted = 0')) {
        await Outbox.upsert(txn,
            table: 'products',
            rowId: p['id'] as String,
            rowVersion: 0,
            data: <String, Object?>{
              for (final String k in <String>[
                'name', 'manufacturer', 'category', 'composition', 'unit',
                'pack_size', 'hsn', 'gst_rate_bp', 'barcode',
                'low_stock_threshold_units', 'discount_bp', 'notes',
              ])
                k: p[k],
            });
      }
      for (final Map<String, Object?> b in await txn.rawQuery(
          'SELECT b.* FROM batches b JOIN products p ON p.id = b.product_id '
          'WHERE b.is_deleted = 0 AND p.is_deleted = 0')) {
        await Outbox.upsert(txn,
            table: 'batches',
            rowId: b['id'] as String,
            rowVersion: 0,
            data: <String, Object?>{
              'product_id': b['product_id'],
              'batch_no': b['batch_no'],
              'expiry_date': _ymd(b['expiry_date'] as int?),
              'mfg_date': _ymd(b['mfg_date'] as int?),
              'mrp_paise': b['mrp_paise'],
              'purchase_rate_paise': b['purchase_rate_paise'],
            });
      }
      for (final Map<String, Object?> m in await txn.rawQuery(
          'SELECT m.* FROM inv_movements m JOIN batches b ON b.id = m.batch_id '
          'WHERE m.synced = 0 AND b.is_deleted = 0')) {
        await Outbox.movement(txn, m['id'] as String, <String, Object?>{
          'batch_id': m['batch_id'],
          'delta_units': m['delta_units'],
          'reason': m['reason'],
          'ref_type': m['ref_type'],
          'occurred_at': DateTime.fromMillisecondsSinceEpoch(m['occurred_at'] as int)
              .toUtc()
              .toIso8601String(),
        });
      }
    });
  }

  // ---- push ----------------------------------------------------------------

  Future<bool> _push(String token) async {
    final Database db = await _db.database;
    while (true) {
      final List<Map<String, Object?>> rows = await db.query('outbox',
          where: "status = 'pending'", orderBy: 'seq', limit: _pushBatch);
      if (rows.isEmpty) return true;

      // One mutation per row per request: a later change to the same row
      // waits so it can be rebased on the version the earlier one produced.
      final Set<String> seen = <String>{};
      final List<Map<String, Object?>> send = <Map<String, Object?>>[];
      for (final Map<String, Object?> r in rows) {
        final String key = '${r['table_name']}:${r['row_id']}';
        if (seen.add(key)) send.add(r);
      }
      final List<Object?> seqs = send.map((Map<String, Object?> r) => r['seq']).toList();
      // Mark as attempted: no more merging into these (same mutation id is
      // retried after a network error; the server de-duplicates it).
      await db.rawUpdate(
          "UPDATE outbox SET result = '{\"sent\":1}' WHERE result IS NULL AND seq IN (${List<String>.filled(seqs.length, '?').join(',')})",
          seqs);

      final ({int status, Map<String, dynamic>? body}) r = await _api.syncPush(
        token,
        deviceId: _deviceId!,
        platform: Platform.operatingSystem,
        mutations: send.map(_toWire).toList(),
      );
      if (!_ok(r.status)) return _offlineOrError(r.status);

      final List<dynamic> results = (r.body?['results'] as List<dynamic>?) ?? <dynamic>[];
      await db.transaction((Transaction txn) async {
        for (int i = 0; i < send.length && i < results.length; i++) {
          await _applyResult(txn, send[i], Map<String, Object?>.from(results[i] as Map));
        }
      });
    }
  }

  Map<String, Object?> _toWire(Map<String, Object?> r) => <String, Object?>{
        'mutation_id': r['mutation_id'],
        'table': r['table_name'],
        'op': r['op'],
        'id': r['row_id'],
        'base_version': r['base_version'],
        'data': jsonDecode(r['data'] as String),
      };

  Future<void> _applyResult(
      Transaction txn, Map<String, Object?> sent, Map<String, Object?> res) async {
    final String table = sent['table_name'] as String;
    final String rowId = sent['row_id'] as String;
    final String status = (res['status'] as String?) ?? 'rejected';

    if (status == 'ok') {
      await txn.delete('outbox', where: 'seq = ?', whereArgs: <Object?>[sent['seq']]);
      final int version = (res['version'] as num?)?.toInt() ?? 0;
      if (table == 'stock_movements') {
        await txn.update('inv_movements', <String, Object?>{'synced': 1},
            where: 'id = ?', whereArgs: <Object?>[rowId]);
        final num? qty = res['batch_qty_units'] as num?;
        if (qty != null) {
          final Map<String, Object?> data =
              jsonDecode(sent['data'] as String) as Map<String, Object?>;
          await txn.update('batches', <String, Object?>{'server_qty_units': qty.toInt()},
              where: 'id = ?', whereArgs: <Object?>[data['batch_id']]);
        }
      } else {
        await txn.update(table, <String, Object?>{'version': version},
            where: 'id = ?', whereArgs: <Object?>[rowId]);
        // Later queued edits of this row were based on our own change.
        await txn.update('outbox', <String, Object?>{'base_version': version},
            where: "table_name = ? AND row_id = ? AND status = 'pending'",
            whereArgs: <Object?>[table, rowId]);
      }
      return;
    }

    await txn.update('outbox', <String, Object?>{'status': status, 'result': jsonEncode(res)},
        where: 'seq = ?', whereArgs: <Object?>[sent['seq']]);
    if (status == 'conflict' && res['row'] is Map) {
      // Show the server's truth right away; the user's change waits in issues.
      await _applyServerRow(txn, table, Map<String, Object?>.from(res['row'] as Map),
          force: true);
    }
  }

  // ---- pull ----------------------------------------------------------------

  Future<bool> _pull(String token) async {
    final Database db = await _db.database;
    bool changed = false;
    while (true) {
      final int since = int.tryParse(await _state(db, 'cursor') ?? '') ?? 0;
      final ({int status, Map<String, dynamic>? body}) r =
          await _api.syncPull(token, since: since, deviceId: _deviceId!, limit: _pullLimit);
      if (!_ok(r.status)) return _offlineOrError(r.status);
      final Map<String, dynamic> body = r.body ?? <String, dynamic>{};
      final Map<String, dynamic> changes =
          Map<String, dynamic>.from((body['changes'] as Map?) ?? <String, dynamic>{});

      await db.transaction((Transaction txn) async {
        for (final String table in <String>['products', 'batches', 'stock_movements', 'price_changes']) {
          for (final dynamic row in (changes[table] as List<dynamic>?) ?? <dynamic>[]) {
            changed = true;
            await _applyServerRow(txn, table, Map<String, Object?>.from(row as Map));
          }
        }
        await _setState(txn, 'cursor', '${body['next'] ?? since}');
      });

      if (body['has_more'] != true) break;
    }
    if (changed) onDataChanged?.call();
    return true;
  }

  /// Write a server row locally. Unless [force], product/batch fields are
  /// left alone while this device still has an unsent edit of that row
  /// (the push will resolve it); a batch's server qty always updates.
  Future<void> _applyServerRow(Transaction txn, String table, Map<String, Object?> row,
      {bool force = false}) async {
    final String id = row['id'] as String;
    final bool deleted = row['deleted_at'] != null;
    final int now = DateTime.now().millisecondsSinceEpoch;

    switch (table) {
      case 'products':
      case 'batches':
        final bool hasLocalEdit = !force &&
            (Sqflite.firstIntValue(await txn.rawQuery(
                        "SELECT COUNT(*) FROM outbox WHERE row_id = ? AND status = 'pending'",
                        <Object?>[id])) ??
                    0) >
                0;
        final Map<String, Object?> cols = table == 'products'
            ? <String, Object?>{
                'name': row['name'],
                'name_norm': DatabaseHelper.normName((row['name'] as String?) ?? ''),
                'manufacturer': row['manufacturer'],
                'category': row['category'],
                'composition': row['composition'],
                'unit': row['unit'],
                'pack_size': row['pack_size'] ?? 1,
                'hsn': row['hsn'],
                'gst_rate_bp': row['gst_rate_bp'],
                'barcode': row['barcode'],
                'low_stock_threshold_units': row['low_stock_threshold_units'] ?? 10,
                'discount_bp': row['discount_bp'] ?? 0,
                'master_id': row['master_id'],
                'notes': row['notes'],
              }
            : <String, Object?>{
                'product_id': row['product_id'],
                'batch_no': row['batch_no'],
                'expiry_date': _millis(row['expiry_date']) ?? 0,
                'mfg_date': _millis(row['mfg_date']),
                'mrp_paise': row['mrp_paise'] ?? 0,
                'purchase_rate_paise': row['purchase_rate_paise'] ?? 0,
              };
        final Map<String, Object?> sync = <String, Object?>{
          'version': row['edit_version'] ?? 0,
          'is_deleted': deleted ? 1 : 0,
          'updated_at': now,
          if (table == 'batches') 'server_qty_units': row['qty_units'] ?? 0,
        };
        final int exists = Sqflite.firstIntValue(await txn.rawQuery(
                'SELECT COUNT(*) FROM $table WHERE id = ?', <Object?>[id])) ??
            0;
        if (exists == 0) {
          await txn.insert(table, <String, Object?>{'id': id, ...cols, ...sync, 'created_at': now});
        } else if (hasLocalEdit) {
          if (table == 'batches') {
            await txn.update(table, <String, Object?>{'server_qty_units': row['qty_units'] ?? 0},
                where: 'id = ?', whereArgs: <Object?>[id]);
          }
        } else {
          await txn.update(table, <String, Object?>{...cols, ...sync},
              where: 'id = ?', whereArgs: <Object?>[id]);
        }
      case 'stock_movements':
        await txn.insert(
            'inv_movements',
            <String, Object?>{
              'id': id,
              'batch_id': row['batch_id'],
              'product_id': row['product_id'],
              'delta_units': row['delta_units'],
              'reason': row['reason'],
              'ref_type': row['ref_type'],
              'ref_id': row['ref_id'],
              'occurred_at': _millis(row['occurred_at']) ?? now,
              'synced': 1,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
        // Our own movement coming back: it's now part of the server qty.
        await txn.update('inv_movements', <String, Object?>{'synced': 1},
            where: 'id = ?', whereArgs: <Object?>[id]);
      case 'price_changes':
        await txn.insert(
            'price_changes',
            <String, Object?>{
              'id': id,
              'batch_id': row['batch_id'],
              'field': row['field'],
              'old_paise': row['old_paise'],
              'new_paise': row['new_paise'],
              'device_id': row['device_id'],
              'created_at': _millis(row['created_at']) ?? now,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  // ---- conflicts / rejections ----------------------------------------------

  /// Keep the server's value (already applied); drop the local change.
  Future<void> useTheirs(SyncIssue issue) async {
    final Database db = await _db.database;
    await db.delete('outbox', where: 'seq = ?', whereArgs: <Object?>[issue.seq]);
    await _refreshCounts();
    notifyListeners();
  }

  /// Re-apply this device's change on top of the server's current row.
  Future<void> keepMine(SyncIssue issue) async {
    final Database db = await _db.database;
    final int base = (issue.theirs?['edit_version'] as num?)?.toInt() ?? 0;
    await db.transaction((Transaction txn) async {
      await txn.delete('outbox', where: 'seq = ?', whereArgs: <Object?>[issue.seq]);
      if (issue.op == 'delete') {
        await txn.update(issue.table, <String, Object?>{'is_deleted': 1},
            where: 'id = ?', whereArgs: <Object?>[issue.rowId]);
        await Outbox.delete(txn, table: issue.table, rowId: issue.rowId, rowVersion: base);
        return;
      }
      final Map<String, Object?> local = <String, Object?>{};
      issue.mine.forEach((String k, Object? v) {
        local[k] = (k == 'expiry_date' || k == 'mfg_date') ? _millis(v) : v;
      });
      if (issue.table == 'products' && local['name'] is String) {
        local['name_norm'] = DatabaseHelper.normName(local['name'] as String);
      }
      local.remove('product_id');
      if (local.isNotEmpty) {
        await txn.update(issue.table, local, where: 'id = ?', whereArgs: <Object?>[issue.rowId]);
      }
      await Outbox.upsert(txn,
          table: issue.table, rowId: issue.rowId, rowVersion: base, data: issue.mine);
    });
    onDataChanged?.call();
  }

  /// Forget a change the server rejected (e.g. invalid data, plan limit).
  Future<void> dismiss(SyncIssue issue) => useTheirs(issue);

  Future<void> _refreshCounts() async {
    final Database db = await _db.database;
    pending = Sqflite.firstIntValue(
            await db.rawQuery("SELECT COUNT(*) FROM outbox WHERE status = 'pending'")) ??
        0;
    final List<Map<String, Object?>> rows =
        await db.query('outbox', where: "status != 'pending'", orderBy: 'seq');
    issues = rows.map((Map<String, Object?> r) {
      final Map<String, Object?> res = r['result'] == null
          ? <String, Object?>{}
          : Map<String, Object?>.from(jsonDecode(r['result'] as String) as Map);
      return SyncIssue(
        r['seq'] as int,
        r['table_name'] as String,
        r['op'] as String,
        r['row_id'] as String,
        r['status'] as String,
        (res['reason'] as String?) ?? '',
        Map<String, Object?>.from(jsonDecode(r['data'] as String) as Map),
        res['row'] is Map ? Map<String, Object?>.from(res['row'] as Map) : null,
      );
    }).toList();
  }

  // ---- helpers -------------------------------------------------------------

  bool _ok(int status) => status >= 200 && status < 300;

  bool _offlineOrError(int status) {
    if (status == 0) {
      _set(SyncStatus.offline);
    } else {
      lastError = 'HTTP $status';
      _set(SyncStatus.error);
    }
    return false;
  }

  void _set(SyncStatus s) {
    if (status == s) return;
    status = s;
    notifyListeners();
  }

  static Future<String?> _state(DatabaseExecutor db, String key) async {
    final List<Map<String, Object?>> r =
        await db.query('sync_state', where: 'key = ?', whereArgs: <Object?>[key]);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  static Future<void> _setState(DatabaseExecutor db, String key, String value) =>
      db.insert('sync_state', <String, Object?>{'key': key, 'value': value},
          conflictAlgorithm: ConflictAlgorithm.replace);

  static int? _millis(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    final DateTime? d = DateTime.tryParse(v.toString());
    if (d == null) return null;
    // A plain date (Y-m-d) is a calendar day in local time, like the form.
    return (v.toString().length <= 10 ? DateTime(d.year, d.month, d.day) : d.toLocal())
        .millisecondsSinceEpoch;
  }

  static String? _ymd(int? millis) {
    if (millis == null) return null;
    final DateTime d = DateTime.fromMillisecondsSinceEpoch(millis);
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}
