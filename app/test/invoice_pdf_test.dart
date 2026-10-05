import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:med_stock/data/models/bill.dart';
import 'package:med_stock/services/invoice_pdf.dart';
import 'package:pdf/pdf.dart';

import 'billing_api_test.dart' show sampleBill;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InvoiceFonts fonts;
  setUpAll(() async => fonts = await InvoiceFonts.load());

  String text(Uint8List pdf) => latin1.decode(pdf);

  test('the embedded invoice fonts have the rupee sign', () async {
    for (final String f in <String>['Regular', 'Bold']) {
      final ByteData data =
          await rootBundle.load('assets/fonts/pdf/GoogleSansFlex-$f.ttf');
      expect(TtfParser(data).charToGlyphIndexMap.containsKey(0x20B9), isTrue, reason: f);
    }
  });

  test('A4 tax invoice and 80 mm receipt render, with ₹ from the embedded font', () async {
    final Bill bill = Bill.fromJson(sampleBill());
    for (final InvoiceLayout layout in InvoiceLayout.values) {
      final Uint8List pdf =
          await InvoicePdf.build(bill, layout: layout, fonts: fonts, compress: false);
      final String raw = text(pdf);
      expect(raw.startsWith('%PDF'), isTrue);
      expect(raw, contains('GoogleSansFlex'), reason: '$layout embeds the app font');
      // The font's ToUnicode map lists every character used, ₹ included.
      expect(raw, contains('<20B9>'), reason: '$layout prints the rupee sign');
    }
    expect(InvoicePdf.fileName(bill, InvoiceLayout.a4), 'Invoice-MED-26-27-000042.pdf');
    expect(InvoicePdf.fileName(bill, InvoiceLayout.receipt80), 'Invoice-MED-26-27-000042-80mm.pdf');
  });

  test('a receipt is as long as the bill; a long A4 invoice runs over pages', () async {
    final Map<String, dynamic> long = sampleBill();
    final Map<String, dynamic> item = Map<String, dynamic>.from((long['items'] as List<dynamic>).first as Map);
    long['items'] = <Map<String, dynamic>>[
      for (int i = 1; i <= 70; i++) <String, dynamic>{...item, 'line_no': i, 'name': 'Medicine $i'},
    ];
    final Bill bill = Bill.fromJson(long);

    final String a4 = text(await InvoicePdf.build(bill, fonts: fonts, compress: false));
    expect(RegExp(r'/Type\s*/Page\b').allMatches(a4).length, greaterThan(1));

    final String receipt = text(await InvoicePdf.build(bill,
        layout: InvoiceLayout.receipt80, fonts: fonts, compress: false));
    final RegExpMatch box = RegExp(r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)').firstMatch(receipt)!;
    expect(double.parse(box.group(1)!), closeTo(80 * PdfPageFormat.mm, 0.5));
    expect(double.parse(box.group(2)!), greaterThan(1000), reason: 'one long roll, not pages');

    // Printing gets that finite size (print dialogs can't take a roll).
    final (_, PdfPageFormat format) =
        await InvoicePdf.buildForPrint(bill, layout: InvoiceLayout.receipt80, fonts: fonts);
    expect(format.width, closeTo(80 * PdfPageFormat.mm, 0.5));
    expect(format.height, closeTo(double.parse(box.group(2)!), 0.5));
    final (_, PdfPageFormat a4Format) =
        await InvoicePdf.buildForPrint(bill, layout: InvoiceLayout.a4, fonts: fonts);
    expect(a4Format.height, PdfPageFormat.a4.height);
  });

  test('cancelled bills and shops without a GSTIN still print', () async {
    final Map<String, dynamic> raw = sampleBill(status: 'cancelled')
      ..['cancel_reason'] = 'Wrong medicine'
      ..['seller'] = <String, dynamic>{'name': 'Corner Chemist'};
    final Bill bill = Bill.fromJson(raw);
    expect(bill.seller.gstin, isNull);
    for (final InvoiceLayout layout in InvoiceLayout.values) {
      final Uint8List pdf = await InvoicePdf.build(bill, layout: layout, fonts: fonts);
      expect(pdf.length, greaterThan(1000));
    }
  });
}
