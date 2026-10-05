import 'package:flutter_test/flutter_test.dart';
import 'package:med_stock/services/import/import_values.dart';
import 'package:med_stock/services/import/sheet_table.dart';

void main() {
  group('dates', () {
    String? read(Object? v, {DateOrder order = DateOrder.dayFirst}) =>
        ImportValues.parseDate(v, order: order)?.toString();

    test('full dates in common formats', () {
      expect(read('31/12/2027'), '2027-12-31');
      expect(read('31-12-2027'), '2027-12-31');
      expect(read('31.12.27'), '2027-12-31');
      expect(read('5/1/2027'), '2027-01-05', reason: 'day first by default');
      expect(read('2027-12-31'), '2027-12-31');
      expect(read('2027/1/5'), '2027-01-05');
      expect(read('2027-12-31 00:00:00'), '2027-12-31');
      expect(read('2027-12-31T00:00:00.000'), '2027-12-31');
      expect(read('31/12/2027 10:30'), '2027-12-31');
      expect(read('31-Dec-2027'), '2027-12-31');
      expect(read('31 DEC 27'), '2027-12-31');
      expect(read('1st Jan 2028'), '2028-01-01');
      expect(read('Dec 31, 2027'), '2027-12-31');
      expect(read('20271231'), '2027-12-31');
      expect(read('31122027'), '2027-12-31');
    });

    test('month and year only (how expiry is printed)', () {
      expect(read('12/27'), '2027-12');
      expect(read('12/2027'), '2027-12');
      expect(read('1-28'), '2028-01');
      expect(read('Dec-27'), '2027-12');
      expect(read("DEC'27"), '2027-12');
      expect(read('Sept 2027'), '2027-09');
      expect(read('December 2027'), '2027-12');
      expect(read('2027-12'), '2027-12');
      expect(ImportValues.parseDate('12/27')!.hasDay, isFalse);
    });

    test('Excel serial numbers and date cells', () {
      expect(read(46752), '2027-12-31');
      expect(read(46752.75), '2027-12-31', reason: 'time of day dropped');
      expect(read('46752'), '2027-12-31');
      expect(read(CellDate(DateTime(2027, 6, 1), hasDay: false)), '2027-06');
      expect(read(DateTime(2027, 6, 15)), '2027-06-15');
      expect(read(120), isNull, reason: 'a quantity is not a date');
      expect(read(8901234567890), isNull);
    });

    test('month-first files and unambiguous swaps', () {
      expect(read('01/02/2027'), '2027-02-01');
      expect(read('01/02/2027', order: DateOrder.monthFirst), '2027-01-02');
      expect(read('12/31/2027'), '2027-12-31',
          reason: 'month 31 is impossible, so it must be month first');
      expect(read('31/12/2027', order: DateOrder.monthFirst), '2027-12-31');
    });

    test('bad dates are rejected', () {
      for (final String bad in <String>[
        'abc', '31/02/2027', '13/13/2027', '00/12/2027', '12/1999',
        '2027', 'Smarch 27', '1/2', '45/-', '',
      ]) {
        expect(read(bad), isNull, reason: bad);
      }
      expect(read(null), isNull);
      expect(read(true), isNull);
    });

    test('expiry of a month means the end of that month', () {
      expect(ImportValues.expiryOf(ImportValues.parseDate('02/28')!),
          DateTime(2028, 2, 29));
      expect(ImportValues.expiryOf(ImportValues.parseDate('Dec-27')!),
          DateTime(2027, 12, 31));
      expect(ImportValues.expiryOf(ImportValues.parseDate('15/12/2027')!),
          DateTime(2027, 12, 15));
    });

    test('date order is detected from the file', () {
      expect(ImportValues.detectDateOrder(<Object?>['01/02/2027', '25/12/2027']),
          DateOrder.dayFirst);
      expect(ImportValues.detectDateOrder(<Object?>['01/02/2027', '12/25/2027']),
          DateOrder.monthFirst);
      expect(
          ImportValues.detectDateOrder(
              <Object?>['12/25/2027', '25/12/2027']),
          DateOrder.dayFirst,
          reason: 'mixed evidence: keep the Indian default');
      expect(ImportValues.detectDateOrder(<Object?>['01/02/2027', 46752]),
          DateOrder.dayFirst);
    });
  });

  group('numbers', () {
    test('prices in Indian formats', () {
      expect(ImportValues.parseNumber('₹1,234.50'), 1234.5);
      expect(ImportValues.parseNumber('Rs. 45'), 45);
      expect(ImportValues.parseNumber('45/-'), 45);
      expect(ImportValues.parseNumber('1,00,000'), 100000);
      expect(ImportValues.parseNumber('12,50'), 12.5);
      expect(ImportValues.parseNumber(32.5), 32.5);
      expect(ImportValues.parseNumber('abc'), isNull);
      expect(ImportValues.parseNumber('NaN'), isNull);
      expect(ImportValues.parseNumber('1e3'), isNull);
      expect(ImportValues.parseMoney('-5'), isNull);
      expect(ImportValues.parseMoney('10.005'), 10.01);
      expect(ImportValues.parseWhole('10'), 10);
      expect(ImportValues.parseWhole('10.5'), isNull);
    });

    test('quantities', () {
      expect(ImportValues.parseQuantity('20').value, 20);
      expect(ImportValues.parseQuantity(20.0).value, 20);
      expect(ImportValues.parseQuantity('1,200').value, 1200);
      expect(ImportValues.parseQuantity('15 TAB').value, 15);
      expect(ImportValues.parseQuantity("10's").value, 10);
      final QuantityValue free = ImportValues.parseQuantity('10+2');
      expect(free.value, 12);
      expect(free.note, contains('counted as 12'));
      expect(ImportValues.parseQuantity('0').value, 0);

      expect(ImportValues.parseQuantity('').error, 'Quantity is missing');
      expect(ImportValues.parseQuantity(null).error, 'Quantity is missing');
      expect(ImportValues.parseQuantity('ten').error, contains('not a number'));
      expect(ImportValues.parseQuantity('-3').error, contains('negative'));
      expect(ImportValues.parseQuantity('2.5').error,
          contains('not a whole number'));
      expect(ImportValues.parseQuantity(CellDate(DateTime(2027))).error,
          contains('not a number'));
    });
  });

  group('units and categories', () {
    test('unit and pack texts map to the app units', () {
      final Map<String, String?> cases = <String, String?>{
        'Tablets': 'Tablets',
        'tab': 'Tablets',
        'CAP': 'Capsules',
        'strip': 'Strips',
        "10's": 'Strips',
        '1x10': 'Strips',
        '1*15 TAB': 'Strips',
        '10 TAB': 'Strips',
        'ml': 'ML',
        '100ML': 'Bottles',
        '60 ml syp': 'Bottles',
        'SYRUP': 'Bottles',
        '15 GM': 'Tubes',
        'OINT': 'Tubes',
        '200 gm': 'Boxes',
        'INJ': 'Injections',
        '2ML AMP': 'Injections',
        '1 VIAL': 'Injections',
        'SACHET': 'Sachets',
        'NOS': 'Pieces',
        'Pcs': 'Pieces',
        'box': 'Boxes',
        'xyz': null,
        '': null,
      };
      cases.forEach((String text, String? unit) {
        expect(ImportValues.unitFrom(text), unit, reason: text);
      });
    });

    test('categories match the presets when they can', () {
      expect(ImportValues.categoryFrom('antibiotics'), 'Antibiotic');
      expect(ImportValues.categoryFrom('ANALGESIC'), 'Pain Relief / Analgesic');
      expect(ImportValues.categoryFrom('fever'), 'Antipyretic (Fever)');
      expect(ImportValues.categoryFrom('Cough & Cold'), 'Cough & Cold');
      expect(ImportValues.categoryFrom('  Surgical  items '), 'Surgical items');
      expect(ImportValues.categoryFrom(''), 'Uncategorised');
    });
  });

  test('cell text as shown in the sheet', () {
    expect(ImportValues.text(8901234567890.0), '8901234567890');
    expect(ImportValues.text(12.5), '12.5');
    expect(ImportValues.text(CellDate(DateTime(2027, 12, 31))), '31/12/2027');
    expect(ImportValues.text(CellDate(DateTime(2027, 12), hasDay: false)),
        '12/2027');
    expect(ImportValues.text('  x '), 'x');
    expect(ImportValues.text(null), '');
  });
}
