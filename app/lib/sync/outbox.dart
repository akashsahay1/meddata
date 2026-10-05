import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Queue of local changes waiting to be pushed to the server.
///
/// At most one *unsent* upsert per row: a later edit is merged into it, so
/// the server sees one change with the version the device originally saw.
/// Once a mutation has been sent, later edits queue separately and the sync
/// engine rebases them on the version the server returned.
class Outbox {
  static const Uuid _uuid = Uuid();

  /// Signals that something was queued (the sync engine debounces a push).
  static void Function()? onEnqueued;

  static Future<void> upsert(
    DatabaseExecutor db, {
    required String table,
    required String rowId,
    required int rowVersion,
    required Map<String, Object?> data,
  }) async {
    final List<Map<String, Object?>> pending = await db.query(
      'outbox',
      where: "table_name = ? AND row_id = ? AND op = 'upsert' "
          "AND status = 'pending' AND result IS NULL",
      whereArgs: <Object?>[table, rowId],
      orderBy: 'seq DESC',
      limit: 1,
    );
    if (pending.isNotEmpty) {
      final Map<String, Object?> merged = <String, Object?>{
        ...(jsonDecode(pending.first['data'] as String) as Map<String, Object?>),
        ...data,
      };
      await db.update('outbox', <String, Object?>{'data': jsonEncode(merged)},
          where: 'seq = ?', whereArgs: <Object?>[pending.first['seq']]);
    } else {
      await _insert(db, table, 'upsert', rowId, rowVersion, data);
    }
    onEnqueued?.call();
  }

  static Future<void> delete(
    DatabaseExecutor db, {
    required String table,
    required String rowId,
    required int rowVersion,
  }) async {
    await _insert(db, table, 'delete', rowId, rowVersion, <String, Object?>{});
    onEnqueued?.call();
  }

  /// Stock movements are insert-only rows with their own ids.
  static Future<void> movement(
      DatabaseExecutor db, String movementId, Map<String, Object?> data) async {
    await _insert(db, 'stock_movements', 'upsert', movementId, 0, data);
    onEnqueued?.call();
  }

  /// Bulk variant of [upsert] and [movement] for rows the server has never
  /// seen (a spreadsheet import): adds the change to [batch]. A new row has
  /// no pending change to merge with. Call [onEnqueued] once committed.
  static void queueNew(
    Batch batch, {
    required String table,
    required String rowId,
    required Map<String, Object?> data,
  }) {
    batch.insert('outbox', _row(table, 'upsert', rowId, 0, data));
  }

  static Future<void> _insert(DatabaseExecutor db, String table, String op,
      String rowId, int rowVersion, Map<String, Object?> data) async {
    await db.insert('outbox', _row(table, op, rowId, rowVersion, data));
  }

  static Map<String, Object?> _row(String table, String op, String rowId,
          int rowVersion, Map<String, Object?> data) =>
      <String, Object?>{
        'mutation_id': _uuid.v4(),
        'table_name': table,
        'op': op,
        'row_id': rowId,
        // 0 = the server has never seen this row (a create).
        'base_version': rowVersion > 0 ? rowVersion : null,
        'data': jsonEncode(data),
        'created_at': DateTime.now().millisecondsSinceEpoch,
      };
}
