import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/inr.dart';
import '../data/models/bill.dart';
import '../domain/gst.dart';

enum InvoiceLayout {
  a4('A4 invoice'),
  receipt80('80 mm receipt');

  const InvoiceLayout(this.label);
  final String label;
}

/// Fonts for invoices. PDF's built-in fonts have no ₹, so the app's own
/// font is embedded: static Regular/Bold subsets of GoogleSansFlex (only
/// the glyphs used end up in each PDF).
class InvoiceFonts {
  const InvoiceFonts(this.regular, this.bold);

  final pw.Font regular;
  final pw.Font bold;

  static InvoiceFonts? _cached;

  static Future<InvoiceFonts> load() async => _cached ??= InvoiceFonts(
        pw.Font.ttf(await rootBundle.load('assets/fonts/pdf/GoogleSansFlex-Regular.ttf')),
        pw.Font.ttf(await rootBundle.load('assets/fonts/pdf/GoogleSansFlex-Bold.ttf')),
      );
}

/// GST invoice PDFs from a server bill: an A4 tax invoice and an 80 mm
/// thermal receipt. A shop without a GSTIN can't charge GST, so its bills
/// print as a plain invoice without the tax breakup.
class InvoicePdf {
  InvoicePdf._();

  static const PdfColor _ink = PdfColor.fromInt(0xFF0A302E);
  static const PdfColor _muted = PdfColor.fromInt(0xFF66807D);
  static const PdfColor _line = PdfColor.fromInt(0xFFB4C4C1);
  static const PdfColor _band = PdfColor.fromInt(0xFFEEF2F1);

  static final PdfPageFormat _receiptFormat = PdfPageFormat.roll80.copyWith(
    marginLeft: 3 * PdfPageFormat.mm,
    marginRight: 3 * PdfPageFormat.mm,
    marginTop: 4 * PdfPageFormat.mm,
    marginBottom: 8 * PdfPageFormat.mm,
  );

  /// e.g. "Invoice-MED-26-27-000042.pdf".
  static String fileName(Bill bill, InvoiceLayout layout) =>
      'Invoice-${bill.invoiceNo.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '-')}'
      '${layout == InvoiceLayout.receipt80 ? '-80mm' : ''}.pdf';

  /// [compress] false keeps the PDF's streams readable (tests).
  static Future<Uint8List> build(Bill bill,
      {InvoiceLayout layout = InvoiceLayout.a4,
      required InvoiceFonts fonts,
      bool compress = true}) {
    return _document(bill, layout, fonts, compress: compress).save();
  }

  /// The PDF plus the size of its first page. A receipt is as tall as its
  /// content, and print dialogs need that finite size rather than the roll.
  static Future<(Uint8List, PdfPageFormat)> buildForPrint(Bill bill,
      {required InvoiceLayout layout, required InvoiceFonts fonts}) async {
    final pw.Document doc = _document(bill, layout, fonts);
    final Uint8List bytes = await doc.save();
    return (bytes, doc.document.pdfPageList.pages.first.pageFormat);
  }

  static pw.Document _document(Bill bill, InvoiceLayout layout, InvoiceFonts fonts,
      {bool compress = true}) {
    final pw.Document doc = pw.Document(
      compress: compress,
      title: 'Invoice ${bill.invoiceNo}',
      author: bill.seller.displayName,
      creator: 'Meddata',
    );
    final pw.ThemeData theme =
        pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold);
    if (layout == InvoiceLayout.a4) {
      _a4(doc, bill, theme);
    } else {
      _receipt(doc, bill, theme);
    }
    return doc;
  }

  static bool _registered(Bill bill) => bill.seller.gstin != null;

  static String _title(Bill bill) => _registered(bill) ? 'TAX INVOICE' : 'INVOICE';

  static String _when(Bill bill) {
    final DateTime? at = bill.createdAt;
    return at == null
        ? DateFormat('dd MMM yyyy').format(bill.billDate)
        : DateFormat('dd MMM yyyy, hh:mm a').format(at);
  }

  static String _exp(DateTime? d) => d == null ? '-' : DateFormat('MM/yy').format(d);

  static String _amt(int paise) => Inr.format(paise, symbol: false);

  // ---- A4 ---------------------------------------------------------------------

  static void _a4(pw.Document doc, Bill bill, pw.ThemeData theme) {
    const pw.TextStyle small = pw.TextStyle(fontSize: 8, color: _muted);
    doc.addPage(pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4.copyWith(
            marginLeft: 28, marginRight: 28, marginTop: 28, marginBottom: 28),
        theme: theme.copyWith(
            defaultTextStyle: theme.defaultTextStyle.copyWith(fontSize: 9, color: _ink)),
        buildForeground: bill.isCancelled ? (_) => _cancelledStamp(72) : null,
      ),
      header: (pw.Context ctx) => ctx.pageNumber == 1
          ? pw.SizedBox()
          : pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Text('${bill.invoiceNo} (continued)', style: small)),
      footer: (pw.Context ctx) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 8),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: <pw.Widget>[
            pw.Text('This is a computer-generated invoice.', style: small),
            pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: small),
          ],
        ),
      ),
      build: (pw.Context ctx) => <pw.Widget>[
        _a4Header(bill),
        pw.SizedBox(height: 10),
        _a4Parties(bill),
        pw.SizedBox(height: 10),
        _a4Items(bill),
        pw.SizedBox(height: 10),
        _a4Summary(bill),
        pw.SizedBox(height: 8),
        pw.Text('Amount in words: ${Inr.words(bill.totalPaise)}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        if (bill.isCancelled)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 6),
            child: pw.Text(
                'This bill was cancelled${bill.cancelReason == null ? '' : ': ${bill.cancelReason}'}.',
                style: pw.TextStyle(color: PdfColors.red, fontWeight: pw.FontWeight.bold)),
          ),
        pw.SizedBox(height: 28),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: <pw.Widget>[
            pw.Text('Thank you. Get well soon!', style: small),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: <pw.Widget>[
                pw.Text('For ${bill.seller.displayName}',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 28),
                pw.Text('Authorised signatory', style: small),
              ],
            ),
          ],
        ),
      ],
    ));
  }

  static pw.Widget _a4Header(Bill bill) {
    final SellerDetails s = bill.seller;
    pw.Widget kv(String k, String v) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 2),
          child: pw.RichText(
            text: pw.TextSpan(children: <pw.TextSpan>[
              pw.TextSpan(text: '$k: ', style: const pw.TextStyle(color: _muted)),
              pw.TextSpan(text: v, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ]),
          ),
        );
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Text(s.displayName,
                  style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
              if (s.legalName != null && s.legalName != s.name)
                pw.Text(s.name, style: const pw.TextStyle(color: _muted)),
              if (s.address != null)
                pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 3), child: pw.Text(s.address!)),
              if (s.phone != null) pw.Text('Phone: ${s.phone}'),
              if (s.gstin != null)
                pw.Text('GSTIN: ${s.gstin}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              if (s.stateCode != null) pw.Text('State: ${GstStates.label(s.stateCode!)}'),
              if (s.drugLicenseNo != null) pw.Text('D.L. No.: ${s.drugLicenseNo}'),
            ],
          ),
        ),
        pw.SizedBox(width: 16),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: <pw.Widget>[
            pw.Text(_title(bill),
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            kv('Invoice No.', bill.invoiceNo),
            kv('Date', _when(bill)),
            kv('Payment', bill.paymentMode.label),
          ],
        ),
      ],
    );
  }

  static pw.Widget _a4Parties(Bill bill) {
    const pw.TextStyle label =
        pw.TextStyle(fontSize: 7.5, color: _muted, letterSpacing: 0.5);
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _line, width: 0.6)),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.Text('BILL TO', style: label),
                pw.SizedBox(height: 2),
                pw.Text(bill.customerName ?? 'Walk-in customer',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                if (bill.customerPhone != null) pw.Text('Phone: ${bill.customerPhone}'),
                if (bill.customerGstin != null) pw.Text('GSTIN: ${bill.customerGstin}'),
                if (bill.customerAddress != null) pw.Text(bill.customerAddress!),
              ],
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.Text('PLACE OF SUPPLY', style: label),
                pw.SizedBox(height: 2),
                pw.Text(bill.placeOfSupplyLabel ?? '-',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                if (_registered(bill)) ...<pw.Widget>[
                  pw.Text(bill.isInterState
                      ? 'Inter-state supply (IGST)'
                      : 'Intra-state supply (CGST + SGST)'),
                  pw.Text('Reverse charge: No'),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _cell(String text,
      {bool right = false, bool bold = false, double size = 8, PdfColor? color}) {
    return pw.Container(
      alignment: right ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      child: pw.Text(text,
          style: pw.TextStyle(
              fontSize: size,
              color: color,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
    );
  }

  static pw.Widget _a4Items(Bill bill) {
    final bool gst = _registered(bill);
    final List<(String, double, bool)> cols = <(String, double, bool)>[
      ('#', 0.45, false),
      ('Item', 3.2, false),
      ('HSN', 0.95, false),
      ('Batch', 1.15, false),
      ('Exp', 0.8, false),
      ('Qty', 0.7, true),
      ('MRP', 1.1, true),
      ('Disc', 0.75, true),
      if (gst) ('Rate', 1.05, true),
      if (gst) ('GST', 0.7, true),
      if (gst) ('Taxable', 1.25, true),
      ('Amount', 1.25, true),
    ];
    return pw.Table(
      columnWidths: <int, pw.TableColumnWidth>{
        for (int i = 0; i < cols.length; i++) i: pw.FlexColumnWidth(cols[i].$2),
      },
      border: const pw.TableBorder(
        top: pw.BorderSide(color: _line, width: 0.6),
        bottom: pw.BorderSide(color: _line, width: 0.6),
        horizontalInside: pw.BorderSide(color: _line, width: 0.3),
      ),
      children: <pw.TableRow>[
        pw.TableRow(
          repeat: true,
          decoration: const pw.BoxDecoration(color: _band),
          children: <pw.Widget>[
            for (final (String, double, bool) c in cols)
              _cell(c.$1, right: c.$3, bold: true, size: 7.5),
          ],
        ),
        for (final BillItem i in bill.items)
          pw.TableRow(
            children: <pw.Widget>[
              _cell('${i.lineNo}'),
              _cell(i.name),
              _cell(i.hsn ?? '-'),
              _cell(i.batchNo ?? '-'),
              _cell(_exp(i.expiryDate)),
              _cell('${i.qty}', right: true),
              _cell(_amt(i.mrpPaise), right: true),
              _cell(i.discountBp > 0 ? Inr.percent(i.discountBp) : '-', right: true),
              if (gst) _cell(_amt(i.ratePaise), right: true),
              if (gst) _cell(Inr.percent(i.gstRateBp), right: true),
              if (gst) _cell(_amt(i.taxablePaise), right: true),
              _cell(_amt(i.totalPaise), right: true, bold: true),
            ],
          ),
      ],
    );
  }

  static pw.Widget _a4Summary(Bill bill) {
    final bool gst = _registered(bill);
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Expanded(child: gst ? _taxTable(bill, 8, splitRates: true) : pw.SizedBox()),
        pw.SizedBox(width: 16),
        pw.SizedBox(width: 200, child: _totals(bill, size: 9, totalSize: 12)),
      ],
    );
  }

  /// Taxable value and tax per GST rate ([splitRates]: "5% (2.5%+2.5%)").
  /// Receipts skip the grey header band (thermal printers dither grey).
  static pw.Widget _taxTable(Bill bill, double size,
      {bool splitRates = false, bool banded = true}) {
    final bool inter = bill.isInterState;
    final List<String> head = <String>[
      'GST',
      'Taxable',
      if (inter) 'IGST' else ...<String>['CGST', 'SGST'],
      'Total tax',
    ];
    List<pw.Widget> row(String rate, int taxable, int cgst, int sgst, int igst,
            {bool bold = false}) =>
        <pw.Widget>[
          _cell(rate, bold: bold, size: size),
          _cell(_amt(taxable), right: true, bold: bold, size: size),
          if (inter)
            _cell(_amt(igst), right: true, bold: bold, size: size)
          else ...<pw.Widget>[
            _cell(_amt(cgst), right: true, bold: bold, size: size),
            _cell(_amt(sgst), right: true, bold: bold, size: size),
          ],
          _cell(_amt(cgst + sgst + igst), right: true, bold: bold, size: size),
        ];
    return pw.Table(
      border: pw.TableBorder.all(color: _line, width: 0.4),
      children: <pw.TableRow>[
        pw.TableRow(
          decoration: banded ? const pw.BoxDecoration(color: _band) : null,
          children: <pw.Widget>[
            for (int i = 0; i < head.length; i++)
              _cell(head[i], right: i > 0, bold: true, size: size - 0.5),
          ],
        ),
        for (final BillTaxRow t in bill.taxSummary)
          pw.TableRow(
            children: row(
                inter || !splitRates
                    ? Inr.percent(t.gstRateBp)
                    : '${Inr.percent(t.gstRateBp)} (${Inr.percent(t.gstRateBp ~/ 2)}+${Inr.percent(t.gstRateBp - t.gstRateBp ~/ 2)})',
                t.taxablePaise,
                t.cgstPaise,
                t.sgstPaise,
                t.igstPaise),
          ),
        if (bill.taxSummary.length > 1)
          pw.TableRow(
            children: row('Total', bill.taxablePaise, bill.cgstPaise, bill.sgstPaise,
                bill.igstPaise,
                bold: true),
          ),
      ],
    );
  }

  /// MRP value -> discount -> taxable + tax -> round off -> total.
  static pw.Widget _totals(Bill bill, {required double size, required double totalSize}) {
    final bool gst = _registered(bill);
    pw.Widget line(String k, String v, {bool strong = false, double? fs}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: <pw.Widget>[
              pw.Text(k,
                  style: pw.TextStyle(
                      fontSize: fs ?? size,
                      fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal)),
              pw.Text(v,
                  style: pw.TextStyle(
                      fontSize: fs ?? size,
                      fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal)),
            ],
          ),
        );
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: <pw.Widget>[
        line('MRP value', Inr.format(bill.subtotalPaise)),
        if (bill.discountPaise > 0) line('Discount', '-${Inr.format(bill.discountPaise)}'),
        if (gst) ...<pw.Widget>[
          line('Taxable value', Inr.format(bill.taxablePaise)),
          if (bill.isInterState)
            line('IGST', Inr.format(bill.igstPaise))
          else ...<pw.Widget>[
            line('CGST', Inr.format(bill.cgstPaise)),
            line('SGST', Inr.format(bill.sgstPaise)),
          ],
        ],
        if (bill.roundOffPaise != 0)
          line('Round off',
              '${bill.roundOffPaise > 0 ? '+' : '-'}${Inr.format(bill.roundOffPaise.abs())}'),
        pw.Container(
          margin: const pw.EdgeInsets.only(top: 3),
          padding: const pw.EdgeInsets.only(top: 3),
          decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: _ink, width: 0.8))),
          child: line('Total', Inr.format(bill.totalPaise), strong: true, fs: totalSize),
        ),
      ],
    );
  }

  static pw.Widget _cancelledStamp(double size) => pw.FullPage(
        ignoreMargins: true,
        child: pw.Center(
          child: pw.Transform.rotate(
            angle: 0.6,
            child: pw.Opacity(
              opacity: 0.18,
              child: pw.Text('CANCELLED',
                  style: pw.TextStyle(
                      fontSize: size,
                      color: PdfColors.red,
                      fontWeight: pw.FontWeight.bold)),
            ),
          ),
        ),
      );

  // ---- 80 mm receipt -------------------------------------------------------------

  static void _receipt(pw.Document doc, Bill bill, pw.ThemeData theme) {
    final SellerDetails s = bill.seller;
    const pw.TextStyle small = pw.TextStyle(fontSize: 6.8, color: _muted);
    final pw.TextStyle bold = pw.TextStyle(fontWeight: pw.FontWeight.bold);
    pw.Widget rule() => pw.Container(
          margin: const pw.EdgeInsets.symmetric(vertical: 4),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
                bottom: pw.BorderSide(color: _ink, width: 0.5, style: pw.BorderStyle.dashed)),
          ),
        );
    pw.Widget centered(String text, {pw.TextStyle? style}) =>
        pw.Text(text, style: style, textAlign: pw.TextAlign.center);

    doc.addPage(pw.Page(
      pageTheme: pw.PageTheme(
        pageFormat: _receiptFormat,
        theme: theme.copyWith(
            defaultTextStyle: theme.defaultTextStyle.copyWith(fontSize: 7.6, color: _ink)),
        buildForeground: bill.isCancelled ? (_) => _cancelledStamp(30) : null,
      ),
      build: (pw.Context ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: <pw.Widget>[
          centered(s.displayName,
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          if (s.address != null) centered(s.address!),
          if (s.phone != null) centered('Ph: ${s.phone}'),
          if (s.gstin != null) centered('GSTIN: ${s.gstin}', style: bold),
          if (s.drugLicenseNo != null) centered('D.L. No.: ${s.drugLicenseNo}'),
          rule(),
          centered(bill.isCancelled ? '${_title(bill)} (CANCELLED)' : _title(bill),
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5)),
          pw.SizedBox(height: 3),
          _pair('Bill No.', bill.invoiceNo, valueStyle: bold),
          _pair('Date', _when(bill)),
          if (bill.customerName != null || bill.customerPhone != null)
            _pair('Customer',
                <String?>[bill.customerName, bill.customerPhone].whereType<String>().join(', ')),
          if (bill.customerGstin != null) _pair('GSTIN', bill.customerGstin!),
          if (_registered(bill)) _pair('Place of supply', bill.placeOfSupplyLabel ?? '-'),
          rule(),
          pw.Row(children: <pw.Widget>[
            pw.Expanded(child: pw.Text('Item', style: bold)),
            pw.SizedBox(width: 26, child: pw.Text('Qty', style: bold, textAlign: pw.TextAlign.right)),
            pw.SizedBox(width: 52, child: pw.Text('Amount', style: bold, textAlign: pw.TextAlign.right)),
          ]),
          pw.SizedBox(height: 2),
          for (final BillItem i in bill.items)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 3),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: <pw.Widget>[
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: <pw.Widget>[
                      pw.Expanded(child: pw.Text(i.name)),
                      pw.SizedBox(width: 26, child: pw.Text('${i.qty}', textAlign: pw.TextAlign.right)),
                      pw.SizedBox(
                          width: 52,
                          child: pw.Text(_amt(i.totalPaise), textAlign: pw.TextAlign.right)),
                    ],
                  ),
                  pw.Text(
                    <String>[
                      if (i.batchNo != null) 'B: ${i.batchNo}',
                      'Exp ${_exp(i.expiryDate)}',
                      'MRP ${_amt(i.mrpPaise)}',
                      if (i.discountBp > 0) 'Disc ${Inr.percent(i.discountBp)}',
                      if (_registered(bill)) 'GST ${Inr.percent(i.gstRateBp)}',
                      if (_registered(bill) && i.hsn != null) 'HSN ${i.hsn}',
                    ].join(' · '),
                    style: small,
                  ),
                ],
              ),
            ),
          rule(),
          _totals(bill, size: 7.6, totalSize: 11),
          if (_registered(bill) && bill.taxSummary.isNotEmpty) ...<pw.Widget>[
            rule(),
            _taxTable(bill, 6.6, banded: false),
          ],
          rule(),
          pw.Text(Inr.words(bill.totalPaise), style: bold),
          pw.SizedBox(height: 2),
          pw.Text('Paid by: ${bill.paymentMode.label}'),
          pw.SizedBox(height: 6),
          centered('Thank you. Get well soon!', style: small),
        ],
      ),
    ));
  }

  static pw.Widget _pair(String k, String v, {pw.TextStyle? valueStyle}) => pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.SizedBox(width: 66, child: pw.Text(k, style: const pw.TextStyle(color: _muted))),
          pw.Expanded(child: pw.Text(v, style: valueStyle)),
        ],
      );
}
