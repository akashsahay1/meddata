import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../core/inr.dart';
import '../data/models/accounting.dart';
import '../domain/accounting.dart';
import '../domain/gst.dart';
import 'invoice_pdf.dart';

/// A4 PDFs for accounting: a party's ledger (statement of account) and
/// credit / debit notes. Same embedded fonts as invoices (for the ₹ sign).
class AccountingPdf {
  AccountingPdf._();

  static const PdfColor _ink = PdfColor.fromInt(0xFF0A302E);
  static const PdfColor _muted = PdfColor.fromInt(0xFF66807D);
  static const PdfColor _line = PdfColor.fromInt(0xFFB4C4C1);
  static const PdfColor _band = PdfColor.fromInt(0xFFEEF2F1);
  static final DateFormat _d = DateFormat('dd MMM yyyy');

  static String _safe(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9-]+'), '-');

  static String ledgerFileName(Ledger l) => 'Ledger-${_safe(l.party.name)}.pdf';
  static String noteFileName(ReturnNote n) =>
      '${n.isCreditNote ? 'Credit-note' : 'Debit-note'}-${_safe(n.noteNo)}.pdf';

  static pw.Document _doc(String title, InvoiceFonts fonts, bool compress) => pw.Document(
        compress: compress,
        title: title,
        creator: 'Meddata',
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
      );

  static pw.PageTheme _page(pw.Document doc) => pw.PageTheme(
        pageFormat: PdfPageFormat.a4.copyWith(marginLeft: 28, marginRight: 28, marginTop: 28, marginBottom: 28),
        theme: doc.theme!.copyWith(defaultTextStyle: doc.theme!.defaultTextStyle.copyWith(fontSize: 9, color: _ink)),
      );

  static pw.Widget _footer(pw.Context ctx, String left) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 8),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: <pw.Widget>[
          pw.Text(left, style: const pw.TextStyle(fontSize: 8, color: _muted)),
          pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: _muted)),
        ]),
      );

  static pw.Widget _seller(Map<String, dynamic> s) {
    String? v(String k) {
      final Object? x = s[k];
      return x == null || '$x'.isEmpty ? null : '$x';
    }

    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: <pw.Widget>[
      pw.Text(v('legal_name') ?? v('name') ?? '', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      if (v('address') != null) pw.Text(v('address')!),
      if (v('phone') != null) pw.Text('Phone: ${v('phone')}'),
      if (v('gstin') != null) pw.Text('GSTIN: ${v('gstin')}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      if (v('state_code') != null) pw.Text('State: ${GstStates.label(v('state_code')!)}'),
    ]);
  }

  static pw.Widget _cell(String text, {bool right = false, bool bold = false, double size = 8}) => pw.Container(
        alignment: right ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
        child: pw.Text(text,
            style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      );

  static String _amt(int paise) => Inr.format(paise, symbol: false);

  // ---- ledger -------------------------------------------------------------------

  /// [compress] false keeps the streams readable (tests).
  static Future<Uint8List> ledger(Ledger l, {required InvoiceFonts fonts, bool compress = true}) {
    final pw.Document doc = _doc('Ledger ${l.party.name}', fonts, compress);
    final String period = l.from == null && l.to == null
        ? 'All entries'
        : '${l.from == null ? 'Start' : _d.format(l.from!)} to ${l.to == null ? 'today' : _d.format(l.to!)}';
    final List<(String, double, bool)> cols = <(String, double, bool)>[
      ('Date', 1.2, false),
      ('Particulars', 3.2, false),
      ('Ref. no.', 1.8, false),
      ('Debit', 1.3, true),
      ('Credit', 1.3, true),
      ('Balance', 1.6, true),
    ];
    doc.addPage(pw.MultiPage(
      pageTheme: _page(doc),
      footer: (pw.Context ctx) => _footer(ctx, 'Debit = owed to us, Credit = paid / owed by us. Computer-generated statement.'),
      build: (pw.Context ctx) => <pw.Widget>[
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: <pw.Widget>[
          pw.Expanded(child: _seller(l.seller)),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: <pw.Widget>[
            pw.Text('STATEMENT OF ACCOUNT', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(period),
          ]),
        ]),
        pw.SizedBox(height: 10),
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: _line, width: 0.6)),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: <pw.Widget>[
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: <pw.Widget>[
                pw.Text(l.party.name, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                if (l.party.phone != null) pw.Text('Phone: ${l.party.phone}'),
                if (l.party.gstin != null) pw.Text('GSTIN: ${l.party.gstin}'),
                if (l.party.address != null) pw.Text(l.party.address!),
              ]),
            ),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: <pw.Widget>[
              pw.Text('Closing balance', style: const pw.TextStyle(color: _muted)),
              pw.Text(BalanceText.drCr(l.closingPaise), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              pw.Text(BalanceText.of(l.closingPaise)),
            ]),
          ]),
        ),
        pw.SizedBox(height: 10),
        pw.Table(
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
              children: <pw.Widget>[for (final (String, double, bool) c in cols) _cell(c.$1, right: c.$3, bold: true)],
            ),
            pw.TableRow(children: <pw.Widget>[
              _cell(l.from == null ? '' : _d.format(l.from!)),
              _cell(l.from == null ? 'Opening balance' : 'Balance brought forward', bold: true),
              _cell(''),
              _cell(''),
              _cell(''),
              _cell(BalanceText.drCr(l.openingPaise), right: true, bold: true),
            ]),
            for (final LedgerEntry e in l.entries)
              pw.TableRow(children: <pw.Widget>[
                _cell(_d.format(e.date)),
                _cell(e.description),
                _cell(e.number ?? ''),
                _cell(e.debitPaise == 0 ? '' : _amt(e.debitPaise), right: true),
                _cell(e.creditPaise == 0 ? '' : _amt(e.creditPaise), right: true),
                _cell(BalanceText.drCr(e.balancePaise), right: true),
              ]),
            pw.TableRow(children: <pw.Widget>[
              _cell(''),
              _cell('Total', bold: true),
              _cell(''),
              _cell(_amt(l.debitPaise), right: true, bold: true),
              _cell(_amt(l.creditPaise), right: true, bold: true),
              _cell(BalanceText.drCr(l.closingPaise), right: true, bold: true),
            ]),
          ],
        ),
      ],
    ));
    return doc.save();
  }

  // ---- credit / debit note ----------------------------------------------------------

  static Future<Uint8List> note(ReturnNote n, {required InvoiceFonts fonts, bool compress = true}) {
    final pw.Document doc = _doc('${n.title} ${n.noteNo}', fonts, compress);
    final bool gst = n.seller['gstin'] != null;
    final List<(String, double, bool)> cols = <(String, double, bool)>[
      ('#', 0.4, false),
      ('Item', 3, false),
      ('HSN', 0.9, false),
      ('Batch', 1.1, false),
      ('Qty', 0.6, true),
      (n.isCreditNote ? 'MRP' : 'Rate', 1, true),
      ('Disc', 0.7, true),
      if (gst) ('GST', 0.6, true),
      if (gst) ('Taxable', 1.2, true),
      ('Amount', 1.2, true),
    ];
    pw.Widget kv(String k, String v) => pw.Text('$k: $v');
    doc.addPage(pw.MultiPage(
      pageTheme: _page(doc),
      footer: (pw.Context ctx) => _footer(ctx, 'This is a computer-generated ${n.title.toLowerCase()}.'),
      build: (pw.Context ctx) => <pw.Widget>[
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: <pw.Widget>[
          pw.Expanded(child: _seller(n.seller)),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: <pw.Widget>[
            pw.Text(n.title.toUpperCase(), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            kv('No.', n.noteNo),
            kv('Date', _d.format(n.date)),
            if (n.againstNo != null)
              kv(n.isCreditNote ? 'Against invoice' : 'Supplier invoice',
                  '${n.againstNo}${n.againstDate == null ? '' : ' (${_d.format(n.againstDate!)})'}'),
          ]),
        ]),
        pw.SizedBox(height: 10),
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: _line, width: 0.6)),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: <pw.Widget>[
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: <pw.Widget>[
                pw.Text(n.isCreditNote ? 'CUSTOMER' : 'SUPPLIER', style: const pw.TextStyle(fontSize: 7.5, color: _muted)),
                pw.Text(n.partyName ?? 'Walk-in customer', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                if (n.partyGstin != null) pw.Text('GSTIN: ${n.partyGstin}'),
              ]),
            ),
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: <pw.Widget>[
                pw.Text('PLACE OF SUPPLY', style: const pw.TextStyle(fontSize: 7.5, color: _muted)),
                pw.Text(n.placeOfSupply == null ? '-' : GstStates.label(n.placeOfSupply!)),
                if (gst) pw.Text(n.isInterState ? 'Inter-state (IGST)' : 'Intra-state (CGST + SGST)'),
              ]),
            ),
          ]),
        ),
        pw.SizedBox(height: 10),
        pw.Table(
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
              children: <pw.Widget>[for (final (String, double, bool) c in cols) _cell(c.$1, right: c.$3, bold: true)],
            ),
            for (int i = 0; i < n.items.length; i++)
              pw.TableRow(children: <pw.Widget>[
                _cell('${i + 1}'),
                _cell(n.items[i].name),
                _cell(n.items[i].hsn ?? '-'),
                _cell(n.items[i].batchNo ?? '-'),
                _cell('${n.items[i].qty}', right: true),
                _cell(_amt(n.items[i].ratePaise), right: true),
                _cell(n.items[i].discountBp > 0 ? Inr.percent(n.items[i].discountBp) : '-', right: true),
                if (gst) _cell(Inr.percent(n.items[i].gstRateBp), right: true),
                if (gst) _cell(_amt(n.items[i].taxablePaise), right: true),
                _cell(_amt(n.items[i].totalPaise), right: true, bold: true),
              ]),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: <pw.Widget>[
          pw.Expanded(
            child: gst
                ? pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: <pw.Widget>[
                    pw.Text('GST by rate', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    for (final ({int rateBp, int taxablePaise, int taxPaise}) t in n.taxSummary)
                      pw.Text('${Inr.percent(t.rateBp)} on ${Inr.format(t.taxablePaise)}: ${Inr.format(t.taxPaise)}'),
                  ])
                : pw.SizedBox(),
          ),
          pw.SizedBox(
            width: 200,
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: <pw.Widget>[
              for (final (String, int) row in <(String, int)>[
                if (gst) ('Taxable value', n.taxablePaise),
                if (gst && n.isInterState) ('IGST', n.igstPaise),
                if (gst && !n.isInterState) ('CGST', n.cgstPaise),
                if (gst && !n.isInterState) ('SGST', n.sgstPaise),
                if (n.roundOffPaise != 0) ('Round off', n.roundOffPaise),
              ])
                pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: <pw.Widget>[
                  pw.Text(row.$1),
                  pw.Text(row.$1 == 'Round off'
                      ? '${row.$2 > 0 ? '+' : '-'}${Inr.format(row.$2.abs())}'
                      : Inr.format(row.$2)),
                ]),
              pw.Divider(color: _ink, thickness: 0.8),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: <pw.Widget>[
                pw.Text('Total', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                pw.Text(Inr.format(n.totalPaise), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              ]),
            ]),
          ),
        ]),
        pw.SizedBox(height: 8),
        pw.Text('Amount in words: ${Inr.words(n.totalPaise)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        if (n.reason != null) pw.Text('Reason: ${n.reason}'),
        if (n.isCreditNote && n.refundMode != null)
          pw.Text(n.refundMode == 'credit'
              ? 'Adjusted against the customer\'s account.'
              : 'Refunded by ${n.refundMode!.toUpperCase()}.'),
      ],
    ));
    return doc.save();
  }
}

/// Print or share the accounting PDFs.
class AccountingShare {
  AccountingShare._();

  static Future<void> _share(Uint8List pdf, String name, String subject, String text) async {
    final Directory dir = await getTemporaryDirectory();
    final File file = File(p.join(dir.path, name));
    await file.writeAsBytes(pdf);
    await SharePlus.instance.share(ShareParams(
      files: <XFile>[XFile(file.path, mimeType: 'application/pdf')],
      subject: subject,
      text: text,
    ));
  }

  static Future<void> shareLedger(Ledger l) async => _share(
        await AccountingPdf.ledger(l, fonts: await InvoiceFonts.load()),
        AccountingPdf.ledgerFileName(l),
        'Statement of account - ${l.party.name}',
        '${l.party.name}: balance ${BalanceText.of(l.closingPaise)}',
      );

  static Future<void> printLedger(Ledger l) async {
    final Uint8List pdf = await AccountingPdf.ledger(l, fonts: await InvoiceFonts.load());
    await Printing.layoutPdf(name: AccountingPdf.ledgerFileName(l), onLayout: (_) async => pdf);
  }

  static Future<void> shareNote(ReturnNote n) async => _share(
        await AccountingPdf.note(n, fonts: await InvoiceFonts.load()),
        AccountingPdf.noteFileName(n),
        '${n.title} ${n.noteNo}',
        '${n.title} ${n.noteNo}: ${Inr.format(n.totalPaise)}',
      );

  static Future<void> printNote(ReturnNote n) async {
    final Uint8List pdf = await AccountingPdf.note(n, fonts: await InvoiceFonts.load());
    await Printing.layoutPdf(name: AccountingPdf.noteFileName(n), onLayout: (_) async => pdf);
  }

  /// A text file (CSV / JSON) to the share sheet.
  static Future<void> shareText(String content, String name, String mime, String subject) async {
    final Directory dir = await getTemporaryDirectory();
    final File file = File(p.join(dir.path, name));
    await file.writeAsString(content);
    await SharePlus.instance.share(ShareParams(
      files: <XFile>[XFile(file.path, mimeType: mime)],
      subject: subject,
    ));
  }
}
