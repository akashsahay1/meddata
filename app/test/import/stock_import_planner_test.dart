import 'package:flutter_test/flutter_test.dart';
import 'package:med_stock/data/models/medicine.dart';
import 'package:med_stock/data/models/stock_import.dart';
import 'package:med_stock/services/import/import_columns.dart';
import 'package:med_stock/services/import/import_values.dart';
import 'package:med_stock/services/import/sheet_table.dart';
import 'package:med_stock/services/import/spreadsheet_reader.dart';
import 'package:med_stock/services/import/stock_import_planner.dart';

final DateTime today = DateTime(2026, 10, 5);

const List<Object?> header = <Object?>[
  'Item Name', 'Mfr', 'Batch', 'Qty', 'Pack', 'Exp', 'MRP', 'Rate',
  'Mfg Date', 'Barcode', 'Remarks',
];

/// A data row in [header]'s column order.
List<Object?> row(String name,
        {String mfr = '',
        String batch = '',
        Object? qty = '10',
        String pack = '',
        Object? exp = '12/27',
        Object? mrp = '',
        Object? rate = '',
        Object? mfg = '',
        Object? barcode = '',
        String notes = ''}) =>
    <Object?>[name, mfr, batch, qty, pack, exp, mrp, rate, mfg, barcode, notes];

ImportPlan plan(
  List<List<Object?>> rows, {
  List<Medicine> inventory = const <Medicine>[],
  DuplicatePolicy duplicates = DuplicatePolicy.skip,
  bool skipZero = true,
  int? room,
  DateOrder order = DateOrder.dayFirst,
}) {
  final SheetTable t = SheetTable('t', <List<Object?>>[header, ...rows]);
  return StockImportPlanner.plan(
    t,
    ImportSettings(
      headerRow: 0,
      columns: ColumnGuesser.guessColumns(t, 0),
      duplicates: duplicates,
      skipZeroQuantity: skipZero,
      newMedicineRoom: room,
      dateOrder: order,
    ),
    inventory: inventory,
    now: today,
  );
}

Medicine inStock(String productId, String name, String batch,
    {String brand = 'Micro Labs',
    String unit = 'Tablets',
    DateTime? expiry,
    String? id}) {
  final DateTime now = DateTime(2026);
  return Medicine(
    id: id ?? 'batch-$productId-$batch',
    productId: productId,
    name: name,
    brand: brand,
    batchNo: batch,
    quantity: 5,
    unit: unit,
    expiryDate: expiry ?? DateTime(2027, 1, 31),
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  test('a valid row becomes a new medicine with every value read', () {
    final ImportPlan p = plan(<List<Object?>>[
      row('  Dolo   650 ', mfr: 'Micro Labs', batch: 'D1', qty: '20',
          pack: "15's", exp: 'Dec-27', mrp: '₹33.60', rate: '24',
          mfg: '15/12/2025', barcode: 8901234567890.0, notes: 'Keep dry'),
    ]);
    expect(p.rows.single.action, RowAction.newMedicine);
    expect(p.rows.single.rowNumber, 2);
    expect(p.rows.single.warnings, isEmpty);
    final StockImportRow s = p.toSave.single;
    expect(s.productId, isNull);
    expect(s.addToBatchId, isNull);
    final Medicine m = s.medicine;
    expect(<Object?>[m.name, m.brand, m.batchNo, m.quantity, m.unit,
      m.sellingPrice, m.purchasePrice, m.barcode, m.notes, m.category],
        <Object?>['Dolo 650', 'Micro Labs', 'D1', 20, 'Strips', 33.6, 24.0,
          '8901234567890', 'Keep dry', 'Uncategorised']);
    expect(m.expiryDate, DateTime(2027, 12, 31), reason: 'end of the month');
    expect(m.mfgDate, DateTime(2025, 12, 15));
    expect(m.lowStockThreshold, 10);
  });

  test('what skips a row, and what only warns', () {
    final ImportPlan p = plan(<List<Object?>>[
      row('', qty: '5'), // 2
      row('A', qty: 'abc'), // 3
      row('B', qty: '-2'), // 4
      row('C', exp: ''), // 5
      row('D', exp: '31/02/2027'), // 6
      row('E', batch: 'X' * 65), // 7
      row('Grand Total', qty: '40', exp: ''), // 8
      <Object?>[], // 9: blank, ignored
      header, // 10: header repeated on a new page, ignored
      row('F', mrp: 'abc', rate: '-4'), // 11
      row('G', mfg: '05/10/2026', exp: '05/10/2026'), // 12: mfg = expiry
      row('H', mfg: '01/2027', exp: '12/28'), // 13: mfg in the future
      row('I', pack: 'xyz'), // 14
      row('J', exp: '01/2026'), // 15: expired
      row('K', barcode: '8.90123E+12'), // 16
      row('L', qty: '10+2'), // 17
      row('M', mfg: 'soon'), // 18
    ]);
    Map<String, Object?> at(int rowNumber) {
      final ImportRow r =
          p.rows.firstWhere((ImportRow r) => r.rowNumber == rowNumber);
      return <String, Object?>{
        'action': r.action,
        'errors': r.errors,
        'warnings': r.warnings,
      };
    }

    expect(p.rows.map((ImportRow r) => r.rowNumber),
        isNot(contains(anyOf(9, 10))));
    expect(at(2)['errors'], <String>['Medicine name is missing']);
    expect(at(3)['errors'], <String>['Quantity "abc" is not a number']);
    expect(at(4)['errors'], <String>['Quantity "-2" is negative']);
    expect(at(5)['errors'], <String>['Expiry date is missing']);
    expect((at(6)['errors']! as List<String>).single, contains('not understood'));
    expect(at(7)['errors'], <String>['Batch no. is longer than 64 characters']);
    expect(at(8)['errors'], <String>['Looks like a total row']);
    for (final int n in <int>[2, 3, 4, 5, 6, 7, 8]) {
      expect(at(n)['action'], RowAction.skip, reason: 'row $n');
    }

    expect(at(11)['action'], RowAction.newMedicine);
    expect(at(11)['warnings'], <String>[
      'Purchase rate "-4" is not a price; left blank',
      'MRP "abc" is not a price; left blank',
    ]);
    expect(at(12)['warnings'],
        <String>['Mfg date is not before the expiry date; left blank']);
    expect(at(13)['warnings'], <String>['Mfg date is in the future; left blank']);
    expect(at(14)['warnings'], <String>['Unit "xyz" not recognised']);
    expect(at(15)['warnings'], <String>['Already expired']);
    expect((at(16)['warnings']! as List<String>).single, contains('rounded by Excel'));
    expect((at(17)['warnings']! as List<String>).single, contains('counted as 12'));
    expect((at(18)['warnings']! as List<String>).single,
        'Mfg date "soon" not understood; left blank');

    Medicine saved(String name) => p.toSave
        .firstWhere((StockImportRow s) => s.medicine.name == name)
        .medicine;
    expect(saved('F').sellingPrice, 0);
    expect(saved('G').mfgDate, isNull);
    expect(saved('I').unit, 'Tablets', reason: 'the default unit');
    expect(saved('K').barcode, '');
    expect(saved('L').quantity, 12);
    expect(p.skipped, 7);
    expect(p.importable, 8);
    expect(p.withWarnings, 8);
  });

  test('rows with quantity 0 are skipped unless asked for', () {
    final List<List<Object?>> rows = <List<Object?>>[
      row('A', qty: '0'),
      row('B', qty: '3'),
    ];
    final ImportPlan skipped = plan(rows);
    expect(skipped.zeroQuantity, 1);
    expect(skipped.rows.first.errors, <String>['Quantity is 0']);
    expect(skipped.toSave, hasLength(1));
    final ImportPlan kept = plan(rows, skipZero: false);
    expect(kept.toSave.map((StockImportRow s) => s.medicine.quantity),
        <int>[0, 3]);
  });

  group('medicines and batches already in stock', () {
    final List<Medicine> inventory = <Medicine>[
      inStock('p-dolo', 'Dolo 650', 'D1'),
      inStock('p-dolo', 'Dolo 650', 'D2'),
      inStock('p-ors', 'ORS', '', unit: 'Sachets', brand: '',
          expiry: DateTime(2027, 6, 30), id: 'b-ors'),
    ];

    test('a new batch joins the medicine; the same batch is a duplicate', () {
      final ImportPlan p = plan(<List<Object?>>[
        row('DOLO  650', mfr: 'micro labs', batch: 'D3', qty: '10'),
        row('Dolo 650', batch: 'd1', qty: '5'),
        row('Dolo 650', mfr: 'Cipla', batch: 'C1'),
        row('Dolo 650', mfr: 'Micro Labs', batch: 'X9', pack: 'strip'),
        row('ORS', exp: '30/06/2027', qty: '4'),
        row('ORS', exp: '31/07/2027', qty: '4'),
      ], inventory: inventory);
      expect(p.rows.map((ImportRow r) => r.action), <RowAction>[
        RowAction.newBatch,
        RowAction.skip,
        RowAction.newMedicine,
        RowAction.newMedicine,
        RowAction.skip,
        RowAction.newBatch,
      ]);
      expect(p.rows[0].detail, 'New batch of Dolo 650 (already in stock)');
      expect(p.rows[1].errors, <String>['Already in stock (same medicine and batch)']);
      expect(p.rows[3].warnings.single,
          contains('already listed in Tablets; this row is added as a '
              'separate medicine in Strips'));
      expect(p.rows[4].errors, <String>['Already in stock (same medicine and batch)'],
          reason: 'no batch number: same expiry, same batch');
      expect(p.duplicates, 2);

      final List<StockImportRow> s = p.toSave;
      expect(s.map((StockImportRow r) => r.productId),
          <String?>['p-dolo', null, null, 'p-ors']);
      expect(s[0].medicine.unit, 'Tablets', reason: "the product's unit");
      expect(s[1].medicine.brand, 'Cipla');
      expect(s[3].medicine.unit, 'Sachets');
    });

    test("a maker's spelling doesn't matter; another maker is separate", () {
      final ImportPlan p = plan(<List<Object?>>[
        row('Dolo 650', mfr: 'MICRO LABS LTD.', batch: 'M1'),
        row('Dolo 650', mfr: 'Micro', batch: 'M2'),
        row('Dolo 650', mfr: 'Cipla', batch: 'C1'),
        row('Dolo 650', mfr: 'Cipla Pharma', batch: 'C2'),
      ], inventory: inventory);
      expect(p.rows.map((ImportRow r) => r.action), <RowAction>[
        RowAction.newBatch,
        RowAction.newBatch,
        RowAction.newMedicine,
        RowAction.newBatch,
      ]);
      expect(p.toSave.map((StockImportRow s) => s.productId),
          <String?>['p-dolo', 'p-dolo', null, null]);
      expect(p.rows[2].warnings, <String>[
        'Dolo 650 by Micro Labs is already listed; this one by Cipla is '
            'added as a separate medicine',
      ]);
      expect(p.rows[3].detail, 'New batch of the medicine on row 4');
    });

    test('or its quantity is added to the batch in stock', () {
      final ImportPlan p = plan(<List<Object?>>[
        row('Dolo 650', batch: 'D1', qty: '5'),
        row('ORS', exp: 'Jun-27', qty: '2'),
      ], inventory: inventory, duplicates: DuplicatePolicy.addQuantity);
      expect(p.rows.map((ImportRow r) => r.action),
          <RowAction>[RowAction.addStock, RowAction.addStock]);
      expect(p.rows.first.detail, 'Adds 5 to the batch already in stock');
      expect(p.toSave.map((StockImportRow r) => r.addToBatchId),
          <String?>['batch-p-dolo-D1', 'b-ors']);
      expect(p.toSave.first.medicine.quantity, 5);
      expect(p.addStock, 2);
    });
  });

  test('the same batch twice in the file: skipped, or quantities merged', () {
    final List<List<Object?>> rows = <List<Object?>>[
      row('Crocin', batch: 'C1', qty: '5', mfr: 'GSK'),
      row('crocin', batch: 'c1', qty: '3'),
      row('Crocin', batch: 'C2', qty: '1', barcode: '890111'),
    ];
    final ImportPlan skip = plan(rows);
    expect(skip.rows[1].errors, <String>['Same medicine and batch as row 2']);
    expect(skip.toSave.map((StockImportRow s) => s.medicine.quantity), <int>[5, 1]);

    final ImportPlan merge = plan(rows, duplicates: DuplicatePolicy.addQuantity);
    expect(merge.rows[1].action, RowAction.addStock);
    expect(merge.rows[1].detail, 'Quantity added to row 2');
    expect(merge.rows[2].detail, 'New batch of the medicine on row 2');
    expect(merge.toSave.map((StockImportRow s) => s.medicine.quantity), <int>[8, 1]);
    // Both batches belong to one new medicine, which takes the first
    // barcode the file gives it.
    expect(merge.toSave.map((StockImportRow s) => s.productKey).toSet(), hasLength(1));
    expect(merge.toSave.map((StockImportRow s) => s.medicine.barcode).toSet(),
        <String>{'890111'});
    expect(merge.newMedicines, 1);
    expect(merge.newBatches, 1);
  });

  test('the free plan limit stops new medicines, not new batches', () {
    final ImportPlan p = plan(<List<Object?>>[
      row('Crocin', batch: 'C1'),
      row('Dolo 650', batch: 'D9'),
      row('Azithral', batch: 'A1'),
      row('Azithral', batch: 'A2'),
      row('Crocin', batch: 'C2'),
    ], inventory: <Medicine>[inStock('p-dolo', 'Dolo 650', 'D1')], room: 1);
    expect(p.rows.map((ImportRow r) => r.action), <RowAction>[
      RowAction.newMedicine,
      RowAction.newBatch,
      RowAction.skip,
      RowAction.skip,
      RowAction.newBatch,
    ]);
    expect(p.rows[2].errors.single, contains('Free plan limit'));
    expect(p.newMedicines, 1);
    expect(p.overLimit, 2);
    expect(p.newMedicinesInFile, 2);
    expect(p.toSave, hasLength(3));
  });

  test('the date order setting reads 01/02/2027 either way', () {
    expect(plan(<List<Object?>>[row('A', exp: '01/02/2027')])
        .toSave.single.medicine.expiryDate, DateTime(2027, 2, 1));
    expect(plan(<List<Object?>>[row('A', exp: '01/02/2027')],
            order: DateOrder.monthFirst)
        .toSave.single.medicine.expiryDate, DateTime(2027, 1, 2));
  });

  test("the app's own CSV export imports back", () {
    final SheetTable t = SheetTable('export', SpreadsheetReader.parseCsv(
        'Name,Brand,Category,Batch,Barcode,Quantity,Unit,Low Stock At,'
        'Purchase Price,Selling Price,Expiry\r\n'
        'Dolo 650,Micro Labs,Antipyretic (Fever),D1,0890123,15,Strips,5,'
        '18.0,30.0,2027-01-31\r\n'));
    final int headerRow = ColumnGuesser.guessHeaderRow(t);
    final ImportPlan p = StockImportPlanner.plan(
        t,
        ImportSettings(
            headerRow: headerRow,
            columns: ColumnGuesser.guessColumns(t, headerRow)),
        now: today);
    final Medicine m = p.toSave.single.medicine;
    expect(<Object?>[m.name, m.brand, m.category, m.batchNo, m.barcode,
      m.quantity, m.unit, m.lowStockThreshold, m.purchasePrice,
      m.sellingPrice, m.expiryDate],
        <Object?>['Dolo 650', 'Micro Labs', 'Antipyretic (Fever)', 'D1',
          '0890123', 15, 'Strips', 5, 18.0, 30.0, DateTime(2027, 1, 31)]);
  });

  test('a very long file is cut at the row limit', () {
    final List<List<Object?>> rows = <List<Object?>>[
      for (int i = 0; i <= StockImportPlanner.maxRows; i++)
        row('Medicine ${i % 3000}', batch: 'B$i', qty: '${i % 50 + 1}'),
    ];
    final Stopwatch w = Stopwatch()..start();
    final ImportPlan p = plan(rows);
    w.stop();
    expect(p.truncated, isTrue);
    expect(p.rows, hasLength(StockImportPlanner.maxRows));
    expect(p.newMedicines, 3000);
    expect(p.newBatches, StockImportPlanner.maxRows - 3000);
    expect(w.elapsedMilliseconds, lessThan(5000));
  });
}
