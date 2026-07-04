import 'package:sqflite/sqflite.dart';

import '../db/database_helper.dart';
import '../models/supplier.dart';

/// Data access for suppliers.
class SupplierRepository {
  final DatabaseHelper _dbHelper;
  SupplierRepository([DatabaseHelper? dbHelper])
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  Future<List<Supplier>> getAll() async {
    final Database db = await _dbHelper.database;
    final List<Map<String, Object?>> rows =
        await db.query('suppliers', orderBy: 'name COLLATE NOCASE ASC');
    return rows.map(Supplier.fromMap).toList();
  }

  Future<Supplier?> getById(String id) async {
    final Database db = await _dbHelper.database;
    final List<Map<String, Object?>> rows =
        await db.query('suppliers', where: 'id = ?', whereArgs: <Object?>[id]);
    if (rows.isEmpty) return null;
    return Supplier.fromMap(rows.first);
  }

  Future<void> insert(Supplier s) async {
    final Database db = await _dbHelper.database;
    await db.insert('suppliers', s.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> update(Supplier s) async {
    final Database db = await _dbHelper.database;
    await db.update('suppliers', s.toMap(),
        where: 'id = ?', whereArgs: <Object?>[s.id]);
  }

  Future<void> delete(String id) async {
    final Database db = await _dbHelper.database;
    await db.delete('suppliers', where: 'id = ?', whereArgs: <Object?>[id]);
  }
}
