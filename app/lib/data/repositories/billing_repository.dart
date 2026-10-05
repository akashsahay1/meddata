import 'package:sqflite/sqflite.dart';

import '../../domain/fefo.dart';
import '../db/database_helper.dart';

/// Local reads and writes for billing. Bills themselves live on the server
/// (billing is online-only); this is the device's inventory side of it.
class BillingRepository {
  BillingRepository([DatabaseHelper? db]) : _db = db ?? DatabaseHelper.instance;

  final DatabaseHelper _db;

  /// Active batches of a product with what a bill line needs (price,
  /// version, GST). Stock = server qty + this device's unsynced movements.
  Future<List<SaleBatch>> batchesOf(String productId) async {
    final Database db = await _db.database;
    final List<Map<String, Object?>> rows = await db.rawQuery('''
      SELECT b.id, b.product_id, p.name, p.unit, p.hsn, p.gst_rate_bp,
        p.discount_bp, b.batch_no, b.expiry_date, b.mrp_paise, b.version,
        b.server_qty_units + IFNULL((SELECT SUM(m.delta_units) FROM inv_movements m
          WHERE m.batch_id = b.id AND m.synced = 0), 0) AS qty
      FROM batches b JOIN products p ON p.id = b.product_id
      WHERE b.product_id = ? AND b.is_deleted = 0 AND p.is_deleted = 0
      ORDER BY b.expiry_date
    ''', <Object?>[productId]);
    return rows
        .map((Map<String, Object?> r) => SaleBatch(
              id: r['id']! as String,
              productId: r['product_id']! as String,
              productName: (r['name'] as String?) ?? '',
              unit: (r['unit'] as String?) ?? '',
              batchNo: (r['batch_no'] as String?) ?? '',
              expiryDate:
                  DateTime.fromMillisecondsSinceEpoch((r['expiry_date'] as int?) ?? 0),
              mrpPaise: (r['mrp_paise'] as int?) ?? 0,
              version: (r['version'] as int?) ?? 0,
              qty: (r['qty'] as int?) ?? 0,
              hsn: (r['hsn'] as String?) ?? '',
              gstRateBp: r['gst_rate_bp'] as int?,
              discountBp: (r['discount_bp'] as int?) ?? 0,
            ))
        .toList();
  }

  /// Stock the server reported after a bill or a cancellation becomes the
  /// batches' server qty at once; the sync pull then brings the movements.
  Future<void> applyServerStock(Map<String, int> qtyByBatch) async {
    if (qtyByBatch.isEmpty) return;
    final Database db = await _db.database;
    await db.transaction((Transaction txn) async {
      for (final MapEntry<String, int> e in qtyByBatch.entries) {
        await txn.update('batches', <String, Object?>{'server_qty_units': e.value},
            where: 'id = ?', whereArgs: <Object?>[e.key]);
      }
    });
  }
}
