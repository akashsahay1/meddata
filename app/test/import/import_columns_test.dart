import 'package:flutter_test/flutter_test.dart';
import 'package:med_stock/services/import/import_columns.dart';
import 'package:med_stock/services/import/sheet_table.dart';

void main() {
  Map<ImportField, String> guess(List<List<Object?>> rows, {int header = 0}) {
    final SheetTable t = SheetTable('t', rows);
    final Map<ImportField, int> cols = ColumnGuesser.guessColumns(t, header);
    return <ImportField, String>{
      for (final MapEntry<ImportField, int> e in cols.entries)
        e.key: rows[header][e.value].toString(),
    };
  }

  test('Indian distributor / billing software headers', () {
    final Map<ImportField, String> m = guess(<List<Object?>>[
      <Object?>['Sr No', 'Item Name', 'Pack', 'Mfr', 'Batch', 'Exp', 'Qty',
        'Free', 'MRP', 'Rate', 'Amount', 'HSN'],
      <Object?>['1', 'Dolo 650', '15 TAB', 'MICRO', 'D1', '12/27', '10', '2',
        '30.00', '21.50', '215.00', '3004'],
    ]);
    expect(m, <ImportField, String>{
      ImportField.name: 'Item Name',
      ImportField.unit: 'Pack',
      ImportField.manufacturer: 'Mfr',
      ImportField.batchNo: 'Batch',
      ImportField.expiryDate: 'Exp',
      ImportField.quantity: 'Qty',
      ImportField.mrp: 'MRP',
      ImportField.purchaseRate: 'Rate',
    });
  });

  test('English headers with punctuation and spacing variants', () {
    final Map<ImportField, String> m = guess(<List<Object?>>[
      <Object?>['Medicine Name', 'Manufacturer', 'Category', 'Batch No.',
        'Bar Code', 'Quantity', 'Unit', 'Reorder Level', 'Purchase Price',
        'Selling Price', 'Mfg.Date', 'EXPIRY_DATE', 'Remarks'],
    ]);
    expect(m.length, ImportField.values.length);
    expect(m[ImportField.mfgDate], 'Mfg.Date');
    expect(m[ImportField.expiryDate], 'EXPIRY_DATE');
    expect(m[ImportField.lowStock], 'Reorder Level');
    expect(m[ImportField.barcode], 'Bar Code');
    expect(m[ImportField.notes], 'Remarks');
  });

  test("the app's own CSV export maps completely", () {
    final Map<ImportField, String> m = guess(<List<Object?>>[
      <Object?>['Name', 'Brand', 'Category', 'Batch', 'Barcode', 'Quantity',
        'Unit', 'Low Stock At', 'Purchase Price', 'Selling Price', 'Expiry'],
    ]);
    expect(m, <ImportField, String>{
      ImportField.name: 'Name',
      ImportField.manufacturer: 'Brand',
      ImportField.category: 'Category',
      ImportField.batchNo: 'Batch',
      ImportField.barcode: 'Barcode',
      ImportField.quantity: 'Quantity',
      ImportField.unit: 'Unit',
      ImportField.lowStock: 'Low Stock At',
      ImportField.purchaseRate: 'Purchase Price',
      ImportField.mrp: 'Selling Price',
      ImportField.expiryDate: 'Expiry',
    });
  });

  test('look-alike columns are not mistaken', () {
    final Map<ImportField, String> m = guess(<List<Object?>>[
      <Object?>['Item Code', 'Product', 'Company Name', 'Closing Stock',
        'Stock Value', 'Opening Stock', 'Sale Qty', 'M.R.P.', 'Exp. Dt.',
        'Min Qty', 'Generic Name'],
      <Object?>['A12', 'Crocin', 'GSK', '5', '150', '8', '3', '30', '1/28',
        '2', 'Paracetamol'],
    ]);
    expect(m[ImportField.name], 'Product');
    expect(m[ImportField.manufacturer], 'Company Name');
    expect(m[ImportField.quantity], 'Closing Stock');
    expect(m[ImportField.mrp], 'M.R.P.');
    expect(m[ImportField.expiryDate], 'Exp. Dt.');
    expect(m[ImportField.lowStock], 'Min Qty');
    expect(m[ImportField.notes], 'Generic Name');
    expect(m.values, isNot(contains('Item Code')));
    expect(m.values, isNot(contains('Stock Value')));
    expect(m.values, isNot(contains('Sale Qty')));
  });

  test('"Mfg" is the maker or the manufacture date, by its values', () {
    final Map<ImportField, String> maker = guess(<List<Object?>>[
      <Object?>['Item', 'Mfg', 'Qty', 'Expiry'],
      <Object?>['Dolo 650', 'Micro Labs', '10', '12/27'],
      <Object?>['Crocin', 'GSK', '4', '01/28'],
    ]);
    expect(maker[ImportField.manufacturer], 'Mfg');
    expect(maker.containsKey(ImportField.mfgDate), isFalse);

    final Map<ImportField, String> date = guess(<List<Object?>>[
      <Object?>['Item', 'Mfg', 'Qty', 'Expiry'],
      <Object?>['Dolo 650', '01/2025', '10', '12/27'],
      <Object?>['Crocin', '03/2025', '4', '01/28'],
    ]);
    expect(date[ImportField.mfgDate], 'Mfg');
    expect(date.containsKey(ImportField.manufacturer), isFalse);
  });

  test('a column is used for one field only', () {
    final SheetTable t = SheetTable('t', <List<Object?>>[
      <Object?>['Name', 'Item Name', 'Qty', 'Qty', 'Exp'],
    ]);
    final Map<ImportField, int> cols = ColumnGuesser.guessColumns(t, 0);
    expect(cols.values.toSet().length, cols.length);
    expect(cols[ImportField.name], 1, reason: '"Item Name" beats "Name"');
    expect(cols[ImportField.quantity], 2, reason: 'leftmost of equals');
  });

  group('header row', () {
    test('found below title rows', () {
      final SheetTable t = SheetTable('t', <List<Object?>>[
        <Object?>['Sharma Medical Agencies'],
        <Object?>['Stock statement as on 31/03/2026'],
        <Object?>[],
        <Object?>['Item Name', 'Batch', 'Exp', 'Qty', 'MRP'],
        <Object?>['Dolo 650', 'D1', '12/27', '10', '30'],
      ]);
      expect(ColumnGuesser.guessHeaderRow(t), 3);
    });

    test('a sheet that starts with data has none', () {
      final SheetTable t = SheetTable('t', <List<Object?>>[
        <Object?>['Dolo 650', 'D1', CellDate(DateTime(2027, 12)), 10, 30],
        <Object?>['Crocin', 'C1', CellDate(DateTime(2028, 1)), 4, 25],
      ]);
      expect(ColumnGuesser.guessHeaderRow(t), -1);
      expect(ColumnGuesser.guessColumns(t, -1), isEmpty);
    });

    test('unrecognised names: the first filled row', () {
      final SheetTable t = SheetTable('t', <List<Object?>>[
        <Object?>[],
        <Object?>['Col1', 'Col2'],
        <Object?>['x', 'y'],
      ]);
      expect(ColumnGuesser.guessHeaderRow(t), 1);
    });
  });

  test('column letters', () {
    expect(ColumnGuesser.columnLetter(0), 'A');
    expect(ColumnGuesser.columnLetter(25), 'Z');
    expect(ColumnGuesser.columnLetter(26), 'AA');
    expect(ColumnGuesser.columnLetter(27), 'AB');
    expect(ColumnGuesser.columnLetter(701), 'ZZ');
    expect(ColumnGuesser.columnLetter(702), 'AAA');
  });
}
