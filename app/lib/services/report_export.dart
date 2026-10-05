import 'dart:io';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../core/inr.dart';
import '../domain/reports/expiry_loss.dart';
import '../domain/reports/profit_report.dart';
import '../domain/reports/stock_valuation.dart';
import 'invoice_pdf.dart';

/// A report as a table: what the CSV holds and the PDF prints.
class ReportTable {
  const ReportTable(this.title, this.header, this.rows);
  final String title;
  final List<String> header;
  final List<List<Object?>> rows;
}

/// A report ready to export: a title, headline figures and tables.
class ReportDoc {
  const ReportDoc({
    required this.title,
    required this.subtitle,
    required this.fileStem,
    required this.summary,
    required this.tables,
    this.notes = const <String>[],
  });

  final String title;
  final String subtitle;

  /// File name without extension, e.g. "stock_value_2026-10-05".
  final String fileStem;

  /// Label -> value lines under the title.
  final List<(String, String)> summary;
  final List<ReportTable> tables;

  /// How the figures are worked out (printed at the end).
  final List<String> notes;
}

/// Builds report CSV / PDF files (the PDF with the invoice's embedded font,
/// which has ₹) and shares them.
class ReportExport {
  ReportExport._();

  static final DateFormat _ymd = DateFormat('yyyy-MM-dd');
  static final DateFormat _dmy = DateFormat('dd MMM yyyy');
  static final DateFormat _month = DateFormat('MMM yyyy');

  /// Rupees for a CSV cell: "1234.50" (no symbol or grouping, so
  /// spreadsheets read it as a number).
  static String rs(int paise) {
    final String sign = paise < 0 ? '-' : '';
    final int a = paise.abs();
    return '$sign${a ~/ 100}.${(a % 100).toString().padLeft(2, '0')}';
  }

  // ---- report documents ---------------------------------------------------

  static ReportDoc stockValuation(StockValuation v) {
    final String date = _ymd.format(v.asOf);
    List<Object?> row(StockRow r) => <Object?>[
          r.name,
          r.categoryLabel,
          r.batchNo,
          _ymd.format(r.expiry),
          r.qty,
          r.hasCost ? rs(r.costPaise) : '',
          r.hasCost ? rs(r.costValuePaise!) : '',
          rs(r.mrpPaise),
          rs(r.mrpValuePaise),
        ];
    const List<String> header = <String>[
      'Medicine', 'Category', 'Batch', 'Expiry', 'Qty', 'Cost/unit',
      'Value at cost', 'MRP/unit', 'Value at MRP',
    ];
    final List<StockRow> fresh = v.rows
        .where((StockRow r) => !r.isExpiredOn(v.asOf))
        .toList();
    return ReportDoc(
      title: 'Stock valuation',
      subtitle: 'As of ${_dmy.format(v.asOf)}',
      fileStem: 'stock_value_$date',
      summary: <(String, String)>[
        ('Sellable stock at cost', Inr.format(v.sellable.costPaise)),
        ('Sellable stock at MRP', Inr.format(v.sellable.mrpPaise)),
        ('Expiring within ${v.nearDays} days (cost / MRP)',
            '${Inr.format(v.nearExpiry.costPaise)} / ${Inr.format(v.nearExpiry.mrpPaise)}'),
        ('Expired stock (cost / MRP)',
            '${Inr.format(v.expired.costPaise)} / ${Inr.format(v.expired.mrpPaise)}'),
        if (v.total.hasUnknownCost)
          ('Batches without a purchase rate',
              '${v.total.unknownCostBatches} (${Inr.format(v.total.unknownCostMrpPaise)} at MRP, not in cost)'),
      ],
      tables: <ReportTable>[
        ReportTable('By category', const <String>[
          'Category', 'Batches', 'Units', 'Value at cost', 'Value at MRP',
        ], <List<Object?>>[
          for (final CategoryValue c in v.byCategory)
            <Object?>[
              c.category, c.value.batches, c.value.units,
              rs(c.value.costPaise), rs(c.value.mrpPaise),
            ],
        ]),
        ReportTable('Sellable stock', header, fresh.map(row).toList()),
        ReportTable('Expiring within ${v.nearDays} days', header,
            v.nearExpiryRows.map(row).toList()),
        ReportTable('Expired', header, v.expiredRows.map(row).toList()),
      ],
      notes: const <String>[
        'Cost = purchase rate entered for the batch (excluding GST). '
            'MRP includes GST.',
        'Batches without a purchase rate are left out of the cost total.',
      ],
    );
  }

  static ReportDoc profit(ProfitReport r) {
    final String range = '${_ymd.format(r.from)}_${_ymd.format(r.to)}';
    List<Object?> row(ProfitRow x) => <Object?>[
          x.label,
          x.qtyUnits,
          rs(x.revenuePaise),
          rs(x.costPaise),
          rs(x.profitPaise),
          marginText(x.marginBp),
          x.hasUnknownCost ? rs(x.unknownCostRevenuePaise) : '',
        ];
    List<String> header(String first) => <String>[
          first, 'Qty', 'Revenue (excl. GST)', 'Cost', 'Gross profit',
          'Margin', 'Revenue without cost',
        ];
    return ReportDoc(
      title: 'Profit',
      subtitle: '${_dmy.format(r.from)} to ${_dmy.format(r.to)}',
      fileStem: 'profit_$range',
      summary: <(String, String)>[
        ('Bills', '${r.totals.bills}'),
        ('Sales (incl. GST)', Inr.format(r.totals.salesPaise)),
        ('Revenue (excl. GST)', Inr.format(r.totals.revenuePaise)),
        ('Cost of goods sold', Inr.format(r.totals.costPaise)),
        ('Gross profit', Inr.format(r.totals.profitPaise)),
        ('Margin', marginText(r.totals.marginBp)),
        if (r.totals.hasUnknownCost)
          ('Sales without a purchase rate (not in profit)',
              Inr.format(r.totals.unknownCostRevenuePaise)),
      ],
      tables: <ReportTable>[
        ReportTable('By day', header('Date'), r.byDay.map(row).toList()),
        ReportTable('By category', header('Category'),
            r.byCategory.map(row).toList()),
        ReportTable('By product', header('Medicine'),
            r.byProduct.map(row).toList()),
        ReportTable('Sold without a purchase rate', const <String>[
          'Medicine', 'Batch', 'Qty', 'Revenue (excl. GST)',
        ], <List<Object?>>[
          for (final UnknownCostLine u in r.unknownCost)
            <Object?>[u.name, u.batchNo, u.qtyUnits, rs(u.revenuePaise)],
        ]),
      ],
      notes: const <String>[
        'Revenue = bill value excluding GST, after discount. Cancelled bills '
            'are left out.',
        'Cost = units sold x the batch purchase rate (excluding GST).',
        'Margin = gross profit / revenue, over lines with a known cost.',
      ],
    );
  }

  static ReportDoc expiry(ExpiryLoss e) {
    List<Object?> row(StockRow r) => <Object?>[
          r.name,
          r.batchNo,
          _ymd.format(r.expiry),
          r.daysLeft(e.today),
          r.qty,
          r.hasCost ? rs(r.costValuePaise!) : '',
          rs(r.mrpValuePaise),
        ];
    const List<String> header = <String>[
      'Medicine', 'Batch', 'Expiry', 'Days left', 'Qty', 'Value at cost',
      'Value at MRP',
    ];
    return ReportDoc(
      title: 'Expiry loss',
      subtitle: 'On ${_dmy.format(e.today)}',
      fileStem: 'expiry_loss_${_ymd.format(e.today)}',
      summary: <(String, String)>[
        ('Written off (cost / MRP)',
            '${Inr.format(e.writtenOff.costPaise)} / ${Inr.format(e.writtenOff.mrpPaise)}'),
        ('Expired, not written off (cost / MRP)',
            '${Inr.format(e.pending.costPaise)} / ${Inr.format(e.pending.mrpPaise)}'),
        for (final ExpiryWindow w in e.windows)
          ('Expiring in the next ${w.days} days (cost / MRP)',
              '${Inr.format(w.value.costPaise)} / ${Inr.format(w.value.mrpPaise)}'),
      ],
      tables: <ReportTable>[
        ReportTable('Expired stock by month of expiry', const <String>[
          'Month', 'Units', 'Loss at cost', 'Loss at MRP',
          'Written off at cost', 'Not written off at cost',
        ], <List<Object?>>[
          for (final ExpiryMonth m in e.months)
            <Object?>[
              _month.format(m.month), m.units, rs(m.costPaise), rs(m.mrpPaise),
              rs(m.writtenOff.costPaise), rs(m.pending.costPaise),
            ],
        ]),
        ReportTable('Expiring in the next ${e.windows.isEmpty ? 90 : e.windows.last.days} days',
            header, e.upcoming.map(row).toList()),
        ReportTable('Expired, not written off', header,
            e.pendingRows.map(row).toList()),
        ReportTable('Write-offs', const <String>[
          'Date', 'Medicine', 'Batch', 'Expiry', 'Qty', 'Value at cost',
          'Value at MRP',
        ], <List<Object?>>[
          for (final WriteOff w in e.writeOffs)
            <Object?>[
              _ymd.format(w.at), w.name, w.batchNo, _ymd.format(w.expiry),
              w.units, w.asRow.hasCost ? rs(w.asRow.costValuePaise!) : '',
              rs(w.asRow.mrpValuePaise),
            ],
        ]),
      ],
      notes: const <String>[
        'A month is the month the batch expired in.',
        'Cost = purchase rate entered for the batch (excluding GST); '
            'batches without one count at MRP only.',
      ],
    );
  }

  // ---- files ----------------------------------------------------------------

  /// The whole report as CSV: summary lines, then each table under its
  /// title, separated by blank rows.
  static String csv(ReportDoc doc) {
    final List<List<Object?>> rows = <List<Object?>>[
      <Object?>[doc.title, doc.subtitle],
      for (final (String, String) s in doc.summary) <Object?>[s.$1, s.$2],
      for (final ReportTable t in doc.tables) ...<List<Object?>>[
        <Object?>[],
        <Object?>[t.title],
        t.header,
        ...t.rows,
      ],
    ];
    return Csv().encode(rows);
  }

  static Future<Uint8List> pdf(ReportDoc doc,
      {required InvoiceFonts fonts, bool compress = true}) async {
    const PdfColor ink = PdfColor.fromInt(0xFF0A302E);
    const PdfColor muted = PdfColor.fromInt(0xFF5B726F);
    const PdfColor band = PdfColor.fromInt(0xFFEEF2F1);
    final pw.Document d = pw.Document(
      compress: compress,
      theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
    );
    d.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      footer: (pw.Context c) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Page ${c.pageNumber} of ${c.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: muted)),
      ),
      build: (pw.Context c) => <pw.Widget>[
        pw.Text(doc.title,
            style: pw.TextStyle(
                fontSize: 20, fontWeight: pw.FontWeight.bold, color: ink)),
        pw.Text(doc.subtitle,
            style: const pw.TextStyle(fontSize: 11, color: muted)),
        pw.SizedBox(height: 12),
        for (final (String, String) s in doc.summary)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 3),
            child: pw.Row(children: <pw.Widget>[
              pw.Expanded(
                  child: pw.Text(s.$1, style: const pw.TextStyle(fontSize: 10))),
              pw.Text(s.$2,
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold)),
            ]),
          ),
        for (final ReportTable t in doc.tables) ...<pw.Widget>[
          pw.SizedBox(height: 14),
          pw.Text(t.title,
              style: pw.TextStyle(
                  fontSize: 12, fontWeight: pw.FontWeight.bold, color: ink)),
          pw.SizedBox(height: 5),
          if (t.rows.isEmpty)
            pw.Text('None', style: const pw.TextStyle(fontSize: 9, color: muted))
          else
            pw.TableHelper.fromTextArray(
              headers: t.header,
              data: <List<String>>[
                for (final List<Object?> r in t.rows)
                  <String>[for (final Object? c in r) '${c ?? ''}'],
              ],
              headerStyle:
                  pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(color: band),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellAlignment: pw.Alignment.centerLeft,
              border: const pw.TableBorder(
                horizontalInside:
                    pw.BorderSide(color: PdfColor.fromInt(0xFFB4C4C1), width: 0.4),
              ),
            ),
        ],
        if (doc.notes.isNotEmpty) ...<pw.Widget>[
          pw.SizedBox(height: 16),
          for (final String n in doc.notes)
            pw.Text(n, style: const pw.TextStyle(fontSize: 8, color: muted)),
        ],
      ],
    ));
    return d.save();
  }

  static Future<void> shareCsv(ReportDoc doc) async {
    final Directory dir = await getTemporaryDirectory();
    final File file = File(p.join(dir.path, '${doc.fileStem}.csv'));
    await file.writeAsString(csv(doc));
    await SharePlus.instance.share(ShareParams(
      files: <XFile>[XFile(file.path, mimeType: 'text/csv')],
      subject: '${doc.title} - ${doc.subtitle}',
    ));
  }

  static Future<void> sharePdf(ReportDoc doc) async {
    final InvoiceFonts fonts = await InvoiceFonts.load();
    await Printing.sharePdf(
        bytes: await pdf(doc, fonts: fonts), filename: '${doc.fileStem}.pdf');
  }
}
