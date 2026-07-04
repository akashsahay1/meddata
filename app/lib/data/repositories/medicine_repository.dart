import 'package:sqflite/sqflite.dart';

import '../db/database_helper.dart';
import '../models/medicine.dart';
import '../models/stock_movement.dart';

/// Data access for medicines and their stock movements.
class MedicineRepository {
  final DatabaseHelper _dbHelper;
  MedicineRepository([DatabaseHelper? dbHelper])
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  Future<List<Medicine>> getAll() async {
    final Database db = await _dbHelper.database;
    final List<Map<String, Object?>> rows = await db.query(
      'medicines',
      where: 'is_deleted = 0',
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(Medicine.fromMap).toList();
  }

  Future<Medicine?> getById(String id) async {
    final Database db = await _dbHelper.database;
    final List<Map<String, Object?>> rows =
        await db.query('medicines', where: 'id = ?', whereArgs: <Object?>[id]);
    if (rows.isEmpty) return null;
    return Medicine.fromMap(rows.first);
  }

  /// Count of active (non-deleted) medicines — used for free-tier gating.
  Future<int> activeCount() async {
    final Database db = await _dbHelper.database;
    final int? c = Sqflite.firstIntValue(await db
        .rawQuery('SELECT COUNT(*) FROM medicines WHERE is_deleted = 0'));
    return c ?? 0;
  }

  /// Returns true if another active medicine already has this name + batch.
  Future<bool> existsNameBatch(String name, String batchNo,
      {String? excludeId}) async {
    final Database db = await _dbHelper.database;
    final List<Map<String, Object?>> rows = await db.query(
      'medicines',
      where:
          'is_deleted = 0 AND LOWER(name) = ? AND LOWER(IFNULL(batch_no, "")) = ? AND id != ?',
      whereArgs: <Object?>[
        name.toLowerCase(),
        batchNo.toLowerCase(),
        excludeId ?? '',
      ],
    );
    return rows.isNotEmpty;
  }

  Future<void> insert(Medicine m) async {
    final Database db = await _dbHelper.database;
    await db.insert('medicines', m.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    await _logMovement(db, m.id, m.quantity, StockReason.add);
  }

  Future<void> update(Medicine m) async {
    final Database db = await _dbHelper.database;
    await db.update('medicines', m.toMap(),
        where: 'id = ?', whereArgs: <Object?>[m.id]);
  }

  /// Adjust quantity by [delta] and record a movement.
  Future<Medicine?> adjustQuantity(String id, int delta, StockReason reason,
      {DateTime? now}) async {
    final Database db = await _dbHelper.database;
    final Medicine? m = await getById(id);
    if (m == null) return null;
    final int newQty = (m.quantity + delta).clamp(0, 1 << 31);
    final Medicine updated =
        m.copyWith(quantity: newQty, updatedAt: now ?? DateTime.now());
    await db.update('medicines', updated.toMap(),
        where: 'id = ?', whereArgs: <Object?>[id]);
    await _logMovement(db, id, delta, reason, now: now);
    return updated;
  }

  /// Soft delete (keeps row for undo / future sync).
  Future<void> softDelete(String id, {DateTime? now}) async {
    final Database db = await _dbHelper.database;
    await db.update(
      'medicines',
      <String, Object?>{
        'is_deleted': 1,
        'updated_at': (now ?? DateTime.now()).millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> restore(String id, {DateTime? now}) async {
    final Database db = await _dbHelper.database;
    await db.update(
      'medicines',
      <String, Object?>{
        'is_deleted': 0,
        'updated_at': (now ?? DateTime.now()).millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<List<StockMovement>> movementsFor(String medicineId) async {
    final Database db = await _dbHelper.database;
    final List<Map<String, Object?>> rows = await db.query(
      'stock_movements',
      where: 'medicine_id = ?',
      whereArgs: <Object?>[medicineId],
      orderBy: 'created_at DESC',
    );
    return rows.map(StockMovement.fromMap).toList();
  }

  Future<void> _logMovement(
      Database db, String medicineId, int change, StockReason reason,
      {DateTime? now}) async {
    if (change == 0) return;
    final DateTime ts = now ?? DateTime.now();
    await db.insert('stock_movements', <String, Object?>{
      'id': '${medicineId}_${ts.microsecondsSinceEpoch}',
      'medicine_id': medicineId,
      'change': change,
      'reason': reason.name,
      'created_at': ts.millisecondsSinceEpoch,
    });
  }
}
