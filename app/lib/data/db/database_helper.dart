import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';

/// Owns the SQLite connection and schema migrations. Single source of truth.
///
/// v2 moves inventory to the server-synced shape: a product has many
/// batches; stock is an append-only movement ledger; pending changes wait in
/// an outbox until the sync engine pushes them.
class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  static const String _dbName = 'med_stock.db';
  static const int _dbVersion = 2;

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
    final DatabaseFactory factory = factoryOverride ?? databaseFactory;
    final String path =
        pathOverride ?? p.join(await factory.getDatabasesPath(), _dbName);
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _dbVersion,
        onConfigure: (Database db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (Database db, int version) async {
          await _createV1(db);
          await migrateToV2(db);
        },
        onUpgrade: _onUpgrade,
      ),
    );
  }

  /// Original v1 schema. Kept so fresh installs and upgrades end up on the
  /// same path (v1 -> v2 migration), and so legacy history stays readable.
  static Future<void> _createV1(Database db) async {
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
        'CREATE INDEX idx_movements_med ON stock_movements(medicine_id)');
  }

  /// Add new migrations here as _dbVersion increases. Never edit past steps.
  Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    if (oldV < 2) await migrateToV2(db);
  }

  /// v1 -> v2: create the synced tables and convert every active v1
  /// `medicines` row into product + batch (+ an opening stock movement).
  /// Runs in the open transaction sqflite gives onCreate/onUpgrade, so a
  /// failure leaves the v1 data untouched. The v1 table is renamed, not
  /// dropped, so nothing is lost.
  static Future<void> migrateToV2(Database db) async {
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
    // qty is server_qty_units plus this device's not-yet-synced movements.
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
    // Pending changes for the server. One row per mutation, sent in seq order.
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

    await _convertV1Rows(db);
    await db.execute('ALTER TABLE medicines RENAME TO medicines_legacy');
  }

  static String normName(String name) =>
      name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static Future<void> _convertV1Rows(Database db) async {
    final List<Map<String, Object?>> rows = await db.query('medicines',
        where: 'is_deleted = 0', orderBy: 'created_at ASC');
    // Group batches of the same medicine (same name + unit + brand).
    final Map<String, String> productIds = <String, String>{};
    for (final Map<String, Object?> r in rows) {
      final String name = ((r['name'] as String?) ?? '').trim();
      final String unit = AppConstants.canonicalUnit(r['unit'] as String?);
      final String brand = ((r['brand'] as String?) ?? '').trim();
      final String key = '${normName(name)}|$unit|${brand.toLowerCase()}';
      final int now = (r['updated_at'] as int?) ?? 0;
      // Server ids must be UUIDs; keep a valid v1 id (so it stays stable),
      // otherwise derive one deterministically.
      final String oldId = r['id'] as String;
      final String batchId = Uuid.isValidUUID(fromString: oldId)
          ? oldId
          : _uuid5('batch:$oldId');

      String? productId = productIds[key];
      if (productId == null) {
        productId = _uuid5('product:$batchId');
        productIds[key] = productId;
        await db.insert('products', <String, Object?>{
          'id': productId,
          'name': name,
          'name_norm': normName(name),
          'manufacturer': brand,
          'category': r['category'],
          'unit': unit,
          'barcode': r['barcode'],
          'low_stock_threshold_units': (r['low_stock_threshold'] as int?) ??
              AppConstants.defaultLowStockThreshold,
          'notes': r['notes'],
          'created_at': (r['created_at'] as int?) ?? now,
          'updated_at': now,
        });
      }

      await db.insert('batches', <String, Object?>{
        'id': batchId,
        'product_id': productId,
        'batch_no': r['batch_no'],
        'expiry_date': r['expiry_date'],
        'mfg_date': r['mfg_date'],
        'mrp_paise': _paise(r['selling_price']),
        'purchase_rate_paise': _paise(r['purchase_price']),
        'created_at': (r['created_at'] as int?) ?? now,
        'updated_at': now,
      });

      final int qty = (r['quantity'] as int?) ?? 0;
      if (qty != 0) {
        await db.insert('inv_movements', <String, Object?>{
          'id': _uuid5('opening:$batchId'),
          'batch_id': batchId,
          'product_id': productId,
          'delta_units': qty,
          'reason': 'opening',
          // Pre-v2 history already shows this stock in stock_movements.
          'ref_type': 'migration',
          'occurred_at': now,
        });
      }
    }
  }

  static String _uuid5(String name) =>
      const Uuid().v5(Namespace.url.value, 'meddata:$name');

  static int _paise(Object? rupees) =>
      (((rupees as num?) ?? 0) * 100).round();

  /// Wipe all inventory data (restore/import, or switching account). Keeps
  /// schema and the legacy v1 tables.
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
