import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:med_stock/domain/reports/expiry_loss.dart';
import 'package:med_stock/domain/reports/profit_report.dart';
import 'package:med_stock/domain/reports/stock_valuation.dart';
import 'package:med_stock/services/invoice_pdf.dart';
import 'package:med_stock/services/report_export.dart';

import '../support/reports_fixture.dart' show sampleProfit;
import 'stock_valuation_test.dart' show row, today;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late InvoiceFonts fonts;
  setUpAll(() async => fonts = await InvoiceFonts.load());

  final StockValuation valuation = StockValuation.build(<StockRow>[
    row('Dolo 650', qty: 10, mrp: 3000, cost: 2050),
    row('Mystery', qty: 1, mrp: 4000, cost: 0),
    row('Old Tonic', qty: 2, mrp: 5000, cost: 3000, expiresIn: -3),
  ], asOf: today);

  test('rupees for CSV cells', () {
    expect(ReportExport.rs(123456), '1234.56');
    expect(ReportExport.rs(5), '0.05');
    expect(ReportExport.rs(-49), '-0.49');
  });

  test('stock valuation CSV: summary, then a table per section', () {
    final List<List<dynamic>> rows =
        Csv().decode(ReportExport.csv(ReportExport.stockValuation(valuation)));
    expect(rows.first, <dynamic>['Stock valuation', 'As of 05 Oct 2026']);
    expect(rows[1], <dynamic>['Sellable stock at cost', '₹205.00']);
    final int header = rows.indexWhere((List<dynamic> r) =>
        r.isNotEmpty && r.first == 'Medicine');
    expect(rows[header], contains('Value at cost'));
    final List<dynamic> dolo =
        rows.firstWhere((List<dynamic> r) => r.isNotEmpty && r.first == 'Dolo 650');
    expect(dolo.sublist(4), <dynamic>['10', '20.50', '205.00', '30.00', '300.00']);
    // Unknown cost is blank, not 0.
    final List<dynamic> mystery =
        rows.firstWhere((List<dynamic> r) => r.isNotEmpty && r.first == 'Mystery');
    expect(mystery.sublist(5, 7), <dynamic>['', '']);
    expect(rows.any((List<dynamic> r) => r.isNotEmpty && r.first == 'Expired'), isTrue);
  });

  test('profit and expiry exports', () {
    final ReportDoc p = ReportExport.profit(ProfitReport.fromJson(sampleProfit()));
    expect(p.fileStem, 'profit_2026-10-01_2026-10-05');
    expect(p.summary.map(((String, String) s) => s.$1),
        contains('Sales without a purchase rate (not in profit)'));
    expect(p.tables.map((ReportTable t) => t.title),
        <String>['By day', 'By category', 'By product', 'Sold without a purchase rate']);
    expect(p.tables[2].rows.first,
        <Object?>['Cough Syrup', 3, '271.21', '210.00', '61.21', '22.57%', '']);

    final ExpiryLoss e = ExpiryLoss.build(
        stock: valuation.rows, writeOffs: const <WriteOff>[], today: today);
    final ReportDoc x = ReportExport.expiry(e);
    expect(x.tables.first.rows.single,
        <Object?>['Oct 2026', 2, '60.00', '100.00', '0.00', '60.00']);
  });

  test('PDF builds with the rupee font', () async {
    final Uint8List bytes = await ReportExport.pdf(
        ReportExport.stockValuation(valuation),
        fonts: fonts,
        compress: false);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });
}
