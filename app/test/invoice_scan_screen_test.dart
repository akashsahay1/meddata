import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:med_stock/data/models/medicine.dart';
import 'package:med_stock/data/repositories/medicine_repository.dart';
import 'package:med_stock/domain/product_stock.dart';
import 'package:med_stock/presentation/screens/invoice_scan_screen.dart';
import 'package:med_stock/services/invoice_scan_service.dart';
import 'package:med_stock/state/medicine_provider.dart';
import 'package:med_stock/sync/sync_engine.dart';
import 'package:provider/provider.dart';

/// In-memory stand-in for the SQLite repository: a batch joins the product
/// with the same name, unit and brand, like the real one.
class _MemoryRepo extends MedicineRepository {
  final List<Medicine> rows = <Medicine>[];

  static String _norm(String s) => s.trim().toLowerCase();

  @override
  Future<List<Medicine>> getAll() async => List<Medicine>.of(rows);

  @override
  Future<bool> existsNameBatch(
    String name,
    String batchNo, {
    String? excludeId,
  }) async => rows.any(
    (Medicine r) =>
        _norm(r.name) == _norm(name) && _norm(r.batchNo) == _norm(batchNo),
  );

  @override
  Future<void> insert(Medicine m) async {
    final Iterable<Medicine> same = rows.where(
      (Medicine r) =>
          _norm(r.name) == _norm(m.name) &&
          r.unit == m.unit &&
          _norm(r.brand) == _norm(m.brand),
    );
    rows.add(
      Medicine(
        id: m.id,
        productId: same.isEmpty ? 'p${rows.length}' : same.first.productId,
        name: m.name,
        brand: m.brand,
        category: m.category,
        batchNo: m.batchNo,
        barcode: m.barcode,
        quantity: m.quantity,
        unit: m.unit,
        lowStockThreshold: m.lowStockThreshold,
        purchasePrice: m.purchasePrice,
        sellingPrice: m.sellingPrice,
        mfgDate: m.mfgDate,
        expiryDate: m.expiryDate,
        notes: m.notes,
        createdAt: m.createdAt,
        updatedAt: m.updatedAt,
      ),
    );
  }
}

void main() {
  // A budget phone, a common one and a desktop window.
  for (final Size size in <Size>[
    const Size(320, 640),
    const Size(360, 760),
    const Size(1280, 800),
  ]) {
    testWidgets('review, fix and add the lines of a read invoice '
        '(${size.width.toInt()} px wide)', (WidgetTester tester) async {
      await _reviewFixAndAdd(tester, size);
    });
  }
}

Future<void> _reviewFixAndAdd(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final _MemoryRepo repo = _MemoryRepo();
  final MedicineProvider mp = MedicineProvider(repo)..isPremium = true;
  await mp.add(
    Medicine(
      id: 'old',
      name: 'Dolo 650',
      brand: 'Micro Labs',
      unit: 'Tablets',
      batchNo: 'OLD1',
      quantity: 30,
      expiryDate: DateTime(2027, 1, 31),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    ),
  );
  final SyncEngine sync = SyncEngine(
    tokenProvider: () => null,
    userKeyProvider: () => null,
  );

  const InvoiceScan scan = InvoiceScan(
    id: 1,
    status: 'done',
    result: <String, dynamic>{
      'supplier_name': 'Shree Ganesh Pharma',
      'invoice_no': 'SG/1',
      'invoice_date': '2026-10-01',
      'notes': 'Second page looks cut off.',
      'items': <Object>[
        <String, dynamic>{
          'product_name': 'DOLO 650 TAB',
          'manufacturer': 'MICRO',
          'pack': "15's",
          'batch_no': 'DOBS1',
          'expiry_date': '2027-06-30',
          'quantity': 2,
          'free_quantity': 0,
          'mrp': 30,
          'purchase_rate': 20,
        },
        <String, dynamic>{
          'product_name': 'AZITHRAL 500 TAB',
          'pack': "5's",
          'batch_no': 'AZ9',
          'expiry_date': null,
          'quantity': 4,
          'mrp': 119.5,
          'purchase_rate': 80,
        },
      ],
    },
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<MedicineProvider>.value(value: mp),
        ChangeNotifierProvider<SyncEngine>.value(value: sync),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const InvoiceScanScreen(initialScan: scan),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();

  // The review: supplier, counts, the reader's note and both lines.
  expect(find.text('Shree Ganesh Pharma'), findsOneWidget);
  expect(find.text('2 items · 1 new medicine · 1 to fix'), findsOneWidget);
  expect(find.text('Second page looks cut off.'), findsOneWidget);
  expect(
    find.text('Dolo 650'),
    findsOneWidget,
  ); // linked to the shop's medicine
  expect(find.text('On the bill: DOLO 650 TAB'), findsOneWidget);
  expect(find.text("Qty 2 · pack 15's → 30 Tablets"), findsOneWidget);
  await tester.scrollUntilVisible(find.text('Expiry date missing'), 200);
  expect(find.text('Expiry date missing'), findsOneWidget);

  // An item still marked red blocks adding.
  await tester.tap(find.text('Add 2 items'));
  await tester.pump();
  expect(
    find.textContaining('Fix the item marked in red first'),
    findsOneWidget,
  );
  expect(repo.rows, hasLength(1));

  // Fix it: set the expiry in the editor.
  await tester.tap(find.text('AZITHRAL 500 TAB'));
  await tester.pumpAndSettle();
  expect(find.text('Edit item'), findsOneWidget);
  await tester.tap(find.text('Not set').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Save')); // pinned below the fields
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text('AZITHRAL 500 TAB'), -200);
  await tester.pumpAndSettle();
  expect(find.text('Expiry date missing'), findsNothing);

  await tester.tap(find.text('Add 2 items'));
  await tester.pumpAndSettle();

  // Back where we came from; one new batch, one new medicine.
  expect(find.text('open'), findsOneWidget);
  expect(find.text('Added 2 items from invoice SG/1'), findsOneWidget);
  expect(mp.productCount, 2);
  final ProductStock dolo = mp.products.firstWhere(
    (ProductStock p) => p.name == 'Dolo 650',
  );
  expect(dolo.batches.map((Medicine m) => m.batchNo).toSet(), <String>{
    'OLD1',
    'DOBS1',
  });
  expect(dolo.totalQty, 30 + 30);
  final Medicine azithral = mp.products
      .firstWhere((ProductStock p) => p.name != 'Dolo 650')
      .first;
  expect(
    <Object>[azithral.name, azithral.unit, azithral.quantity],
    <Object>['AZITHRAL 500 TAB', 'Strips', 4],
  );
}
