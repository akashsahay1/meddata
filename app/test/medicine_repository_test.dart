import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:med_stock/data/db/database_helper.dart';
import 'package:med_stock/data/models/medicine.dart';
import 'package:med_stock/data/models/stock_movement.dart';
import 'package:med_stock/data/repositories/medicine_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

void main() {
  sqfliteFfiInit();
  final DatabaseFactory factory = databaseFactoryFfi;
  late DatabaseHelper helper;
  late MedicineRepository repo;
  late String path;

  setUp(() async {
    path = '${await factory.getDatabasesPath()}/repo_${const Uuid().v4()}.db';
    helper = DatabaseHelper.at(factory, path);
    repo = MedicineRepository(helper);
  });

  tearDown(() async {
    await helper.close();
    await factory.deleteDatabase(path);
  });

  Medicine med(String name, String batch, int qty, {double mrp = 30, String brand = 'Micro Labs'}) {
    final DateTime now = DateTime.now();
    return Medicine(
        id: const Uuid().v4(),
        name: name,
        brand: brand,
        batchNo: batch,
        quantity: qty,
        sellingPrice: mrp,
        purchasePrice: 18,
        expiryDate: DateTime(2027, 1, 31),
        createdAt: now,
        updatedAt: now);
  }

  Future<List<Map<String, Object?>>> outbox() async =>
      (await helper.database).query('outbox', orderBy: 'seq');

  test('adding a medicine creates product + batch + opening stock, queued for sync', () async {
    final Medicine m = med('Dolo 650', 'D1', 15);
    await repo.insert(m);

    final Medicine back = (await repo.getById(m.id))!;
    expect(<Object>[back.name, back.batchNo, back.quantity, back.sellingPrice, back.purchasePrice],
        <Object>['Dolo 650', 'D1', 15, 30.0, 18.0]);
    expect((await outbox()).map((Map<String, Object?> r) => r['table_name']),
        <String>['products', 'batches', 'stock_movements']);
    final Map<String, Object?> batch = jsonDecode((await outbox())[1]['data'] as String) as Map<String, Object?>;
    expect(batch['expiry_date'], '2027-01-31');
    expect(batch['mrp_paise'], 3000);
    expect((await repo.movementsFor(m.id)).single.reason, StockReason.add);
  });

  test('a new batch of an existing medicine joins its product', () async {
    await repo.insert(med('Dolo 650', 'D1', 3));
    await repo.insert(med('  dolo   650 ', 'D2', 7));
    await repo.insert(med('Dolo 650', 'X1', 1, brand: 'Other Co'));
    final List<Medicine> all = await repo.getAll();
    expect(all, hasLength(3));
    expect(all.where((Medicine m) => m.brand == 'Micro Labs').map((Medicine m) => m.productId).toSet(), hasLength(1));
    expect(await repo.activeCount(), 2, reason: 'same name, different maker = separate product');
    expect(await repo.existsNameBatch('DOLO 650', 'd1'), isTrue);
  });

  test('edits and stock changes go through the ledger and the outbox', () async {
    final Medicine m = med('Paracetamol 500', 'B1', 30);
    await repo.insert(m);
    (await helper.database).delete('outbox');

    await repo.adjustQuantity(m.id, -5, StockReason.sell);
    expect((await repo.getById(m.id))!.quantity, 25);

    await repo.update((await repo.getById(m.id))!.copyWith(sellingPrice: 32));
    final List<Map<String, Object?>> out = await outbox();
    expect(out.map((Map<String, Object?> r) => r['table_name']), <String>['stock_movements', 'batches']);
    expect(jsonDecode(out.first['data'] as String)['reason'], 'sale');
    expect(jsonDecode(out.last['data'] as String), <String, Object?>{'mrp_paise': 3200});

    // A second unsent edit merges into the same pending change.
    await repo.update((await repo.getById(m.id))!.copyWith(purchasePrice: 20));
    expect((await outbox()).length, 2);
    expect(jsonDecode((await outbox()).last['data'] as String),
        <String, Object?>{'mrp_paise': 3200, 'purchase_rate_paise': 2000});

    // Quantity typed in the form becomes an 'adjust' movement.
    await repo.update((await repo.getById(m.id))!.copyWith(quantity: 40));
    expect((await repo.getById(m.id))!.quantity, 40);
    expect(jsonDecode((await outbox()).last['data'] as String)['delta_units'], 15);

    // Selling more than is in stock never goes below zero locally.
    await repo.adjustQuantity(m.id, -100, StockReason.sell);
    expect((await repo.getById(m.id))!.quantity, 0);
  });

  test('deleting the last batch deletes the product; undo before sync cancels it', () async {
    final Medicine m = med('ORS', 'O1', 4);
    await repo.insert(m);
    await repo.softDelete(m.id);
    expect(await repo.getAll(), isEmpty);
    expect(await repo.activeCount(), 0);

    await repo.restore(m.id);
    expect((await repo.getAll()).single.id, m.id);
    expect((await outbox()).where((Map<String, Object?> r) => r['op'] == 'delete'), isEmpty);
  });
}
