import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:med_stock/data/db/database_helper.dart';
import 'package:med_stock/data/models/medicine.dart';
import 'package:med_stock/data/repositories/medicine_repository.dart';
import 'package:med_stock/presentation/screens/import/import_wizard_screen.dart';
import 'package:med_stock/state/medicine_provider.dart';
import 'package:med_stock/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

/// Lets real async work (the reading isolate, the database) finish until
/// [finder] shows up.
Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
  for (int i = 0; i < 200 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  expect(finder, findsWidgets);
}

/// The wizard over a fresh database holding [stock], on a phone-width
/// screen tall enough to build every row of the check list.
Future<(MedicineRepository, MedicineProvider)> openWizard(
  WidgetTester tester,
  String csv, {
  List<Medicine> stock = const <Medicine>[],
  bool premium = true,
}) async {
  tester.view.physicalSize = const Size(1080, 6000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final String dir = (await tester.runAsync(databaseFactoryFfi.getDatabasesPath))!;
  final String path = '$dir/wizard_${const Uuid().v4()}.db';
  final DatabaseHelper helper = DatabaseHelper.at(databaseFactoryFfi, path);
  final MedicineRepository repo = MedicineRepository(helper);
  final MedicineProvider mp = MedicineProvider(repo)..isPremium = premium;
  await tester.runAsync(() async {
    for (final Medicine m in stock) {
      await repo.insert(m);
    }
    await mp.load();
  });
  addTearDown(() => tester.runAsync(() async {
        await helper.close();
        await databaseFactoryFfi.deleteDatabase(path);
      }));

  await tester.pumpWidget(ChangeNotifierProvider<MedicineProvider>.value(
    value: mp,
    child: MaterialApp(
      theme: AppTheme.light,
      home: ImportWizardScreen(
        pickFile: () async =>
            (name: 'stock.csv', bytes: Uint8List.fromList(utf8.encode(csv))),
      ),
    ),
  ));
  return (repo, mp);
}

/// The text of the value next to [label] on the result card.
String resultOf(WidgetTester tester, String label) => tester
    .widget<Text>(find
        .descendant(
            of: find.ancestor(of: find.text(label), matching: find.byType(Row)),
            matching: find.byType(Text))
        .last)
    .data!;

void main() {
  sqfliteFfiInit();

  testWidgets('a CSV goes from file to saved stock', (WidgetTester tester) async {
    final DateTime now = DateTime.now();
    final (MedicineRepository repo, MedicineProvider mp) = await openWizard(
      tester,
      'Sharma Medical Agencies - Stock Statement\n'
      'Item Name,Pack,Mfr,Batch,Exp,Qty,MRP,Rate\n'
      "Dolo 650,15's,Micro Labs,D1,12/27,20,33.60,24\n"
      "Dolo 650,15's,Micro Labs,D2,01/28,5,33.60,24\n"
      'Azithral 500,5 TAB,Alembic,A1,,3,119.50,85\n'
      'ORS,SACHET,,O1,06/27,12,21,15\n'
      'Crocin,TAB,GSK,C1,06/27,0,25,18\n',
      stock: <Medicine>[
        Medicine(
          id: const Uuid().v4(),
          name: 'Dolo 650',
          brand: 'Micro Labs',
          batchNo: 'D1',
          quantity: 4,
          unit: 'Strips',
          expiryDate: DateTime(2027, 12, 31),
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
    expect(find.text('Step 1 of 4 · Choose a file'), findsOneWidget);

    // 1. File → the header row is found below the title.
    await tester.tap(find.text('Choose file'));
    await pumpUntil(tester, find.text('Step 2 of 4 · Find the column names'));
    expect(find.textContaining('It looks like row 2.'), findsOneWidget);

    // 2. Columns are matched; nothing required is missing. Back works.
    await tester.tap(find.text('Match columns'));
    await tester.pumpAndSettle();
    expect(find.text('Step 3 of 4 · Match the columns'), findsOneWidget);
    expect(find.textContaining('Choose a column for'), findsNothing);
    expect(find.text('e.g. Dolo 650'), findsOneWidget);
    expect(find.text('e.g. 12/27'), findsOneWidget);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 4 · Find the column names'), findsOneWidget);
    await tester.tap(find.text('Match columns'));
    await tester.pumpAndSettle();

    // 3. Check: the batch already in stock, the row without an expiry and
    //    the zero quantity are skipped, with reasons.
    await tester.tap(find.text('Check rows'));
    await pumpUntil(tester, find.text('Step 4 of 4 · Check the rows'));
    expect(find.text('All · 5'), findsOneWidget);
    expect(find.text('To import · 2'), findsOneWidget);
    expect(find.text('Skipped · 3'), findsOneWidget);
    expect(find.text('Already in stock (same medicine and batch)'), findsOneWidget);
    expect(find.text('Expiry date is missing'), findsOneWidget);
    expect(find.text('Quantity is 0'), findsOneWidget);
    expect(find.text('New batch of Dolo 650 (already in stock)'), findsOneWidget);

    await tester.tap(find.text('Skipped · 3'));
    await tester.pump();
    expect(find.text('ORS'), findsNothing);
    await tester.tap(find.text('All · 5'));
    await tester.pump();

    // Zero quantities can be let through, and skipped again.
    expect(find.text('Skip rows with quantity 0 (1)'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await pumpUntil(tester, find.text('To import · 3'));
    await tester.tap(find.byType(Switch));
    await pumpUntil(tester, find.text('To import · 2'));

    // Add the duplicate's quantity instead of skipping it.
    await tester.tap(find.text('Add quantity'));
    await pumpUntil(tester, find.text('To import · 3'));
    expect(find.text('Adds 20 to the batch already in stock'), findsOneWidget);

    // 4. Import.
    await tester.tap(find.text('Import 3 rows'));
    await pumpUntil(tester, find.text('Import complete'));
    expect(resultOf(tester, 'Medicines added'), '1');
    expect(resultOf(tester, 'Batches added'), '2', reason: 'ORS O1 and Dolo D2');
    expect(resultOf(tester, 'Batches with stock added'), '1');
    expect(resultOf(tester, 'Units added'), '37');
    expect(resultOf(tester, 'Rows skipped'), '2');

    final List<Medicine> all = (await tester.runAsync(repo.getAll))!;
    expect(all.map((Medicine m) => '${m.name} ${m.batchNo} ${m.quantity} ${m.unit}'),
        <String>['Dolo 650 D1 24 Strips', 'Dolo 650 D2 5 Strips', 'ORS O1 12 Sachets']);
    expect(mp.productCount, 2, reason: 'the provider reloaded');
  });

  testWidgets('the free plan limit is explained before importing',
      (WidgetTester tester) async {
    final (MedicineRepository _, MedicineProvider mp) = await openWizard(
      tester,
      'Item Name,Qty,Exp\n'
      '${<String>[for (int i = 1; i <= 9; i++) 'Medicine $i,5,12/27'].join('\n')}\n',
      premium: false,
    );
    await tester.tap(find.text('Choose file'));
    await pumpUntil(tester, find.text('Match columns'));
    await tester.tap(find.text('Match columns'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check rows'));
    await pumpUntil(tester, find.text('Step 4 of 4 · Check the rows'));

    expect(find.text('Free plan: only 7 more medicines fit, so 2 rows are skipped.'),
        findsOneWidget);
    expect(find.text('Free plan limit reached: no room for more medicines'),
        findsNWidgets(2));

    await tester.tap(find.text('Import 7 rows'));
    await tester.pumpAndSettle();
    expect(find.text('Free plan limit'), findsOneWidget);
    expect(find.textContaining('This file has 9 new medicines, so only 7 can be '
        'added and 2 rows will be skipped.'), findsOneWidget);
    await tester.tap(find.text('Import 7'));
    await pumpUntil(tester, find.text('Import complete'));
    expect(mp.productCount, 7);
    expect(mp.canAdd(), isFalse);
  });

  testWidgets('a file that is not a spreadsheet says why', (WidgetTester tester) async {
    await tester.pumpWidget(ChangeNotifierProvider<MedicineProvider>.value(
      value: MedicineProvider(),
      child: MaterialApp(
        theme: AppTheme.light,
        home: ImportWizardScreen(
          pickFile: () async => (
            name: 'stock.xls',
            bytes: Uint8List.fromList(
                <int>[0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, 0, 0]),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Choose file'));
    await pumpUntil(tester, find.textContaining('old Excel file (.xls)'));
    expect(find.text('Step 1 of 4 · Choose a file'), findsOneWidget);
  });
}
