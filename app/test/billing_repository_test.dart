import 'package:flutter_test/flutter_test.dart';
import 'package:med_stock/data/db/database_helper.dart';
import 'package:med_stock/data/models/medicine.dart';
import 'package:med_stock/data/models/stock_movement.dart';
import 'package:med_stock/data/repositories/billing_repository.dart';
import 'package:med_stock/data/repositories/medicine_repository.dart';
import 'package:med_stock/domain/fefo.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

void main() {
  sqfliteFfiInit();
  final DatabaseFactory factory = databaseFactoryFfi;
  late DatabaseHelper helper;
  late MedicineRepository meds;
  late BillingRepository billing;
  late String path;

  setUp(() async {
    path = '${await factory.getDatabasesPath()}/billing_${const Uuid().v4()}.db';
    helper = DatabaseHelper.at(factory, path);
    meds = MedicineRepository(helper);
    billing = BillingRepository(helper);
  });

  tearDown(() async {
    await helper.close();
    await factory.deleteDatabase(path);
  });

  Medicine med(String batch, int qty, DateTime expiry, {double mrp = 30}) {
    final DateTime now = DateTime.now();
    return Medicine(
      id: const Uuid().v4(),
      name: 'Dolo 650',
      brand: 'Micro Labs',
      batchNo: batch,
      quantity: qty,
      sellingPrice: mrp,
      expiryDate: expiry,
      createdAt: now,
      updatedAt: now,
      hsn: '3004',
      gstRateBp: 500,
    );
  }

  test('sale batches carry price, version, GST and current stock', () async {
    final Medicine a = med('A1', 10, DateTime(2027, 3, 31), mrp: 32.5);
    final Medicine b = med('B1', 4, DateTime(2026, 12, 31));
    await meds.insert(a);
    await meds.insert(b);
    await meds.adjustQuantity(a.id, -3, StockReason.sell);
    // The server has seen batch B at version 8.
    await (await helper.database)
        .update('batches', <String, Object?>{'version': 8}, where: 'id = ?', whereArgs: <Object?>[b.id]);

    final String productId = (await meds.getById(a.id))!.productId;
    final List<SaleBatch> batches = await billing.batchesOf(productId);
    expect(batches.map((SaleBatch s) => s.batchNo), <String>['B1', 'A1'], reason: 'earliest expiry first');
    final SaleBatch sa = batches.last;
    expect(<Object?>[sa.productName, sa.qty, sa.mrpPaise, sa.version, sa.hsn, sa.gstRateBp],
        <Object?>['Dolo 650', 7, 3250, 0, '3004', 500]);
    expect(batches.first.version, 8);
  });

  test("the server's stock after a bill shows at once", () async {
    final Medicine a = med('A1', 10, DateTime(2027, 3, 31));
    await meds.insert(a);
    final Database db = await helper.database;
    // Opening stock has synced: it's part of the server qty now.
    await db.update('inv_movements', <String, Object?>{'synced': 1});
    await db.update('batches', <String, Object?>{'server_qty_units': 10});

    await billing.applyServerStock(<String, int>{a.id: 7});
    expect((await meds.getById(a.id))!.quantity, 7);
  });

  test('HSN and GST rate are saved on the product and queued for sync', () async {
    final Medicine a = med('A1', 1, DateTime(2027, 3, 31));
    await meds.insert(a);
    final Medicine back = (await meds.getById(a.id))!;
    expect(<Object?>[back.hsn, back.gstRateBp], <Object?>['3004', 500]);

    await meds.update(back.copyWith(gstRateBp: 1200, hsn: '30049099'));
    final Medicine edited = (await meds.getById(a.id))!;
    expect(<Object?>[edited.hsn, edited.gstRateBp], <Object?>['30049099', 1200]);

    await meds.update(edited.copyWith(clearGstRate: true));
    expect((await meds.getById(a.id))!.gstRateBp, isNull);
  });
}
