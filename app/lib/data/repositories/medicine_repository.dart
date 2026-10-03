import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../sync/outbox.dart';
import '../db/database_helper.dart';
import '../models/medicine.dart';
import '../models/stock_movement.dart';

/// Inventory data access. The UI still works with [Medicine] (one batch of a
/// product); underneath, rows live in `products` + `batches`, stock is the
/// `inv_movements` ledger, and every change is queued in the [Outbox] for
/// the server.
class MedicineRepository {
  final DatabaseHelper _dbHelper;
  MedicineRepository([DatabaseHelper? dbHelper])
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  static const Uuid _uuid = Uuid();

  /// Batch + product columns flattened into the shape [Medicine.fromMap]
  /// reads. Quantity = server qty + this device's not-yet-synced movements.
  static const String _select = '''
    SELECT b.id AS id, b.product_id AS product_id, p.name AS name,
      p.manufacturer AS brand, p.category AS category, b.batch_no AS batch_no,
      p.barcode AS barcode,
      b.server_qty_units + IFNULL((SELECT SUM(m.delta_units) FROM inv_movements m
        WHERE m.batch_id = b.id AND m.synced = 0), 0) AS quantity,
      p.unit AS unit, p.low_stock_threshold_units AS low_stock_threshold,
      b.purchase_rate_paise / 100.0 AS purchase_price,
      b.mrp_paise / 100.0 AS selling_price,
      b.mfg_date AS mfg_date, b.expiry_date AS expiry_date, p.notes AS notes,
      b.created_at AS created_at, b.updated_at AS updated_at,
      (b.is_deleted OR p.is_deleted) AS is_deleted
    FROM batches b JOIN products p ON p.id = b.product_id
  ''';

  Future<List<Medicine>> getAll() async {
    final Database db = await _dbHelper.database;
    final List<Map<String, Object?>> rows = await db.rawQuery(
        '$_select WHERE b.is_deleted = 0 AND p.is_deleted = 0 '
        'ORDER BY p.name COLLATE NOCASE ASC, b.expiry_date ASC');
    return rows.map(Medicine.fromMap).toList();
  }

  Future<Medicine?> getById(String id) async {
    final Database db = await _dbHelper.database;
    final List<Map<String, Object?>> rows =
        await db.rawQuery('$_select WHERE b.id = ?', <Object?>[id]);
    if (rows.isEmpty) return null;
    return Medicine.fromMap(rows.first);
  }

  /// Active products — the unit for free-tier gating.
  Future<int> activeCount() async {
    final Database db = await _dbHelper.database;
    final int? c = Sqflite.firstIntValue(await db
        .rawQuery('SELECT COUNT(*) FROM products WHERE is_deleted = 0'));
    return c ?? 0;
  }

  /// True if another active batch already has this product name + batch no.
  Future<bool> existsNameBatch(String name, String batchNo,
      {String? excludeId}) async {
    final Database db = await _dbHelper.database;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT b.id FROM batches b JOIN products p ON p.id = b.product_id '
      'WHERE b.is_deleted = 0 AND p.is_deleted = 0 AND p.name_norm = ? '
      "AND LOWER(IFNULL(b.batch_no, '')) = ? AND b.id != ? LIMIT 1",
      <Object?>[
        DatabaseHelper.normName(name),
        batchNo.trim().toLowerCase(),
        excludeId ?? '',
      ],
    );
    return rows.isNotEmpty;
  }

  /// Add a batch. It joins an existing product with the same name, unit and
  /// brand (so batches of one medicine group together); otherwise a new
  /// product is created. Opening stock is recorded as a movement.
  Future<void> insert(Medicine m) async {
    final Database db = await _dbHelper.database;
    await db.transaction((Transaction txn) async {
      final int now = m.createdAt.millisecondsSinceEpoch;
      String? productId = await _findProduct(txn, m);
      if (productId == null) {
        productId = _uuid.v4();
        final Map<String, Object?> data = _productData(m);
        await txn.insert('products', <String, Object?>{
          'id': productId,
          ...data,
          'name_norm': DatabaseHelper.normName(m.name),
          'created_at': now,
          'updated_at': now,
        });
        await Outbox.upsert(txn,
            table: 'products', rowId: productId, rowVersion: 0, data: data);
      }

      final Map<String, Object?> batch = _batchColumns(m);
      await txn.insert('batches', <String, Object?>{
        'id': m.id,
        'product_id': productId,
        ...batch,
        'created_at': now,
        'updated_at': now,
      });
      await Outbox.upsert(txn,
          table: 'batches',
          rowId: m.id,
          rowVersion: 0,
          data: <String, Object?>{
            'product_id': productId,
            ..._batchSyncData(batch),
          });

      if (m.quantity != 0) {
        await _move(txn, m.id, productId, m.quantity, 'opening');
      }
    });
  }

  /// Save edits from the form: product fields (shared by all its batches),
  /// batch fields, and a quantity change as an 'adjust' movement.
  Future<void> update(Medicine m) async {
    final Database db = await _dbHelper.database;
    await db.transaction((Transaction txn) async {
      final Map<String, Object?>? b = await _row(txn, 'batches', m.id);
      if (b == null) return;
      final String productId = b['product_id'] as String;
      final Map<String, Object?>? p = await _row(txn, 'products', productId);
      final int now = DateTime.now().millisecondsSinceEpoch;

      if (p != null) {
        final Map<String, Object?> data = _productData(m);
        final Map<String, Object?> changed = _diff(p, data);
        if (changed.isNotEmpty) {
          await txn.update(
              'products',
              <String, Object?>{
                ...changed,
                'name_norm': DatabaseHelper.normName(m.name),
                'updated_at': now,
              },
              where: 'id = ?',
              whereArgs: <Object?>[productId]);
          await Outbox.upsert(txn,
              table: 'products',
              rowId: productId,
              rowVersion: (p['version'] as int?) ?? 0,
              data: changed);
        }
      }

      final Map<String, Object?> changed = _diff(b, _batchColumns(m));
      if (changed.isNotEmpty) {
        await txn.update('batches', <String, Object?>{...changed, 'updated_at': now},
            where: 'id = ?', whereArgs: <Object?>[m.id]);
        await Outbox.upsert(txn,
            table: 'batches',
            rowId: m.id,
            rowVersion: (b['version'] as int?) ?? 0,
            data: _batchSyncData(changed));
      }

      final int delta = m.quantity - await _qty(txn, m.id);
      if (delta != 0) await _move(txn, m.id, productId, delta, 'adjust');
    });
  }

  /// Change stock by [delta] (never below zero locally) and record why.
  Future<Medicine?> adjustQuantity(String id, int delta, StockReason reason,
      {DateTime? now}) async {
    final Database db = await _dbHelper.database;
    await db.transaction((Transaction txn) async {
      final Map<String, Object?>? b = await _row(txn, 'batches', id);
      if (b == null) return;
      final int current = await _qty(txn, id);
      final int applied = current + delta < 0 ? -current : delta;
      if (applied != 0) {
        await _move(txn, id, b['product_id'] as String, applied,
            _serverReason(reason, applied),
            at: now);
      }
    });
    return getById(id);
  }

  /// Delete a batch; the product goes too once it has no batches left.
  Future<void> softDelete(String id, {DateTime? now}) async {
    final Database db = await _dbHelper.database;
    await db.transaction((Transaction txn) async {
      final Map<String, Object?>? b = await _row(txn, 'batches', id);
      if (b == null) return;
      final int ts = (now ?? DateTime.now()).millisecondsSinceEpoch;
      await txn.update('batches', <String, Object?>{'is_deleted': 1, 'updated_at': ts},
          where: 'id = ?', whereArgs: <Object?>[id]);
      await Outbox.delete(txn,
          table: 'batches', rowId: id, rowVersion: (b['version'] as int?) ?? 0);

      final String productId = b['product_id'] as String;
      final int? left = Sqflite.firstIntValue(await txn.rawQuery(
          'SELECT COUNT(*) FROM batches WHERE product_id = ? AND is_deleted = 0',
          <Object?>[productId]));
      if ((left ?? 0) == 0) {
        final Map<String, Object?>? p = await _row(txn, 'products', productId);
        await txn.update('products', <String, Object?>{'is_deleted': 1, 'updated_at': ts},
            where: 'id = ?', whereArgs: <Object?>[productId]);
        await Outbox.delete(txn,
            table: 'products',
            rowId: productId,
            rowVersion: (p?['version'] as int?) ?? 0);
      }
    });
  }

  /// Undo a delete. If the delete hasn't reached the server yet it is simply
  /// cancelled; otherwise the batch is re-created as a new one.
  Future<void> restore(String id, {DateTime? now}) async {
    final Database db = await _dbHelper.database;
    await db.transaction((Transaction txn) async {
      final Map<String, Object?>? b = await _row(txn, 'batches', id);
      if (b == null) return;
      final String productId = b['product_id'] as String;
      final int removed = await txn.delete('outbox',
          where: "op = 'delete' AND row_id IN (?, ?) AND result IS NULL",
          whereArgs: <Object?>[id, productId]);
      final int ts = (now ?? DateTime.now()).millisecondsSinceEpoch;
      if (removed > 0) {
        await txn.update('batches', <String, Object?>{'is_deleted': 0, 'updated_at': ts},
            where: 'id = ?', whereArgs: <Object?>[id]);
        await txn.update('products', <String, Object?>{'is_deleted': 0, 'updated_at': ts},
            where: 'id = ?', whereArgs: <Object?>[productId]);
      }
    });
    final Medicine? m = await getById(id);
    if (m != null && m.isDeleted) {
      // Already deleted on the server: bring it back as a fresh batch.
      await insert(Medicine(
        id: _uuid.v4(),
        name: m.name,
        brand: m.brand,
        category: m.category,
        batchNo: m.batchNo,
        barcode: m.barcode,
        quantity: m.quantity,
        unit: m.unit,
        lowStockThreshold: m.lowStockThreshold,
        purchasePrice: m.purchasePrice,
        sellingPrice: m.sellingPrice,
        mfgDate: m.mfgDate,
        expiryDate: m.expiryDate,
        notes: m.notes,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
    }
  }

  /// Stock history of a batch, newest first (synced ledger + pre-v2 history).
  Future<List<StockMovement>> movementsFor(String medicineId) async {
    final Database db = await _dbHelper.database;
    final List<Map<String, Object?>> rows = await db.rawQuery('''
      SELECT id, batch_id AS medicine_id, delta_units AS change,
        reason, occurred_at AS created_at
      FROM inv_movements WHERE batch_id = ? AND IFNULL(ref_type, '') != 'migration'
      UNION ALL
      SELECT id, medicine_id, change, reason, created_at
      FROM stock_movements WHERE medicine_id = ?
      ORDER BY created_at DESC
    ''', <Object?>[medicineId, medicineId]);
    return rows.map(StockMovement.fromMap).toList();
  }

  // ---------------------------------------------------------------------

  Future<String?> _findProduct(DatabaseExecutor db, Medicine m) async {
    final List<Map<String, Object?>> rows = await db.query(
      'products',
      columns: <String>['id'],
      where: "is_deleted = 0 AND name_norm = ? AND IFNULL(unit, '') = ? "
          "AND LOWER(IFNULL(manufacturer, '')) = ?",
      whereArgs: <Object?>[
        DatabaseHelper.normName(m.name),
        m.unit,
        m.brand.trim().toLowerCase(),
      ],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['id'] as String;
  }

  Future<Map<String, Object?>?> _row(
      DatabaseExecutor db, String table, String id) async {
    final List<Map<String, Object?>> rows =
        await db.query(table, where: 'id = ?', whereArgs: <Object?>[id]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> _qty(DatabaseExecutor db, String batchId) async {
    final int? q = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT b.server_qty_units + IFNULL((SELECT SUM(delta_units) '
        'FROM inv_movements WHERE batch_id = b.id AND synced = 0), 0) '
        'FROM batches b WHERE b.id = ?',
        <Object?>[batchId]));
    return q ?? 0;
  }

  Future<void> _move(DatabaseExecutor db, String batchId, String productId,
      int delta, String reason,
      {DateTime? at}) async {
    final String id = _uuid.v4();
    final DateTime ts = at ?? DateTime.now();
    await db.insert('inv_movements', <String, Object?>{
      'id': id,
      'batch_id': batchId,
      'product_id': productId,
      'delta_units': delta,
      'reason': reason,
      'occurred_at': ts.millisecondsSinceEpoch,
    });
    await Outbox.movement(db, id, <String, Object?>{
      'batch_id': batchId,
      'delta_units': delta,
      'reason': reason,
      'occurred_at': ts.toUtc().toIso8601String(),
    });
  }

  static String _serverReason(StockReason r, int delta) {
    switch (r) {
      case StockReason.sell:
        return 'sale';
      case StockReason.add:
      case StockReason.restock:
        return delta > 0 ? 'purchase' : 'adjust';
      case StockReason.adjust:
        return 'adjust';
    }
  }

  static Map<String, Object?> _productData(Medicine m) => <String, Object?>{
        'name': m.name.trim(),
        'manufacturer': m.brand.trim(),
        'category': m.category,
        'unit': m.unit,
        'barcode': m.barcode.trim(),
        'low_stock_threshold_units': m.lowStockThreshold,
        'notes': m.notes,
      };

  static Map<String, Object?> _batchColumns(Medicine m) => <String, Object?>{
        'batch_no': m.batchNo.trim(),
        'expiry_date': m.expiryDate.millisecondsSinceEpoch,
        'mfg_date': m.mfgDate?.millisecondsSinceEpoch,
        'mrp_paise': (m.sellingPrice * 100).round(),
        'purchase_rate_paise': (m.purchasePrice * 100).round(),
      };

  /// Local batch columns -> server field values (dates as Y-m-d).
  static Map<String, Object?> _batchSyncData(Map<String, Object?> cols) {
    final Map<String, Object?> out = Map<String, Object?>.of(cols);
    for (final String k in <String>['expiry_date', 'mfg_date']) {
      if (out.containsKey(k)) out[k] = _ymd(out[k] as int?);
    }
    return out;
  }

  static String? _ymd(int? millis) {
    if (millis == null) return null;
    final DateTime d = DateTime.fromMillisecondsSinceEpoch(millis);
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// Fields of [next] whose value differs from [current].
  static Map<String, Object?> _diff(
      Map<String, Object?> current, Map<String, Object?> next) {
    final Map<String, Object?> out = <String, Object?>{};
    next.forEach((String k, Object? v) {
      final Object? cur = current[k];
      final bool same = (cur ?? '') == (v ?? '') ||
          (cur is num && v is num && cur == v);
      if (!same) out[k] = v;
    });
    return out;
  }
}
