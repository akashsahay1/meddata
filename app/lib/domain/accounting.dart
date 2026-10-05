import 'package:csv/csv.dart';

import '../core/inr.dart';
import '../data/models/accounting.dart';
import '../data/models/bill.dart';
import 'gst.dart';
import 'invoice_draft.dart';

/// A party balance in words. Positive = the party owes the shop.
class BalanceText {
  BalanceText._();

  /// "₹1,200.00 to collect" / "₹50.00 to pay" / "Settled".
  static String of(int paise) {
    if (paise == 0) return 'Settled';
    return '${Inr.format(paise.abs())} ${paise > 0 ? 'to collect' : 'to pay'}';
  }

  /// "Dr" (owes the shop) / "Cr" (the shop owes) after an amount, ledger style.
  static String drCr(int paise) =>
      paise == 0 ? Inr.format(0) : '${Inr.format(paise.abs())} ${paise > 0 ? 'Dr' : 'Cr'}';
}

/// One returnable line: a bill item (sale return) or a purchase item
/// (purchase return), and how many go back.
class ReturnLine {
  ReturnLine({
    required this.itemId,
    required this.name,
    this.batchNo,
    required this.maxQty,
    required this.ratePaise,
    required this.discountBp,
    required this.gstRateBp,
    this.qty = 0,
  });

  final int itemId;
  final String name;
  final String? batchNo;

  /// Sold (or bought) less what earlier notes returned.
  final int maxQty;

  /// Sale: MRP incl. GST; purchase: rate before GST (per pack).
  final int ratePaise;
  final int discountBp;
  final int gstRateBp;
  int qty;
}

/// A sale return (credit note) or purchase return (debit note) being made.
/// The preview uses the same maths as the server; the server's note counts
/// (the last units of a line take exactly what is left of it there).
class ReturnDraft {
  ReturnDraft._(this.isSale, this.documentId, this.interState, this.lines);

  factory ReturnDraft.forBill(Bill bill) => ReturnDraft._(
        true,
        bill.id,
        bill.isInterState,
        <ReturnLine>[
          for (final BillItem i in bill.items)
            if (i.returnableQty > 0)
              ReturnLine(
                itemId: i.id,
                name: i.name,
                batchNo: i.batchNo,
                maxQty: i.returnableQty,
                ratePaise: i.mrpPaise,
                discountBp: i.discountBp,
                gstRateBp: i.gstRateBp,
              ),
        ],
      );

  factory ReturnDraft.forPurchase(Purchase purchase) => ReturnDraft._(
        false,
        purchase.id,
        purchase.isInterState,
        <ReturnLine>[
          for (final PurchaseItem i in purchase.items)
            if (i.qty - i.returnedQty > 0)
              ReturnLine(
                itemId: i.id,
                name: i.name,
                batchNo: i.batchNo,
                maxQty: i.qty - i.returnedQty,
                ratePaise: i.ratePaise,
                discountBp: i.discountBp,
                gstRateBp: i.gstRateBp,
              ),
        ],
      );

  final bool isSale;
  final String documentId;
  final bool interState;
  final List<ReturnLine> lines;

  void setQty(ReturnLine line, int qty) => line.qty = qty.clamp(0, line.maxQty);

  /// Everything back.
  void all() {
    for (final ReturnLine l in lines) {
      l.qty = l.maxQty;
    }
  }

  List<ReturnLine> get chosen => lines.where((ReturnLine l) => l.qty > 0).toList();
  bool get isEmpty => chosen.isEmpty;

  GstLine gstOf(ReturnLine l) => isSale
      ? GstMath.line(
          mrpPaise: l.ratePaise, qty: l.qty, discountBp: l.discountBp, gstRateBp: l.gstRateBp, interState: interState)
      : GstMath.purchaseLine(
          ratePaise: l.ratePaise, qty: l.qty, discountBp: l.discountBp, gstRateBp: l.gstRateBp, interState: interState);

  GstTotals get totals => GstMath.totals(chosen.map(gstOf));

  /// POST /sale-returns or /purchase-returns body.
  Map<String, Object?> body({required String id, String? deviceId, String? reason, String? refundMode}) =>
      <String, Object?>{
        'id': id,
        'device_id': deviceId,
        if (isSale) 'bill_id': documentId else 'purchase_id': documentId,
        if (isSale && refundMode != null) 'refund_mode': refundMode,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
        'lines': <Map<String, Object?>>[
          for (final ReturnLine l in chosen)
            if (isSale)
              <String, Object?>{'bill_item_id': l.itemId, 'qty_units': l.qty}
            else
              <String, Object?>{'purchase_item_id': l.itemId, 'qty': l.qty},
        ],
      };
}

/// Turns a reviewed invoice scan into a purchase entry (POST /purchases).
/// The server creates the batches and the stock movements; the device adds
/// none of its own, so the stock is counted once.
class PurchaseFromInvoice {
  PurchaseFromInvoice._();

  static String ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static int paise(double rupees) => (rupees * 100).round();

  /// [newProductId] gives the id for a line that is a new medicine (the
  /// same id on a retry, so it is not created twice).
  static Map<String, Object?> body({
    required String id,
    required String partyId,
    required String invoiceNo,
    required DateTime invoiceDate,
    required List<InvoiceDraftLine> lines,
    required String Function(InvoiceDraftLine) newProductId,
    String? deviceId,
    int? scanId,
  }) =>
      <String, Object?>{
        'id': id,
        'device_id': deviceId,
        'party_id': partyId,
        'supplier_invoice_no': invoiceNo.trim(),
        'invoice_date': ymd(invoiceDate),
        'invoice_scan_id': scanId,
        'lines': <Map<String, Object?>>[
          for (final InvoiceDraftLine l in lines) line(l, l.target == null ? newProductId(l) : null),
        ],
      };

  static Map<String, Object?> line(InvoiceDraftLine l, String? newProductId) {
    final bool isNew = l.target == null;
    final String? hsn = l.hsn.trim().isEmpty ? null : l.hsn.trim();
    return <String, Object?>{
      'product_id': isNew ? newProductId : l.target!.productId,
      if (isNew)
        'product': <String, Object?>{
          'name': l.name.trim(),
          if (l.manufacturer.trim().isNotEmpty) 'manufacturer': l.manufacturer.trim(),
          'unit': l.stockUnit,
          'category': 'Uncategorised',
          if (l.barcode.trim().isNotEmpty) 'barcode': l.barcode.trim(),
        },
      if (l.batchNo.trim().isNotEmpty) 'batch_no': l.batchNo.trim(),
      'expiry_date': ymd(l.expiry!),
      if (l.mfgDate != null) 'mfg_date': ymd(l.mfgDate!),
      'qty': l.quantity,
      'free_qty': l.freeQuantity,
      // Rates and MRP per pack as printed; stock in the medicine's unit.
      'units_per_pack': l.countsPieces ? l.unitsPerPack : 1,
      'rate_paise': paise(l.rate),
      'mrp_paise': paise(l.mrp),
      'discount_bp': (l.discountPercent * 100).round(),
      if (l.gstPercent != null) 'gst_rate_bp': (l.gstPercent! * 100).round(),
      'hsn': ?hsn,
    };
  }

  /// The purchase preview total (tax added to the rates).
  static GstTotals preview(List<InvoiceDraftLine> lines, {required bool interState, int defaultGstBp = 500}) =>
      GstMath.totals(lines.map((InvoiceDraftLine l) => GstMath.purchaseLine(
            ratePaise: paise(l.rate),
            qty: l.quantity,
            discountBp: (l.discountPercent * 100).round(),
            gstRateBp: l.gstPercent == null ? defaultGstBp : (l.gstPercent! * 100).round(),
            interState: interState,
          )));
}

/// GSTR-1 / GSTR-3B summaries (server JSON) as CSV for the CA. Amounts in
/// rupees with 2 decimals; rates as percentages.
class GstrCsv {
  GstrCsv._();

  static String _rs(Object? paise) => (((paise as num?) ?? 0) / 100).toStringAsFixed(2);
  static String _pct(Object? bp) {
    final num v = ((bp as num?) ?? 0) / 100;
    return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
  }

  static List<Map<String, dynamic>> _list(Object? raw) => <Map<String, dynamic>>[
        for (final Object? o in (raw as List<dynamic>?) ?? <dynamic>[])
          if (o is Map) Map<String, dynamic>.from(o),
      ];

  static String gstr1(Map<String, dynamic> r) {
    final List<List<Object?>> rows = <List<Object?>>[
      <Object?>['GSTR-1 summary', r['month'], 'GSTIN', r['gstin'] ?? 'not registered'],
      <Object?>[r['disclaimer']],
      <Object?>[],
      <Object?>['B2B', 'GSTIN', 'Receiver', 'Invoice no', 'Invoice date', 'Invoice value', 'Place of supply', 'Reverse charge', 'Rate %', 'Taxable', 'IGST', 'CGST', 'SGST'],
    ];
    for (final Map<String, dynamic> g in _list(r['b2b'])) {
      for (final Map<String, dynamic> inv in _list(g['invoices'])) {
        for (final Map<String, dynamic> rate in _list(inv['rates'])) {
          rows.add(<Object?>['B2B', g['gstin'], g['name'], inv['invoice_no'], inv['invoice_date'], _rs(inv['invoice_value_paise']),
            inv['place_of_supply'], inv['reverse_charge'], _pct(rate['gst_rate_bp']), _rs(rate['taxable_paise']),
            _rs(rate['igst_paise']), _rs(rate['cgst_paise']), _rs(rate['sgst_paise'])]);
        }
      }
    }
    rows
      ..add(<Object?>[])
      ..add(<Object?>['B2CL', 'Invoice no', 'Invoice date', 'Invoice value', 'Place of supply', 'Rate %', 'Taxable', 'IGST']);
    for (final Map<String, dynamic> inv in _list(r['b2cl'])) {
      for (final Map<String, dynamic> rate in _list(inv['rates'])) {
        rows.add(<Object?>['B2CL', inv['invoice_no'], inv['invoice_date'], _rs(inv['invoice_value_paise']), inv['place_of_supply'],
          _pct(rate['gst_rate_bp']), _rs(rate['taxable_paise']), _rs(rate['igst_paise'])]);
      }
    }
    rows
      ..add(<Object?>[])
      ..add(<Object?>['B2CS', 'Type', 'Place of supply', 'Supply', 'Rate %', 'Taxable', 'IGST', 'CGST', 'SGST']);
    for (final Map<String, dynamic> b in _list(r['b2cs'])) {
      rows.add(<Object?>['B2CS', b['type'], b['place_of_supply'], b['supply_type'], _pct(b['gst_rate_bp']), _rs(b['taxable_paise']),
        _rs(b['igst_paise']), _rs(b['cgst_paise']), _rs(b['sgst_paise'])]);
    }
    rows
      ..add(<Object?>[])
      ..add(<Object?>['CDN', 'Section', 'GSTIN', 'Name', 'Note no', 'Note date', 'Note type', 'Note value', 'Place of supply', 'Against invoice', 'Rate %', 'Taxable', 'IGST', 'CGST', 'SGST']);
    for (final (String section, Object? list) in <(String, Object?)>[('CDNR', r['cdnr']), ('CDNUR', r['cdnur'])]) {
      for (final Map<String, dynamic> n in _list(list)) {
        for (final Map<String, dynamic> rate in _list(n['rates'])) {
          rows.add(<Object?>['CDN', section, n['gstin'], n['name'], n['note_no'], n['note_date'], n['note_type'], _rs(n['note_value_paise']),
            n['place_of_supply'], n['invoice_no'], _pct(rate['gst_rate_bp']), _rs(rate['taxable_paise']), _rs(rate['igst_paise']),
            _rs(rate['cgst_paise']), _rs(rate['sgst_paise'])]);
        }
      }
    }
    rows
      ..add(<Object?>[])
      ..add(<Object?>['NIL', 'Supply', 'Nil rated value']);
    for (final Map<String, dynamic> n in _list(r['nil_rated'])) {
      rows.add(<Object?>['NIL', n['supply'], _rs(n['nil_rated_paise'])]);
    }
    rows
      ..add(<Object?>[])
      ..add(<Object?>['HSN', 'Section', 'HSN', 'Unit', 'Qty', 'Rate %', 'Total value', 'Taxable', 'IGST', 'CGST', 'SGST']);
    final Map<String, dynamic> hsn = Map<String, dynamic>.from((r['hsn'] as Map?) ?? <String, dynamic>{});
    for (final String section in <String>['b2b', 'b2c']) {
      for (final Map<String, dynamic> h in _list(hsn[section])) {
        rows.add(<Object?>['HSN', section.toUpperCase(), h['hsn'] ?? '', h['unit'] ?? '', h['qty'], _pct(h['gst_rate_bp']),
          _rs(h['total_value_paise']), _rs(h['taxable_paise']), _rs(h['igst_paise']), _rs(h['cgst_paise']), _rs(h['sgst_paise'])]);
      }
    }
    rows
      ..add(<Object?>[])
      ..add(<Object?>['DOCS', 'Nature of document', 'From', 'To', 'Total', 'Cancelled', 'Net issued']);
    for (final Map<String, dynamic> d in _list(r['documents'])) {
      rows.add(<Object?>['DOCS', d['nature'], d['from'] ?? '', d['to'] ?? '', d['total'], d['cancelled'], d['net_issued']]);
    }
    return Csv().encode(rows);
  }

  static String gstr3b(Map<String, dynamic> r) {
    Map<String, dynamic> m(Object? o) => Map<String, dynamic>.from((o as Map?) ?? <String, dynamic>{});
    final Map<String, dynamic> out = m(r['outward_taxable']);
    final Map<String, dynamic> itc = m(r['itc']);
    final Map<String, dynamic> pay = m(r['payment']);
    List<Object?> heads(String label, Map<String, dynamic> v, {bool taxable = true}) => <Object?>[
          label,
          if (taxable) _rs(v['taxable_paise']) else '',
          _rs(v['igst_paise']),
          _rs(v['cgst_paise']),
          _rs(v['sgst_paise']),
        ];
    final List<List<Object?>> rows = <List<Object?>>[
      <Object?>['GSTR-3B summary', r['month'], 'GSTIN', r['gstin'] ?? 'not registered'],
      <Object?>[r['disclaimer']],
      <Object?>[],
      <Object?>['Section', 'Taxable', 'IGST', 'CGST', 'SGST'],
      heads('3.1(a) Outward taxable supplies', out),
      <Object?>['3.1(c) Nil rated', _rs(m(r['outward_nil_rated'])['taxable_paise']), '', '', ''],
      heads('4(A)(5) ITC available', m(itc['available']), taxable: false),
      heads('4(B) ITC reversed (debit notes)', m(itc['reversed']), taxable: false),
      heads('4(C) Net ITC', m(itc['net']), taxable: false),
      heads('Tax payable', m(pay['tax_payable']), taxable: false),
      heads('Paid through ITC', m(pay['itc_used']), taxable: false),
      heads('Payable in cash', m(pay['cash_payable']), taxable: false),
      heads('ITC carried forward', m(pay['itc_carried_forward']), taxable: false),
      <Object?>[],
      <Object?>['3.2 Inter-state to unregistered', 'Place of supply', 'Taxable', 'IGST'],
      for (final Map<String, dynamic> u in _list(r['inter_state_unregistered']))
        <Object?>['', u['place_of_supply'], _rs(u['taxable_paise']), _rs(u['igst_paise'])],
    ];
    return Csv().encode(rows);
  }
}

/// Months for the GST reports: this month and the 23 before it.
List<DateTime> recentMonths(DateTime now, {int count = 24}) =>
    <DateTime>[for (int i = 0; i < count; i++) DateTime(now.year, now.month - i)];

/// "2026-10".
String monthKey(DateTime m) => '${m.year.toString().padLeft(4, '0')}-${m.month.toString().padLeft(2, '0')}';
