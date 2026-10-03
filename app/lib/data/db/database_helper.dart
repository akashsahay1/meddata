import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Owns the SQLite connection and schema. This device's copy of the shop's
/// inventory: products have batches, stock is an append-only movement
/// ledger, and local changes wait in the outbox until the sync engine
/// pushes them to the server.
class DatabaseHelper {
  DatabaseHelper._()
      : _factory = null,
        _path = null;
  static final DatabaseHelper instance = DatabaseHelper._();

  /// A separate database (tests simulating several devices).
  DatabaseHelper.at(DatabaseFactory factory, String path)
      : _factory = factory,
        _path = path;

  final DatabaseFactory? _factory;
  final String? _path;

  static const String _dbName = 'meddata.db';
  static const int _dbVersion = 1;

  /// Overridable for tests (in-memory / ffi factories).
  static DatabaseFactory? factoryOverride;
  static String? pathOverride;

  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  /// Close and forget the connection (tests).
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<Database> _open() async {
    final DatabaseFactory factory =
        _factory ?? factoryOverride ?? databaseFactory;
    final String path = _path ??
        pathOverride ??
        p.join(await factory.getDatabasesPath(), _dbName);
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _dbVersion,
        onConfigure: (Database db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE products (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        name_norm TEXT NOT NULL,
        manufacturer TEXT,
        category TEXT,
        composition TEXT,
        unit TEXT,
        pack_size INTEGER NOT NULL DEFAULT 1,
        hsn TEXT,
        gst_rate_bp INTEGER,
        barcode TEXT,
        low_stock_threshold_units INTEGER NOT NULL DEFAULT 10,
        discount_bp INTEGER NOT NULL DEFAULT 0,
        master_id INTEGER,
        notes TEXT,
        version INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');
    // A batch's stock = server_qty_units + this device's unsynced movements.
    await db.execute('''
      CREATE TABLE batches (
        id TEXT PRIMARY KEY,
        product_id TEXT NOT NULL,
        batch_no TEXT,
        expiry_date INTEGER NOT NULL,
        mfg_date INTEGER,
        mrp_paise INTEGER NOT NULL DEFAULT 0,
        purchase_rate_paise INTEGER NOT NULL DEFAULT 0,
        server_qty_units INTEGER NOT NULL DEFAULT 0,
        version INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE inv_movements (
        id TEXT PRIMARY KEY,
        batch_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        delta_units INTEGER NOT NULL,
        reason TEXT NOT NULL,
        ref_type TEXT,
        ref_id TEXT,
        occurred_at INTEGER NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE price_changes (
        id TEXT PRIMARY KEY,
        batch_id TEXT NOT NULL,
        field TEXT NOT NULL,
        old_paise INTEGER,
        new_paise INTEGER,
        device_id TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
    // Pending changes for the server, sent in seq order.
    await db.execute('''
      CREATE TABLE outbox (
        seq INTEGER PRIMARY KEY AUTOINCREMENT,
        mutation_id TEXT NOT NULL UNIQUE,
        table_name TEXT NOT NULL,
        op TEXT NOT NULL,
        row_id TEXT NOT NULL,
        base_version INTEGER,
        data TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        result TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
        'CREATE TABLE sync_state (key TEXT PRIMARY KEY, value TEXT)');
    await db.execute('CREATE INDEX idx_batches_product ON batches(product_id)');
    await db.execute('CREATE INDEX idx_batches_expiry ON batches(expiry_date)');
    await db.execute('CREATE INDEX idx_products_barcode ON products(barcode)');
    await db.execute('CREATE INDEX idx_products_norm ON products(name_norm)');
    await db.execute('CREATE INDEX idx_inv_mov_batch ON inv_movements(batch_id)');
    await db.execute('CREATE INDEX idx_outbox_row ON outbox(row_id, status)');
  }

  /// Add migrations here as _dbVersion increases. Never edit past steps.
  Future<void> _onUpgrade(Database db, int oldV, int newV) async {}

  static String normName(String name) =>
      name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Wipe this device's inventory copy (e.g. a different account signs in).
  Future<void> clearAll() async {
    final Database db = await database;
    await db.transaction((Transaction txn) async {
      for (final String t in <String>[
        'inv_movements',
        'batches',
        'products',
        'price_changes',
        'outbox',
        'sync_state',
      ]) {
        await txn.delete(t);
      }
    });
  }
}
