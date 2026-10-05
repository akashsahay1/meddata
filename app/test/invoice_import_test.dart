import 'package:flutter_test/flutter_test.dart';
import 'package:med_stock/data/db/database_helper.dart';
import 'package:med_stock/data/models/medicine.dart';
import 'package:med_stock/data/repositories/medicine_repository.dart';
import 'package:med_stock/domain/invoice_draft.dart';
import 'package:med_stock/domain/product_stock.dart';
import 'package:med_stock/state/medicine_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

/// Adding the reviewed lines of a scanned invoice goes through the same
/// repository insert as a manual add.
void main() {
  sqfliteFfiInit();
  final DatabaseFactory factory = databaseFactoryFfi;
  late DatabaseHelper helper;
  late MedicineProvider mp;
  late String path;
  final DateTime now = DateTime(2026, 10, 5);

  setUp(() async {
    path =
        '${await factory.getDatabasesPath()}/invoice_${const Uuid().v4()}.db';
    helper = DatabaseHelper.at(factory, path);
    mp = MedicineProvider(MedicineRepository(helper));
  });

  tearDown(() async {
    await helper.close();
    await factory.deleteDatabase(path);
  });

  Medicine manual(
    String name, {
    String unit = 'Strips',
    String brand = 'Micro Labs',
  }) => Medicine(
    id: const Uuid().v4(),
    name: name,
    brand: brand,
    unit: unit,
    batchNo: 'OLD1',
    quantity: 5,
    expiryDate: DateTime(2027, 1, 31),
    createdAt: now,
    updatedAt: now,
  );

  /// Draft lines for these invoice items, matched like the scan screen does.
  List<Medicine> fromInvoice(List<Map<String, dynamic>> items) {
    final InvoiceDraft draft = InvoiceDraftMapper.fromResult(<String, dynamic>{
      'items': items,
    }, products: mp.products);
    return <Medicine>[
      for (final InvoiceDraftLine l in draft.lines)
        l.toMedicine(id: const Uuid().v4(), now: now),
    ];
  }

  Map<String, dynamic> item(String name, String batch) => <String, dynamic>{
    'product_name': name,
    'pack': "15's",
    'batch_no': batch,
    'expiry_date': '2028-03-31',
    'quantity': 10,
    'free_quantity': 2,
    'mrp': 30,
    'purchase_rate': 20,
  };

  Future<int> outboxCount(String table) async =>
      (await (await helper.database).query(
        'outbox',
        where: 'table_name = ?',
        whereArgs: <Object?>[table],
      )).length;

  test(
    'a known medicine gets a new batch; others become new medicines',
    () async {
      mp.isPremium = true;
      await mp.add(manual('Dolo 650'));
      final String doloId = mp.products.single.productId;

      final List<Medicine> items = fromInvoice(<Map<String, dynamic>>[
        item('DOLO 650 TAB', 'NEW1'),
        item('AZITHRAL 500 TAB', 'AZ9'),
      ]);
      expect(mp.countNewProducts(items), 1);
      expect(await mp.addFromInvoice(items), AddResult.success);

      expect(mp.productCount, 2);
      final ProductStock dolo = mp.productById(doloId)!;
      expect(dolo.batches.map((Medicine m) => m.batchNo).toSet(), <String>{
        'OLD1',
        'NEW1',
      });
      expect(dolo.totalQty, 5 + 12);
      final Medicine azithral = mp.products
          .firstWhere((ProductStock p) => p.productId != doloId)
          .first;
      expect(
        <Object>[
          azithral.name,
          azithral.unit,
          azithral.quantity,
          azithral.sellingPrice,
        ],
        <Object>['AZITHRAL 500 TAB', 'Strips', 12, 30.0],
      );
      // Queued for sync like manual adds: 2 products, 3 batches, 3 movements.
      expect(await outboxCount('products'), 2);
      expect(await outboxCount('batches'), 3);
      expect(await outboxCount('stock_movements'), 3);
    },
  );

  test(
    'the free plan refuses an invoice whose new medicines do not fit',
    () async {
      mp.isPremium = false;
      for (int i = 1; i <= 6; i++) {
        await mp.add(manual('Medicine $i'));
      }

      final List<Medicine> tooMany = fromInvoice(<Map<String, dynamic>>[
        item('NEW ONE', 'A'),
        item('NEW TWO', 'B'),
        item('MEDICINE 1', 'C'), // a batch of a known one is free
      ]);
      expect(mp.countNewProducts(tooMany), 2);
      expect(mp.canAddProducts(2), isFalse);
      expect(await mp.addFromInvoice(tooMany), AddResult.blockedByFreeLimit);
      expect(mp.totalCount, 6); // nothing was added

      final List<Medicine> fits = fromInvoice(<Map<String, dynamic>>[
        item('NEW ONE', 'A'),
        item('NEW ONE', 'A2'), // same new medicine twice = one product
        item('MEDICINE 1', 'C'),
      ]);
      expect(mp.countNewProducts(fits), 1);
      expect(await mp.addFromInvoice(fits), AddResult.success);
      expect(mp.productCount, 7);
      expect(mp.totalCount, 9);
    },
  );
}
