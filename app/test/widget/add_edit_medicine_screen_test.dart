import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:med_stock/core/formatters.dart';
import 'package:med_stock/data/models/medicine.dart';
import 'package:med_stock/domain/product_stock.dart';
import 'package:med_stock/presentation/screens/add_edit_medicine_screen.dart';

import '../support/finders.dart';
import '../support/test_app.dart';

void main() {
  setUpAll(loadAppFont);

  Future<TestApp> start(WidgetTester tester) async {
    usePhoneScreen(tester, height: 1400);
    final TestApp app = await TestApp.create();
    addTearDown(app.dispose);
    return app;
  }

  Future<void> save(WidgetTester tester, String button) async {
    await tester.tap(find.text(button));
    await tester.pumpAndSettle();
  }

  Future<void> answer(WidgetTester tester, String button) =>
      answerDialog(tester, button);

  group('add medicine', () {
    testWidgets('name and quantity are required; nothing is saved without them',
        (WidgetTester tester) async {
      final TestApp app = await start(tester);
      await app.open(tester, AddEditMedicineScreen(api: app.backend.api));
      expect(find.text('Add Medicine'), findsOneWidget);

      await save(tester, 'Add medicine');
      expect(find.text('Required'), findsNWidgets(2));
      expect(app.medicines.productCount, 0);
      expect(find.byType(AddEditMedicineScreen), findsOneWidget);

      // Each error clears as soon as its field is filled in.
      await tester.enterText(fieldLabeled('Medicine name *'), 'Dolo 650');
      await tester.pump();
      expect(find.text('Required'), findsOneWidget);
      await tester.enterText(fieldLabeled('Quantity *'), '15');
      await tester.pump();
      expect(find.text('Required'), findsNothing);
    });

    testWidgets('saving adds the medicine with its first batch and closes',
        (WidgetTester tester) async {
      final TestApp app = await start(tester);
      await app.open(tester, AddEditMedicineScreen(api: app.backend.api));

      await tester.enterText(fieldLabeled('Medicine name *'), ' Dolo 650 ');
      await tester.enterText(fieldLabeled('Brand'), 'Micro Labs');
      await tester.enterText(fieldLabeled('Batch / lot no.'), 'D1');
      await tester.enterText(fieldLabeled('Quantity *'), '15');
      await tester.enterText(fieldLabeled('Purchase price'), '18');
      await tester.enterText(fieldLabeled('Selling price (MRP)'), '30.50');
      await save(tester, 'Add medicine');

      expect(find.byType(AddEditMedicineScreen), findsNothing);
      final ProductStock p = app.medicines.products.single;
      expect(p.name, 'Dolo 650', reason: 'name is trimmed');
      expect(p.brand, 'Micro Labs');
      expect(p.totalQty, 15);
      expect(p.unit, 'Tablets');
      expect(p.category, 'Uncategorised');
      expect(p.lowStockThreshold, 10);
      final Medicine b = p.batches.single;
      expect(b.batchNo, 'D1');
      expect(b.sellingPrice, 30.5);
      expect(b.purchasePrice, 18);
      expect(b.mfgDate, isNull);
      expect(dateOnly(b.expiryDate), dateOnly(DateTime.now().add(const Duration(days: 365))),
          reason: 'expiry defaults to a year ahead');
    });

    testWidgets('the same name and batch again asks before adding a duplicate',
        (WidgetTester tester) async {
      final TestApp app = await start(tester);
      await app.addBatch('Dolo 650', batch: 'D1', qty: 10);
      await app.open(tester, AddEditMedicineScreen(api: app.backend.api));

      await tester.enterText(fieldLabeled('Medicine name *'), 'dolo  650');
      await tester.enterText(fieldLabeled('Batch / lot no.'), 'd1');
      await tester.enterText(fieldLabeled('Quantity *'), '5');
      await save(tester, 'Add medicine');
      expect(find.text('Possible duplicate'), findsOneWidget);
      await answer(tester, 'Cancel');
      expect(app.medicines.totalCount, 1);
      expect(find.byType(AddEditMedicineScreen), findsOneWidget);

      await save(tester, 'Add medicine');
      await answer(tester, 'Add anyway');
      expect(find.byType(AddEditMedicineScreen), findsNothing);
      expect(app.medicines.totalCount, 2);
    });
  });

  group('dates', () {
    testWidgets('manufacture date is at most today; expiry comes after it',
        (WidgetTester tester) async {
      final TestApp app = await start(tester);
      await app.open(tester, AddEditMedicineScreen(api: app.backend.api));
      expect(find.text('Not set'), findsOneWidget);

      await tester.tap(dateField('Manufacture date'));
      await tester.pumpAndSettle();
      DatePickerDialog picker =
          tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
      expect(picker.lastDate, day(0), reason: 'no future manufacture date');
      expect(picker.firstDate, DateTime(2000));
      await answer(tester, 'OK'); // picks today
      expect(find.text(Fmt.date(day(0))), findsOneWidget);

      await tester.tap(dateField('Expiry date *'));
      await tester.pumpAndSettle();
      picker = tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
      expect(picker.firstDate, day(1), reason: 'expiry after manufacture');
      await answer(tester, 'Cancel');
    });

    testWidgets('an expired batch can only get a manufacture date before expiry',
        (WidgetTester tester) async {
      final TestApp app = await start(tester);
      final Medicine m = await app.addBatch('ORS', expiresInDays: -10);
      await app.open(
          tester, AddEditMedicineScreen(existing: m, api: app.backend.api));

      await tester.tap(dateField('Manufacture date'));
      await tester.pumpAndSettle();
      final DatePickerDialog picker =
          tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
      expect(picker.lastDate, day(-11));
    });

    testWidgets('saving refuses a future manufacture date',
        (WidgetTester tester) async {
      final TestApp app = await start(tester);
      final Medicine m = await app.addBatch('ORS', qty: 8, mfg: day(3));
      await app.open(
          tester, AddEditMedicineScreen(existing: m, api: app.backend.api));

      await tester.enterText(fieldLabeled('Quantity *'), '9');
      await save(tester, 'Save changes');
      expect(find.text("Manufacture date can't be in the future."),
          findsOneWidget);
      expect(find.byType(AddEditMedicineScreen), findsOneWidget);
      expect(app.medicines.findById(m.id)!.quantity, 8, reason: 'not saved');
    });

    testWidgets('saving refuses an expiry on or before the manufacture date',
        (WidgetTester tester) async {
      final TestApp app = await start(tester);
      final Medicine m =
          await app.addBatch('ORS', expiresInDays: -5, mfg: day(-5));
      await app.open(
          tester, AddEditMedicineScreen(existing: m, api: app.backend.api));

      await save(tester, 'Save changes');
      expect(find.text('Expiry date must be after the manufacture date.'),
          findsOneWidget);
      expect(find.byType(AddEditMedicineScreen), findsOneWidget);
    });

    testWidgets('a cleared manufacture date is saved as cleared',
        (WidgetTester tester) async {
      final TestApp app = await start(tester);
      final Medicine m = await app.addBatch('ORS', mfg: day(-30));
      await app.open(
          tester, AddEditMedicineScreen(existing: m, api: app.backend.api));
      expect(find.text(Fmt.date(day(-30))), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(find.text('Not set'), findsOneWidget);
      await save(tester, 'Save changes');
      expect(find.byType(AddEditMedicineScreen), findsNothing);
      expect(app.medicines.findById(m.id)!.mfgDate, isNull);
    });
  });

  group('new batch of a medicine', () {
    testWidgets('keeps the product details and leaves the batch fields empty',
        (WidgetTester tester) async {
      final TestApp app = await start(tester);
      final Medicine dolo = await app.addBatch(
        'Dolo 650',
        brand: 'Micro Labs',
        category: 'Antipyretic (Fever)',
        unit: 'Strips',
        barcode: '8901234567890',
        lowStock: 5,
        mrp: 30,
        purchase: 18,
        batch: 'D1',
        qty: 15,
        mfg: day(-60),
        expiresInDays: 400,
      );
      await app.open(tester,
          AddEditMedicineScreen(newBatchOf: dolo, api: app.backend.api));
      expect(find.text('Add batch'), findsOneWidget);

      expect(fieldText(tester, 'Medicine name *'), 'Dolo 650');
      expect(fieldText(tester, 'Brand'), 'Micro Labs');
      expect(fieldText(tester, 'Barcode'), '8901234567890');
      expect(fieldText(tester, 'Low-stock at'), '5');
      expect(fieldText(tester, 'Purchase price'), '18.0');
      expect(fieldText(tester, 'Selling price (MRP)'), '30.0');
      expect(find.text('Strips'), findsOneWidget);
      expect(find.text('Antipyretic (Fever)'), findsOneWidget);

      expect(fieldText(tester, 'Batch / lot no.'), isEmpty);
      expect(fieldText(tester, 'Quantity *'), isEmpty);
      expect(find.text('Not set'), findsOneWidget, reason: 'no mfg date');
      expect(find.text(Fmt.date(dolo.expiryDate)), findsNothing,
          reason: "the old batch's expiry is not copied");

      await tester.enterText(fieldLabeled('Batch / lot no.'), 'D2');
      await tester.enterText(fieldLabeled('Quantity *'), '20');
      await save(tester, 'Add medicine');

      expect(find.byType(AddEditMedicineScreen), findsNothing);
      final ProductStock p = app.medicines.products.single;
      expect(p.batches.map((Medicine b) => b.batchNo), containsAll(<String>['D1', 'D2']));
      expect(p.totalQty, 35);
    });
  });

  group('edit medicine', () {
    testWidgets('shows the batch and saves changes to it',
        (WidgetTester tester) async {
      final TestApp app = await start(tester);
      final Medicine m = await app.addBatch('Dolo 650',
          batch: 'D1', qty: 15, mrp: 30, mfg: day(-30), expiresInDays: 300);
      await app.open(
          tester, AddEditMedicineScreen(existing: m, api: app.backend.api));

      expect(find.text('Edit Medicine'), findsOneWidget);
      expect(find.text('Delete medicine'), findsOneWidget);
      expect(fieldText(tester, 'Medicine name *'), 'Dolo 650');
      expect(fieldText(tester, 'Batch / lot no.'), 'D1');
      expect(fieldText(tester, 'Quantity *'), '15');
      expect(find.text(Fmt.date(day(-30))), findsOneWidget);
      expect(find.text(Fmt.date(day(300))), findsOneWidget);

      await tester.enterText(fieldLabeled('Quantity *'), '12');
      await tester.enterText(fieldLabeled('Selling price (MRP)'), '32.5');
      await save(tester, 'Save changes');

      expect(find.byType(AddEditMedicineScreen), findsNothing);
      final Medicine saved = app.medicines.findById(m.id)!;
      expect(saved.quantity, 12);
      expect(saved.sellingPrice, 32.5);
      expect(saved.batchNo, 'D1');
      expect(app.medicines.totalCount, 1, reason: 'edited, not added');
    });

    testWidgets('delete asks first and can be undone',
        (WidgetTester tester) async {
      final TestApp app = await start(tester);
      final Medicine m = await app.addBatch('Dolo 650', qty: 15);
      await app.open(
          tester, AddEditMedicineScreen(existing: m, api: app.backend.api));

      await save(tester, 'Delete medicine');
      expect(find.text('Delete medicine?'), findsOneWidget);
      await answer(tester, 'Delete');
      expect(find.byType(AddEditMedicineScreen), findsNothing);
      expect(app.medicines.productCount, 0);

      await save(tester, 'UNDO');
      expect(app.medicines.findById(m.id)!.quantity, 15);
    });
  });

  group('pack size', () {
    testWidgets('tablets per strip: stock as strips + loose, prices per strip',
        (WidgetTester tester) async {
      final TestApp app = await start(tester);
      await app.open(tester, AddEditMedicineScreen(api: app.backend.api));
      expect(find.text('Quantity *'), findsOneWidget);
      expect(find.text('Tablets per strip'), findsOneWidget,
          reason: 'the default unit counts pieces');

      await tester.enterText(fieldLabeled('Medicine name *'), 'Dolo 650');
      await tester.enterText(fieldLabeled('Tablets per strip'), '15');
      await tester.pump();
      expect(find.text('Quantity *'), findsNothing);
      expect(find.text('Stock is kept in tablets; 1 strip = 15 tablets'),
          findsOneWidget);

      // Neither strips nor loose: still required.
      await save(tester, 'Add medicine');
      expect(find.text('Required'), findsOneWidget);
      expect(app.medicines.productCount, 0);

      await tester.enterText(fieldLabeled('Strips *'), '2');
      await tester.enterText(fieldLabeled('Loose tablets'), '3');
      await tester.pump();
      expect(find.text('= 33 tablets in stock'), findsOneWidget);
      await tester.enterText(fieldLabeled('Purchase price per strip'), '15');
      await tester.enterText(fieldLabeled('MRP per strip'), '30');
      await save(tester, 'Add medicine');

      expect(find.byType(AddEditMedicineScreen), findsNothing);
      final ProductStock p = app.medicines.products.single;
      expect((p.unit, p.packSize, p.totalQty), ('Tablets', 15, 33));
      final Medicine b = p.batches.single;
      expect(b.sellingPrice, 30, reason: 'stored per strip (PackSize.pricePack)');
      expect(b.purchasePrice, 15);
    });

    testWidgets('editing shows the stock and prices as strips; a change is saved in tablets',
        (WidgetTester tester) async {
      final TestApp app = await start(tester);
      final Medicine m = await app.addBatch('Dolo 650',
          qty: 63, packSize: 10, mrp: 25, purchase: 18);
      await app.open(
          tester, AddEditMedicineScreen(existing: m, api: app.backend.api));

      expect(fieldText(tester, 'Tablets per strip'), '10');
      expect(fieldText(tester, 'Strips *'), '6');
      expect(fieldText(tester, 'Loose tablets'), '3');
      expect(fieldText(tester, 'MRP per strip'), '25.0', reason: 'as stored, per strip');
      expect(fieldText(tester, 'Purchase price per strip'), '18.0');
      expect(find.text('= 63 tablets in stock'), findsOneWidget);

      await tester.enterText(fieldLabeled('Strips *'), '5');
      await tester.enterText(fieldLabeled('Loose tablets'), '');
      await tester.pump();
      expect(find.text('= 50 tablets in stock'), findsOneWidget);
      await save(tester, 'Save changes');

      final Medicine saved = app.medicines.findById(m.id)!;
      expect((saved.quantity, saved.packSize), (50, 10));
      expect(saved.sellingPrice, 25, reason: 'unchanged, per strip');
      expect(saved.purchasePrice, 18);
    });

    testWidgets('clearing the pack size goes back to a plain quantity in tablets',
        (WidgetTester tester) async {
      final TestApp app = await start(tester);
      final Medicine m = await app.addBatch('Dolo 650',
          qty: 63, packSize: 10, mrp: 25, purchase: 18);
      await app.open(
          tester, AddEditMedicineScreen(existing: m, api: app.backend.api));

      await tester.enterText(fieldLabeled('Tablets per strip'), '');
      await tester.pump();
      expect(fieldText(tester, 'Quantity *'), '63');
      expect(fieldText(tester, 'Selling price (MRP)'), '2.50');
      expect(fieldText(tester, 'Purchase price'), '1.80');
      expect(find.text('Strips *'), findsNothing);

      // And back: the same numbers, as strips again.
      await tester.enterText(fieldLabeled('Tablets per strip'), '6');
      await tester.pump();
      expect(fieldText(tester, 'Strips *'), '10');
      expect(fieldText(tester, 'Loose tablets'), '3');
      expect(fieldText(tester, 'MRP per strip'), '15');
      expect(find.text('= 63 tablets in stock'), findsOneWidget);
    });

    testWidgets('a strip-counted medicine has no pack size field',
        (WidgetTester tester) async {
      final TestApp app = await start(tester);
      final Medicine m = await app.addBatch('Dolo 650', unit: 'Strips', qty: 7);
      await app.open(
          tester, AddEditMedicineScreen(existing: m, api: app.backend.api));
      expect(find.text('Tablets per strip'), findsNothing);
      expect(find.textContaining('per strip'), findsNothing);
      expect(fieldText(tester, 'Quantity *'), '7');
    });
  });

  group('barcode and catalog', () {
    testWidgets('a barcode the shop already has offers a new batch of it',
        (WidgetTester tester) async {
      final TestApp app = await start(tester);
      await app.addBatch('Dolo 650', barcode: '8901234567890');
      await app.open(tester, AddEditMedicineScreen(api: app.backend.api));

      await tester.enterText(fieldLabeled('Barcode'), '8901234567890');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Already in inventory'), findsOneWidget);
      await answer(tester, 'Add batch');

      expect(find.text('Add batch'), findsOneWidget, reason: 'header');
      expect(fieldText(tester, 'Medicine name *'), 'Dolo 650');
      expect(fieldText(tester, 'Quantity *'), isEmpty);
      expect(app.backend.requests, isEmpty, reason: 'found locally');
    });

    testWidgets('an unknown barcode is filled in from the master catalog',
        (WidgetTester tester) async {
      final TestApp app = await start(tester);
      await app.open(tester, AddEditMedicineScreen(api: app.backend.api));

      await tester.enterText(fieldLabeled('Barcode'), '8901000000011');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(fieldText(tester, 'Medicine name *'), 'Paracetamol 500mg');
      expect(fieldText(tester, 'Brand'), 'GSK');
      expect(fieldText(tester, 'Selling price (MRP)'), '22.50');
      expect(find.text('Strips'), findsOneWidget, reason: 'unit normalised');

      // Counted in strips, so the "15 tablets" pack is kept but not asked
      // about; save and the medicine remembers it.
      expect(find.text('Tablets per strip'), findsNothing);
      await tester.enterText(fieldLabeled('Quantity *'), '4');
      await save(tester, 'Add medicine');
      final ProductStock p = app.medicines.products.single;
      expect((p.unit, p.packSize, p.totalQty), ('Strips', 15, 4));
      expect(p.batches.single.sellingPrice, 22.5, reason: 'per strip');
    });

    testWidgets('a catalog medicine counted in tablets fills the pack size and keeps the pack price',
        (WidgetTester tester) async {
      usePhoneScreen(tester, height: 1400);
      final TestApp app = await TestApp.create(
        backend: FakeBackend(catalog: <Map<String, Object?>>[
          <String, Object?>{
            'name': 'Zincovit',
            'manufacturer': 'Apex',
            'pack_size': 'strip of 15 tablets',
            'unit': 'Tablets',
            'price': 105,
            'barcode': '8901000000022',
          },
        ]),
      );
      addTearDown(app.dispose);
      await app.open(tester, AddEditMedicineScreen(api: app.backend.api));
      await tester.enterText(fieldLabeled('Purchase price'), '5');
      await tester.enterText(fieldLabeled('Barcode'), '8901000000022');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(fieldText(tester, 'Tablets per strip'), '15');
      expect(fieldText(tester, 'MRP per strip'), '105.00',
          reason: 'the catalog price is for the strip');
      expect(fieldText(tester, 'Purchase price per strip'), '75',
          reason: 'what was typed per tablet, now per strip');
      await tester.enterText(fieldLabeled('Strips *'), '1');
      await save(tester, 'Add medicine');
      final ProductStock p = app.medicines.products.single;
      expect((p.unit, p.packSize, p.totalQty), ('Tablets', 15, 15));
      expect(p.batches.single.sellingPrice, 105, reason: 'the strip price');
      expect(p.batches.single.purchasePrice, 75);
    });

    testWidgets('typing a name suggests catalog medicines to fill in from',
        (WidgetTester tester) async {
      final TestApp app = await start(tester);
      await app.open(tester, AddEditMedicineScreen(api: app.backend.api));

      await tester.enterText(fieldLabeled('Medicine name *'), 'Pant');
      await tester.pump(const Duration(milliseconds: 300)); // debounce
      await tester.pumpAndSettle();
      expect(find.text('Alkem'), findsOneWidget);

      await tester.tap(find.text('Pantoprazole 40mg'));
      await tester.pumpAndSettle();
      expect(fieldText(tester, 'Medicine name *'), 'Pantoprazole 40mg');
      expect(fieldText(tester, 'Brand'), 'Alkem');
      expect(fieldText(tester, 'Selling price (MRP)'), '110.00');
    });
  });
}
