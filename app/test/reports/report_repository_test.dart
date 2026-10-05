import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:med_stock/data/db/database_helper.dart';
import 'package:med_stock/data/models/medicine.dart';
import 'package:med_stock/data/models/stock_movement.dart';
import 'package:med_stock/data/repositories/medicine_repository.dart';
import 'package:med_stock/data/repositories/report_repository.dart';
import 'package:med_stock/domain/reports/expiry_loss.dart';
import 'package:med_stock/domain/reports/stock_valuation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

void main() {
  sqfliteFfiInit();
  final DatabaseFactory factory = databaseFactoryFfi;
  late DatabaseHelper helper;
  late MedicineRepository meds;
  late ReportRepository reports;
  late String path;

  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day);

  setUp(() async {
    path = '${await factory.getDatabasesPath()}/reports_${const Uuid().v4()}.db';
    helper = DatabaseHelper.at(factory, path);
    meds = MedicineRepository(helper);
    reports = ReportRepository(helper);
  });

  tearDown(() async {
    await helper.close();
    await factory.deleteDatabase(path);
  });

  /// Adds a batch [createdDaysAgo] days ago with [qty] opening stock.
  Future<Medicine> add(String name, int qty,
      {int expiresIn = 200,
      double mrp = 30,
      double cost = 20,
      int createdDaysAgo = 0}) async {
    final DateTime at = now.subtract(Duration(days: createdDaysAgo));
    final Medicine m = Medicine(
      id: const Uuid().v4(),
      name: name,
      category: 'Pain Relief',
      batchNo: '$name-1',
      quantity: qty,
      sellingPrice: mrp,
      purchasePrice: cost,
      expiryDate: today.add(Duration(days: expiresIn)),
      createdAt: at,
      updatedAt: at,
    );
    await meds.insert(m);
    // The opening movement is stamped "now"; move it back to the add date.
    await (await helper.database).update(
        'inv_movements', <String, Object?>{'occurred_at': at.millisecondsSinceEpoch},
        where: 'batch_id = ?', whereArgs: <Object?>[m.id]);
    return m;
  }

  StockRow rowOf(List<StockRow> rows, String id) =>
      rows.firstWhere((StockRow r) => r.batchId == id);

  test('stock today, with prices in paise', () async {
    final Medicine dolo = await add('Dolo 650', 10, mrp: 30, cost: 20.5);
    final StockRow r = rowOf(await reports.stockAsOf(), dolo.id);
    expect(<Object>[r.qty, r.mrpPaise, r.costPaise, r.name, r.category],
        <Object>[10, 3000, 2050, 'Dolo 650', 'Pain Relief']);
  });

  test('stock on a past date takes back the movements after it', () async {
    final Medicine dolo = await add('Dolo 650', 10, createdDaysAgo: 20);
    final Medicine late = await add('Crocin', 7, createdDaysAgo: 2);
    // Sold 4 Dolo 5 days ago, 1 today.
    await meds.adjustQuantity(dolo.id, -4, StockReason.sell,
        now: now.subtract(const Duration(days: 5)));
    await meds.adjustQuantity(dolo.id, -1, StockReason.sell);

    final List<StockRow> nowRows = await reports.stockAsOf();
    expect(rowOf(nowRows, dolo.id).qty, 5);

    final List<StockRow> tenDaysAgo =
        await reports.stockAsOf(today.subtract(const Duration(days: 10)));
    expect(rowOf(tenDaysAgo, dolo.id).qty, 10);
    expect(rowOf(tenDaysAgo, late.id).qty, 0, reason: 'not bought yet');

    final List<StockRow> yesterday =
        await reports.stockAsOf(today.subtract(const Duration(days: 1)));
    expect(rowOf(yesterday, dolo.id).qty, 6);
    expect(rowOf(yesterday, late.id).qty, 7);

    // Movements already synced (pulled from the server) count the same way.
    final Database db = await helper.database;
    await db.rawUpdate('UPDATE batches SET server_qty_units = 5 WHERE id = ?', <Object?>[dolo.id]);
    await db.rawUpdate('UPDATE inv_movements SET synced = 1 WHERE batch_id = ?', <Object?>[dolo.id]);
    expect(rowOf(await reports.stockAsOf(today.subtract(const Duration(days: 10))), dolo.id).qty, 10);
    expect(rowOf(await reports.stockAsOf(), dolo.id).qty, 5);
  });

  test('writing off an expired batch zeroes it through the outbox', () async {
    final Medicine old = await add('Old Tonic', 6, expiresIn: -3, mrp: 50, cost: 30);
    final Medicine fresh = await add('Dolo 650', 10);
    final Medicine today0 = await add('Last Day', 2, expiresIn: 0);

    expect(await meds.writeOffExpired(fresh.id), 0, reason: 'not expired');
    expect(await meds.writeOffExpired(today0.id), 0, reason: 'sellable on its expiry date');
    expect(await meds.writeOffExpired(old.id), 6);
    expect(await meds.writeOffExpired(old.id), 0, reason: 'nothing left');

    expect((await meds.getById(old.id))!.quantity, 0);
    expect((await meds.getById(fresh.id))!.quantity, 10);

    final List<Map<String, Object?>> queued = await (await helper.database).query(
        'outbox',
        where: "table_name = 'stock_movements'",
        orderBy: 'seq DESC',
        limit: 1);
    final Map<String, dynamic> data =
        jsonDecode(queued.single['data']! as String) as Map<String, dynamic>;
    expect(<Object?>[data['batch_id'], data['delta_units'], data['reason']],
        <Object?>[old.id, -6, 'expiry_writeoff']);

    final List<WriteOff> offs = await reports.writeOffs();
    expect(offs.single.units, 6);
    expect(<int>[offs.single.costPaise, offs.single.mrpPaise], <int>[3000, 5000]);

    // Gone from valuation, recorded as a loss in its expiry month.
    final StockValuation v =
        StockValuation.build(await reports.stockAsOf(), asOf: today);
    expect(v.expired.isEmpty, isTrue);
    final ExpiryLoss e = ExpiryLoss.build(
        stock: await reports.stockAsOf(), writeOffs: offs, today: today);
    expect(<int>[e.writtenOff.costPaise, e.writtenOff.mrpPaise], <int>[18000, 30000]);
    expect(e.pending.isEmpty, isTrue);

    // The history shows it as an adjustment.
    expect((await meds.movementsFor(old.id)).first.change, -6);
  });

  test('a write-off pulled from another device counts too', () async {
    final Medicine old = await add('Old Tonic', 4, expiresIn: -40);
    await (await helper.database).insert('inv_movements', <String, Object?>{
      'id': const Uuid().v4(),
      'batch_id': old.id,
      'product_id': old.productId.isEmpty
          ? (await meds.getById(old.id))!.productId
          : old.productId,
      'delta_units': -4,
      'reason': 'expiry_writeoff',
      'occurred_at': now.millisecondsSinceEpoch,
      'synced': 1,
    });
    expect((await reports.writeOffs()).single.units, 4);
  });
}
