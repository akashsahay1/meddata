import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:med_stock/data/db/database_helper.dart';
import 'package:med_stock/data/models/medicine.dart';
import 'package:med_stock/data/models/stock_movement.dart';
import 'package:med_stock/data/repositories/medicine_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

/// Builds a real v1 database file, then opens it through DatabaseHelper so
/// the v1 -> v2 upgrade runs exactly as it will on users' phones.
void main() {
  sqfliteFfiInit();
  final DatabaseFactory factory = databaseFactoryFfi;
  late String path;
  int n = 0;

  setUp(() async {
    path = '${await factory.getDatabasesPath()}/mig_test_${n++}_${DateTime.now().microsecondsSinceEpoch}.db';
    DatabaseHelper.factoryOverride = factory;
    DatabaseHelper.pathOverride = path;
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
    await factory.deleteDatabase(path);
  });

  Future<void> makeV1(List<Map<String, Object?>> meds,
      {List<Map<String, Object?>> moves = const <Map<String, Object?>>[]}) async {
    final Database db = await factory.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (Database db, int v) async {
            await db.execute('''
              CREATE TABLE medicines (id TEXT PRIMARY KEY, name TEXT NOT NULL,
                brand TEXT, category TEXT, batch_no TEXT, barcode TEXT,
                quantity INTEGER NOT NULL DEFAULT 0, unit TEXT,
                low_stock_threshold INTEGER NOT NULL DEFAULT 10,
                purchase_price REAL NOT NULL DEFAULT 0,
                selling_price REAL NOT NULL DEFAULT 0, supplier_id TEXT,
                mfg_date INTEGER, expiry_date INTEGER NOT NULL, notes TEXT,
                created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
                is_deleted INTEGER NOT NULL DEFAULT 0)''');
            await db.execute('CREATE TABLE suppliers (id TEXT PRIMARY KEY, '
                'name TEXT NOT NULL, phone TEXT, email TEXT, address TEXT, '
                'created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)');
            await db.execute('CREATE TABLE stock_movements (id TEXT PRIMARY KEY, '
                'medicine_id TEXT NOT NULL, change INTEGER NOT NULL, '
                'reason TEXT NOT NULL, created_at INTEGER NOT NULL)');
          },
        ));
    for (final Map<String, Object?> m in meds) {
      await db.insert('medicines', m);
    }
    for (final Map<String, Object?> m in moves) {
      await db.insert('stock_movements', m);
    }
    await db.close();
  }

  Map<String, Object?> v1(String id, String name,
      {String batch = '',
      int qty = 0,
      String unit = 'Tablets',
      String brand = '',
      double sell = 0,
      double buy = 0,
      int deleted = 0}) {
    final int ts = DateTime(2026, 9, 1).millisecondsSinceEpoch;
    return <String, Object?>{
      'id': id,
      'name': name,
      'brand': brand,
      'category': 'Analgesic',
      'batch_no': batch,
      'barcode': '',
      'quantity': qty,
      'unit': unit,
      'low_stock_threshold': 10,
      'purchase_price': buy,
      'selling_price': sell,
      'expiry_date': DateTime(2027, 10, 31).millisecondsSinceEpoch,
      'notes': '',
      'created_at': ts,
      'updated_at': ts,
      'is_deleted': deleted,
    };
  }

  test('empty v1 database upgrades cleanly', () async {
    await makeV1(<Map<String, Object?>>[]);
    final Database db = await DatabaseHelper.instance.database;
    expect(await MedicineRepository().getAll(), isEmpty);
    final List<Map<String, Object?>> tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'");
    final Set<String> names = tables.map((Map<String, Object?> r) => r['name'] as String).toSet();
    expect(names, containsAll(<String>['products', 'batches', 'inv_movements', 'outbox', 'medicines_legacy']));
    expect(names, isNot(contains('medicines')));
  });

  test('batches of the same medicine group into one product; data intact', () async {
    final String a = const Uuid().v4(), b = const Uuid().v4(), c = const Uuid().v4();
    await makeV1(<Map<String, Object?>>[
      v1(a, 'Paracetamol 500', batch: 'B1', qty: 30, sell: 30.5, buy: 18),
      v1(b, '  paracetamol   500 ', batch: 'B2', qty: 70, sell: 32),
      v1(c, 'Cough Syrup', batch: 'S1', qty: 9, unit: 'ML'),
      v1(const Uuid().v4(), 'Old deleted', qty: 5, deleted: 1),
    ], moves: <Map<String, Object?>>[
      <String, Object?>{'id': 'x1', 'medicine_id': a, 'change': 30, 'reason': 'add', 'created_at': 1},
    ]);

    final Database db = await DatabaseHelper.instance.database;
    final MedicineRepository repo = MedicineRepository();
    final List<Medicine> all = await repo.getAll();

    expect(all, hasLength(3), reason: 'deleted rows are not migrated');
    expect(await repo.activeCount(), 2, reason: 'two products');
    final Medicine pa = all.firstWhere((Medicine m) => m.id == a);
    final Medicine pb = all.firstWhere((Medicine m) => m.id == b);
    expect(pa.productId, pb.productId);
    expect(Uuid.isValidUUID(fromString: pa.productId), isTrue);
    expect(<num>[pa.quantity, pa.sellingPrice, pa.purchasePrice, pb.quantity], <num>[30, 30.5, 18, 70]);
    expect(pa.batchNo, 'B1');
    expect(pa.expiryDate, DateTime(2027, 10, 31));
    expect(all.firstWhere((Medicine m) => m.id == c).unit, 'ML');

    // Pre-v2 history is still shown, without a duplicate opening entry.
    final List<StockMovement> hist = await repo.movementsFor(a);
    expect(hist.map((StockMovement s) => s.change), <int>[30]);

    // Nothing is queued for the server until the account is linked.
    expect(await db.query('outbox'), isEmpty);
    expect((await db.query('medicines_legacy')).length, 4, reason: 'v1 rows kept');
  });

  test('writes after the upgrade go through the ledger and the outbox', () async {
    final String a = const Uuid().v4();
    await makeV1(<Map<String, Object?>>[v1(a, 'Paracetamol 500', batch: 'B1', qty: 30, sell: 30)]);
    final MedicineRepository repo = MedicineRepository();
    await DatabaseHelper.instance.database;

    await repo.adjustQuantity(a, -5, StockReason.sell);
    final Medicine m = (await repo.getById(a))!;
    expect(m.quantity, 25);

    await repo.update(m.copyWith(sellingPrice: 32));
    final Database db = await DatabaseHelper.instance.database;
    final List<Map<String, Object?>> out = await db.query('outbox', orderBy: 'seq');
    expect(out.map((Map<String, Object?> r) => r['table_name']), <String>['stock_movements', 'batches']);
    expect(jsonDecode(out.last['data'] as String), <String, Object?>{'mrp_paise': 3200});
    expect(jsonDecode(out.first['data'] as String)['reason'], 'sale');

    // Selling more than is in stock never goes below zero locally.
    await repo.adjustQuantity(a, -100, StockReason.sell);
    expect((await repo.getById(a))!.quantity, 0);
  });

  test('a new batch of an existing medicine joins its product', () async {
    await makeV1(<Map<String, Object?>>[]);
    final MedicineRepository repo = MedicineRepository();
    final DateTime now = DateTime.now();
    Medicine mk(String batch, int qty) => Medicine(
        id: const Uuid().v4(),
        name: 'Dolo 650',
        brand: 'Micro Labs',
        batchNo: batch,
        quantity: qty,
        expiryDate: DateTime(2027, 1, 31),
        createdAt: now,
        updatedAt: now);

    await repo.insert(mk('D1', 3));
    await repo.insert(mk('D2', 7));
    final List<Medicine> all = await repo.getAll();
    expect(all, hasLength(2));
    expect(all[0].productId, all[1].productId);
    expect(await repo.activeCount(), 1);
    expect(await repo.existsNameBatch('dolo  650', 'd1'), isTrue);
  });
}
