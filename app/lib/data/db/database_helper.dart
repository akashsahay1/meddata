import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Owns the SQLite connection and schema migrations. Single source of truth.
class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  static const String _dbName = 'med_stock.db';
  static const int _dbVersion = 1;

  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final String path = p.join(await getDatabasesPath(), _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onConfigure: (Database db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE medicines (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        brand TEXT,
        category TEXT,
        batch_no TEXT,
        barcode TEXT,
        quantity INTEGER NOT NULL DEFAULT 0,
        unit TEXT,
        low_stock_threshold INTEGER NOT NULL DEFAULT 10,
        purchase_price REAL NOT NULL DEFAULT 0,
        selling_price REAL NOT NULL DEFAULT 0,
        supplier_id TEXT,
        mfg_date INTEGER,
        expiry_date INTEGER NOT NULL,
        notes TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE suppliers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT,
        email TEXT,
        address TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE stock_movements (
        id TEXT PRIMARY KEY,
        medicine_id TEXT NOT NULL,
        change INTEGER NOT NULL,
        reason TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute(
        'CREATE INDEX idx_medicines_expiry ON medicines(expiry_date)');
    await db.execute('CREATE INDEX idx_medicines_name ON medicines(name)');
    await db
        .execute('CREATE INDEX idx_medicines_qty ON medicines(quantity)');
    await db
        .execute('CREATE INDEX idx_medicines_barcode ON medicines(barcode)');
    await db.execute(
        'CREATE INDEX idx_movements_med ON stock_movements(medicine_id)');
  }

  /// Add new migrations here as _dbVersion increases. Never edit past steps.
  Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    // Example for future versions:
    // if (oldV < 2) { await db.execute('ALTER TABLE ...'); }
  }

  /// Wipe all data (used by restore/import). Keeps schema.
  Future<void> clearAll() async {
    final Database db = await database;
    await db.delete('stock_movements');
    await db.delete('medicines');
    await db.delete('suppliers');
  }
}
