import 'package:flutter_test/flutter_test.dart';
import 'package:med_stock/data/db/database_helper.dart';
import 'package:med_stock/data/models/medicine.dart';
import 'package:med_stock/data/repositories/medicine_repository.dart';
import 'package:med_stock/domain/medicine_status.dart';
import 'package:med_stock/domain/product_stock.dart';
import 'package:med_stock/state/medicine_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

void main() {
  sqfliteFfiInit();
  final DateTime now = DateTime.now();
  DateTime inDays(int d) => DateTime(now.year, now.month, now.day + d);

  Medicine batch(String name, int qty, DateTime exp, {String brand = 'Acme', int low = 10}) => Medicine(
        id: const Uuid().v4(),
        name: name,
        brand: brand,
        batchNo: 'B${const Uuid().v4().substring(0, 4)}',
        quantity: qty,
        lowStockThreshold: low,
        expiryDate: exp,
        createdAt: now,
        updatedAt: now,
      );

  late DatabaseHelper db;
  late MedicineProvider mp;
  late String path;

  setUp(() async {
    path = '${await databaseFactoryFfi.getDatabasesPath()}/ps_${const Uuid().v4()}.db';
    db = DatabaseHelper.at(databaseFactoryFfi, path);
    mp = MedicineProvider(MedicineRepository(db))..warningDays = 30;
  });

  tearDown(() async {
    await db.close();
    await databaseFactoryFfi.deleteDatabase(path);
  });

  test('batches group per medicine; low stock uses the total across batches', () async {
    // Paracetamol: 6 + 6 = 12 > 10 -> not low, though each batch alone is.
    await mp.add(batch('Paracetamol', 6, inDays(200)));
    await mp.add(batch('Paracetamol', 6, inDays(100)), allowDuplicate: true);
    // Cetirizine: 4 in total -> low.
    await mp.add(batch('Cetirizine', 4, inDays(300)));

    expect(mp.productCount, 2);
    final ProductStock para = mp.products.firstWhere((ProductStock p) => p.name == 'Paracetamol');
    expect(para.totalQty, 12);
    expect(para.batches.first.expiryDate, inDays(100), reason: 'earliest expiry first');
    expect(para.isLowStock, isFalse);
    expect(mp.statusOf(para.batches.first).isLowStock, isFalse, reason: 'batch status uses product total');

    expect(mp.lowStockCount, 1);
    expect(mp.lowStockProducts.single.name, 'Cetirizine');
    mp.setFilter(MedicineFilter.lowStock);
    expect(mp.visibleProducts.map((ProductStock p) => p.name), <String>['Cetirizine']);
  });

  test('expiry alerts only count batches that still have stock', () async {
    await mp.add(batch('ORS', 0, inDays(-5), low: 0)); // expired but empty
    await mp.add(batch('ORS', 20, inDays(10), low: 0), allowDuplicate: true); // expiring
    await mp.add(batch('Dolo', 5, inDays(-1), low: 0)); // expired with stock

    expect(mp.expiredCount, 1);
    expect(mp.expiredBatches.single.name, 'Dolo');
    expect(mp.expiringCount, 1);
    expect(mp.productsExpiredCount, 1, reason: 'ORS has no stocked expired batch');
    expect(mp.productsExpiringCount, 1);

    final ProductStock ors = mp.products.firstWhere((ProductStock p) => p.name == 'ORS');
    expect(ors.nearestExpiry, inDays(10), reason: 'empty expired batch ignored');
    expect(ors.worstExpiry(30), ExpiryState.expiring);

    mp.setFilter(MedicineFilter.expired);
    expect(mp.visibleProducts.map((ProductStock p) => p.name), <String>['Dolo']);
  });

  test('free plan limit counts medicines, not batches', () async {
    mp.isPremium = false;
    for (int i = 0; i < 7; i++) {
      await mp.add(batch('Med $i', 1, inDays(100)));
    }
    expect(mp.canAdd(), isFalse);
    expect(mp.productCount, 7);
  });
}
