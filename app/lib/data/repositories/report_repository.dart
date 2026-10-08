import 'package:sqflite/sqflite.dart';

import '../../domain/reports/expiry_loss.dart';
import '../../domain/reports/stock_valuation.dart';
import '../db/database_helper.dart';

/// Read-only queries for the stock reports, against this device's copy of
/// the inventory - so they work offline.
///
/// The local ledger holds every stock movement of the shop (pulled from
/// the server, plus this device's unsent ones), so the stock on a past
/// date is today's stock minus the movements after that date. Prices are
/// the batches' current MRP and purchase rate.
class ReportRepository {
  ReportRepository([DatabaseHelper? db])
      : _dbHelper = db ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  /// The reason the app (and the server) record for an expiry write-off.
  static const String writeOffReason = 'expiry_writeoff';

  /// A time after every movement.
  static const int _never = 1 << 62;

  /// Stock per batch at the end of [asOf] (null = now), for batches that
  /// exist today. Batches with no stock are included (qty 0); one added
  /// after [asOf] has its opening stock taken back off, so it counts 0.
  Future<List<StockRow>> stockAsOf([DateTime? asOf]) async {
    final Database db = await _dbHelper.database;
    // Movements after the end of that day are taken back off.
    final int? after = asOf == null
        ? null
        : DateTime(asOf.year, asOf.month, asOf.day + 1).millisecondsSinceEpoch;
    final List<Map<String, Object?>> rows = await db.rawQuery('''
      SELECT b.id AS batch_id, b.product_id AS product_id, p.name AS name,
        p.manufacturer AS brand, p.category AS category, b.batch_no AS batch_no,
        p.unit AS unit, p.pack_size AS pack_size, b.expiry_date AS expiry_date,
        b.mrp_paise AS mrp_paise, b.purchase_rate_paise AS cost_paise,
        b.server_qty_units
          + IFNULL((SELECT SUM(m.delta_units) FROM inv_movements m
              WHERE m.batch_id = b.id AND m.synced = 0), 0)
          - IFNULL((SELECT SUM(m.delta_units) FROM inv_movements m
              WHERE m.batch_id = b.id AND m.occurred_at >= ?), 0) AS qty
      FROM batches b JOIN products p ON p.id = b.product_id
      WHERE b.is_deleted = 0 AND p.is_deleted = 0
    ''', <Object?>[after ?? _never]);
    return rows.map(_stockRow).toList();
  }

  /// Every expiry write-off, newest first (deleted batches included: the
  /// loss still happened).
  Future<List<WriteOff>> writeOffs() async {
    final Database db = await _dbHelper.database;
    final List<Map<String, Object?>> rows = await db.rawQuery('''
      SELECT m.batch_id AS batch_id, m.product_id AS product_id, p.name AS name,
        p.category AS category, p.unit AS unit, p.pack_size AS pack_size,
        b.batch_no AS batch_no, b.expiry_date AS expiry_date,
        -m.delta_units AS units, m.occurred_at AS occurred_at,
        b.mrp_paise AS mrp_paise, b.purchase_rate_paise AS cost_paise
      FROM inv_movements m
        JOIN batches b ON b.id = m.batch_id
        JOIN products p ON p.id = b.product_id
      WHERE m.reason = ?
      ORDER BY m.occurred_at DESC
    ''', <Object?>[writeOffReason]);
    return <WriteOff>[
      for (final Map<String, Object?> r in rows)
        WriteOff(
          batchId: r['batch_id']! as String,
          productId: (r['product_id'] as String?) ?? '',
          name: (r['name'] as String?) ?? '',
          category: (r['category'] as String?) ?? '',
          unit: (r['unit'] as String?) ?? '',
          packSize: (r['pack_size'] as num?)?.toInt() ?? 1,
          batchNo: (r['batch_no'] as String?) ?? '',
          expiry: _date(r['expiry_date']),
          units: (r['units'] as num?)?.toInt() ?? 0,
          at: _date(r['occurred_at']),
          mrpPaise: (r['mrp_paise'] as num?)?.toInt() ?? 0,
          costPaise: (r['cost_paise'] as num?)?.toInt() ?? 0,
        ),
    ];
  }

  static StockRow _stockRow(Map<String, Object?> r) => StockRow(
        batchId: r['batch_id']! as String,
        productId: (r['product_id'] as String?) ?? '',
        name: (r['name'] as String?) ?? '',
        brand: (r['brand'] as String?) ?? '',
        category: (r['category'] as String?) ?? '',
        batchNo: (r['batch_no'] as String?) ?? '',
        unit: (r['unit'] as String?) ?? '',
        packSize: (r['pack_size'] as num?)?.toInt() ?? 1,
        expiry: _date(r['expiry_date']),
        qty: (r['qty'] as num?)?.toInt() ?? 0,
        mrpPaise: (r['mrp_paise'] as num?)?.toInt() ?? 0,
        costPaise: (r['cost_paise'] as num?)?.toInt() ?? 0,
      );

  static DateTime _date(Object? millis) =>
      DateTime.fromMillisecondsSinceEpoch((millis as num?)?.toInt() ?? 0);
}
