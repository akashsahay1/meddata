import '../../domain/gst.dart';

int _int(Object? v) => (v as num?)?.toInt() ?? 0;
String? _str(Object? v) {
  final String? s = v?.toString();
  return (s == null || s.isEmpty) ? null : s;
}

DateTime? _date(Object? v) {
  final String? s = _str(v);
  if (s == null) return null;
  final DateTime? d = DateTime.tryParse(s);
  if (d == null) return null;
  return s.length <= 10 ? DateTime(d.year, d.month, d.day) : d.toLocal();
}

List<Map<String, dynamic>> _maps(Object? raw) => <Map<String, dynamic>>[
      for (final Object? o in (raw as List<dynamic>?) ?? <dynamic>[])
        if (o is Map) Map<String, dynamic>.from(o),
    ];

/// Customer, supplier or both.
enum PartyType {
  customer('Customer'),
  supplier('Supplier'),
  both('Customer & supplier');

  const PartyType(this.label);
  final String label;

  static PartyType from(String? v) => PartyType.values
      .firstWhere((PartyType t) => t.name == v, orElse: () => PartyType.customer);

  bool get isCustomer => this != PartyType.supplier;
  bool get isSupplier => this != PartyType.customer;
}

/// A customer or supplier account. Balances: positive = the party owes the
/// shop ("to collect"), negative = the shop owes the party ("to pay").
class Party {
  const Party({
    required this.id,
    required this.type,
    required this.name,
    this.phone,
    this.gstin,
    this.stateCode,
    this.address,
    this.openingBalancePaise = 0,
    this.notes,
    this.balancePaise = 0,
  });

  factory Party.fromJson(Map<String, dynamic> j) => Party(
        id: _str(j['id']) ?? '',
        type: PartyType.from(_str(j['type'])),
        name: _str(j['name']) ?? '',
        phone: _str(j['phone']),
        gstin: _str(j['gstin']),
        stateCode: _str(j['state_code']),
        address: _str(j['address']),
        openingBalancePaise: _int(j['opening_balance_paise']),
        notes: _str(j['notes']),
        balancePaise: _int(j['balance_paise']),
      );

  final String id;
  final PartyType type;
  final String name;
  final String? phone;
  final String? gstin;
  final String? stateCode;
  final String? address;
  final int openingBalancePaise;
  final String? notes;
  final int balancePaise;

  /// "27 - Maharashtra".
  String? get stateLabel => stateCode == null ? null : GstStates.label(stateCode!);

  /// Name plus phone or GSTIN, for pickers.
  String get subtitle => <String?>[phone, gstin].whereType<String>().join(' · ');
}

/// One line of a party's account.
class LedgerEntry {
  const LedgerEntry({
    required this.type,
    required this.id,
    this.number,
    required this.date,
    required this.description,
    required this.debitPaise,
    required this.creditPaise,
    required this.balancePaise,
  });

  factory LedgerEntry.fromJson(Map<String, dynamic> j) => LedgerEntry(
        type: _str(j['type']) ?? '',
        id: _str(j['id']) ?? '',
        number: _str(j['number']),
        date: _date(j['date']) ?? DateTime.now(),
        description: _str(j['description']) ?? '',
        debitPaise: _int(j['debit_paise']),
        creditPaise: _int(j['credit_paise']),
        balancePaise: _int(j['balance_paise']),
      );

  /// sale | purchase | payment_in | payment_out | sale_return | purchase_return
  final String type;
  final String id;
  final String? number;
  final DateTime date;
  final String description;

  /// Raises what the party owes the shop.
  final int debitPaise;

  /// Lowers it.
  final int creditPaise;
  final int balancePaise;

  bool get isPayment => type == 'payment_in' || type == 'payment_out';
}

/// A party's ledger for a date range.
class Ledger {
  const Ledger({
    required this.party,
    this.from,
    this.to,
    required this.openingPaise,
    required this.closingPaise,
    required this.debitPaise,
    required this.creditPaise,
    required this.entries,
    required this.seller,
  });

  factory Ledger.fromJson(Map<String, dynamic> j) => Ledger(
        party: Party.fromJson(Map<String, dynamic>.from((j['party'] as Map?) ?? <String, dynamic>{})),
        from: _date(j['from']),
        to: _date(j['to']),
        openingPaise: _int(j['opening_paise']),
        closingPaise: _int(j['closing_paise']),
        debitPaise: _int(j['debit_paise']),
        creditPaise: _int(j['credit_paise']),
        entries: _maps(j['entries']).map(LedgerEntry.fromJson).toList(),
        seller: Map<String, dynamic>.from((j['seller'] as Map?) ?? <String, dynamic>{}),
      );

  final Party party;
  final DateTime? from;
  final DateTime? to;

  /// Balance brought forward to [from] (the opening balance without a range).
  final int openingPaise;
  final int closingPaise;
  final int debitPaise;
  final int creditPaise;
  final List<LedgerEntry> entries;

  /// The shop's details (for the PDF header).
  final Map<String, dynamic> seller;
}

/// A credit bill or purchase with money still to settle.
class OpenDocument {
  const OpenDocument({
    required this.type,
    required this.id,
    required this.number,
    required this.date,
    required this.totalPaise,
    required this.outstandingPaise,
  });

  factory OpenDocument.fromJson(Map<String, dynamic> j) => OpenDocument(
        type: _str(j['type']) ?? 'bill',
        id: _str(j['id']) ?? '',
        number: _str(j['number']) ?? '',
        date: _date(j['date']) ?? DateTime.now(),
        totalPaise: _int(j['total_paise']),
        outstandingPaise: _int(j['outstanding_paise']),
      );

  /// bill | purchase
  final String type;
  final String id;
  final String number;
  final DateTime date;
  final int totalPaise;
  final int outstandingPaise;

  bool get isBill => type == 'bill';
}

/// How money moved.
enum MoneyMode {
  cash('Cash'),
  upi('UPI'),
  card('Card'),
  bank('Bank transfer'),
  cheque('Cheque');

  const MoneyMode(this.label);
  final String label;

  static MoneyMode from(String? v) =>
      MoneyMode.values.firstWhere((MoneyMode m) => m.name == v, orElse: () => MoneyMode.cash);
}

/// A payment received (in) or made (out).
class PartyPayment {
  const PartyPayment({
    required this.id,
    required this.partyId,
    required this.isIn,
    required this.amountPaise,
    required this.mode,
    this.reference,
    required this.date,
    this.notes,
    this.billId,
    this.purchaseId,
    required this.cancelled,
  });

  factory PartyPayment.fromJson(Map<String, dynamic> j) => PartyPayment(
        id: _str(j['id']) ?? '',
        partyId: _str(j['party_id']) ?? '',
        isIn: j['direction'] == 'in',
        amountPaise: _int(j['amount_paise']),
        mode: MoneyMode.from(_str(j['mode'])),
        reference: _str(j['reference']),
        date: _date(j['payment_date']) ?? DateTime.now(),
        notes: _str(j['notes']),
        billId: _str(j['bill_id']),
        purchaseId: _str(j['purchase_id']),
        cancelled: j['status'] == 'cancelled',
      );

  final String id;
  final String partyId;
  final bool isIn;
  final int amountPaise;
  final MoneyMode mode;
  final String? reference;
  final DateTime date;
  final String? notes;
  final String? billId;
  final String? purchaseId;
  final bool cancelled;
}

/// One line of a supplier's bill, as entered.
class PurchaseItem {
  const PurchaseItem({
    required this.id,
    required this.lineNo,
    required this.productId,
    required this.batchId,
    required this.name,
    this.hsn,
    this.batchNo,
    this.expiryDate,
    required this.qty,
    required this.freeQty,
    required this.unitsPerPack,
    required this.stockUnits,
    required this.ratePaise,
    required this.mrpPaise,
    required this.discountBp,
    required this.gstRateBp,
    required this.taxablePaise,
    required this.taxPaise,
    required this.totalPaise,
    this.returnedQty = 0,
  });

  factory PurchaseItem.fromJson(Map<String, dynamic> j) => PurchaseItem(
        id: _int(j['id']),
        lineNo: _int(j['line_no']),
        productId: _str(j['product_id']) ?? '',
        batchId: _str(j['batch_id']) ?? '',
        name: _str(j['name']) ?? '',
        hsn: _str(j['hsn']),
        batchNo: _str(j['batch_no']),
        expiryDate: _date(j['expiry_date']),
        qty: _int(j['qty']),
        freeQty: _int(j['free_qty']),
        unitsPerPack: _int(j['units_per_pack']) == 0 ? 1 : _int(j['units_per_pack']),
        stockUnits: _int(j['stock_units']),
        ratePaise: _int(j['rate_paise']),
        mrpPaise: _int(j['mrp_paise']),
        discountBp: _int(j['discount_bp']),
        gstRateBp: _int(j['gst_rate_bp']),
        taxablePaise: _int(j['taxable_paise']),
        taxPaise: _int(j['cgst_paise']) + _int(j['sgst_paise']) + _int(j['igst_paise']),
        totalPaise: _int(j['total_paise']),
        returnedQty: _int(j['returned_qty']),
      );

  final int id;
  final int lineNo;
  final String productId;
  final String batchId;
  final String name;
  final String? hsn;
  final String? batchNo;
  final DateTime? expiryDate;
  final int qty;
  final int freeQty;
  final int unitsPerPack;
  final int stockUnits;
  final int ratePaise;
  final int mrpPaise;
  final int discountBp;
  final int gstRateBp;
  final int taxablePaise;
  final int taxPaise;
  final int totalPaise;

  /// Billed packs already sent back on debit notes.
  final int returnedQty;
}

/// A purchase entry (supplier's bill) as the server has it.
class Purchase {
  const Purchase({
    required this.id,
    required this.partyId,
    required this.supplierName,
    this.supplierGstin,
    required this.invoiceNo,
    required this.invoiceDate,
    required this.isInterState,
    required this.subtotalPaise,
    required this.discountPaise,
    required this.taxablePaise,
    required this.cgstPaise,
    required this.sgstPaise,
    required this.igstPaise,
    required this.roundOffPaise,
    required this.totalPaise,
    required this.outstandingPaise,
    required this.cancelled,
    this.cancelReason,
    this.notes,
    required this.items,
  });

  factory Purchase.fromJson(Map<String, dynamic> j) => Purchase(
        id: _str(j['id']) ?? '',
        partyId: _str(j['party_id']) ?? '',
        supplierName: _str(j['supplier_name']) ?? '',
        supplierGstin: _str(j['supplier_gstin']),
        invoiceNo: _str(j['supplier_invoice_no']) ?? '',
        invoiceDate: _date(j['invoice_date']) ?? DateTime.now(),
        isInterState: j['is_inter_state'] == true,
        subtotalPaise: _int(j['subtotal_paise']),
        discountPaise: _int(j['discount_paise']),
        taxablePaise: _int(j['taxable_paise']),
        cgstPaise: _int(j['cgst_paise']),
        sgstPaise: _int(j['sgst_paise']),
        igstPaise: _int(j['igst_paise']),
        roundOffPaise: _int(j['round_off_paise']),
        totalPaise: _int(j['total_paise']),
        outstandingPaise: _int(j['outstanding_paise']),
        cancelled: j['status'] == 'cancelled',
        cancelReason: _str(j['cancel_reason']),
        notes: _str(j['notes']),
        items: _maps(j['items']).map(PurchaseItem.fromJson).toList(),
      );

  final String id;
  final String partyId;
  final String supplierName;
  final String? supplierGstin;
  final String invoiceNo;
  final DateTime invoiceDate;
  final bool isInterState;
  final int subtotalPaise;
  final int discountPaise;
  final int taxablePaise;
  final int cgstPaise;
  final int sgstPaise;
  final int igstPaise;
  final int roundOffPaise;
  final int totalPaise;
  final int outstandingPaise;
  final bool cancelled;
  final String? cancelReason;
  final String? notes;
  final List<PurchaseItem> items;

  int get taxPaise => cgstPaise + sgstPaise + igstPaise;
}

/// One row of the purchases list.
class PurchaseSummary {
  const PurchaseSummary({
    required this.id,
    required this.supplierName,
    required this.invoiceNo,
    required this.invoiceDate,
    required this.totalPaise,
    required this.itemsCount,
    required this.cancelled,
  });

  factory PurchaseSummary.fromJson(Map<String, dynamic> j) => PurchaseSummary(
        id: _str(j['id']) ?? '',
        supplierName: _str(j['supplier_name']) ?? '',
        invoiceNo: _str(j['supplier_invoice_no']) ?? '',
        invoiceDate: _date(j['invoice_date']) ?? DateTime.now(),
        totalPaise: _int(j['total_paise']),
        itemsCount: _int(j['items_count']),
        cancelled: j['status'] == 'cancelled',
      );

  final String id;
  final String supplierName;
  final String invoiceNo;
  final DateTime invoiceDate;
  final int totalPaise;
  final int itemsCount;
  final bool cancelled;
}

/// A page of a list plus whether there is more.
class ApiPage<T> {
  const ApiPage(this.items, {required this.currentPage, required this.lastPage, this.totalPaise = 0, this.count = 0});

  factory ApiPage.fromJson(Map<String, dynamic> j, T Function(Map<String, dynamic>) item) {
    final Map<String, dynamic> meta = Map<String, dynamic>.from((j['meta'] as Map?) ?? <String, dynamic>{});
    final Map<String, dynamic> sum = Map<String, dynamic>.from((j['summary'] as Map?) ?? <String, dynamic>{});
    return ApiPage<T>(
      _maps(j['data']).map(item).toList(),
      currentPage: _int(meta['current_page']),
      lastPage: _int(meta['last_page']),
      totalPaise: _int(sum['total_paise']),
      count: _int(sum['count']),
    );
  }

  final List<T> items;
  final int currentPage;
  final int lastPage;

  /// For purchases: total of the (not cancelled) ones in the range.
  final int totalPaise;
  final int count;

  bool get hasMore => currentPage < lastPage;
}

/// A credit note (sale return) or debit note (purchase return).
class ReturnNote {
  const ReturnNote({
    required this.id,
    required this.isCreditNote,
    required this.noteNo,
    required this.date,
    this.createdAt,
    this.againstNo,
    this.againstDate,
    this.partyId,
    this.partyName,
    this.partyGstin,
    this.placeOfSupply,
    this.refundMode,
    this.reason,
    required this.isInterState,
    required this.seller,
    required this.subtotalPaise,
    required this.discountPaise,
    required this.taxablePaise,
    required this.cgstPaise,
    required this.sgstPaise,
    required this.igstPaise,
    required this.roundOffPaise,
    required this.totalPaise,
    required this.items,
    required this.taxSummary,
  });

  factory ReturnNote.fromJson(Map<String, dynamic> j) {
    final bool credit = j['kind'] == 'credit_note';
    return ReturnNote(
      id: _str(j['id']) ?? '',
      isCreditNote: credit,
      noteNo: _str(j['note_no']) ?? '',
      date: _date(j['return_date']) ?? DateTime.now(),
      createdAt: _date(j['created_at']),
      againstNo: _str(credit ? j['bill_invoice_no'] : j['supplier_invoice_no']),
      againstDate: _date(j['bill_date']),
      partyId: _str(j['party_id']),
      partyName: _str(j['party_name']),
      partyGstin: _str(j['party_gstin']),
      placeOfSupply: _str(j['place_of_supply']),
      refundMode: _str(j['refund_mode']),
      reason: _str(j['reason']),
      isInterState: j['is_inter_state'] == true,
      seller: Map<String, dynamic>.from((j['seller'] as Map?) ?? <String, dynamic>{}),
      subtotalPaise: _int(j['subtotal_paise']),
      discountPaise: _int(j['discount_paise']),
      taxablePaise: _int(j['taxable_paise']),
      cgstPaise: _int(j['cgst_paise']),
      sgstPaise: _int(j['sgst_paise']),
      igstPaise: _int(j['igst_paise']),
      roundOffPaise: _int(j['round_off_paise']),
      totalPaise: _int(j['total_paise']),
      items: _maps(j['items']).map(ReturnNoteItem.fromJson).toList(),
      taxSummary: _maps(j['tax_summary'])
          .map((Map<String, dynamic> t) => (
                rateBp: _int(t['gst_rate_bp']),
                taxablePaise: _int(t['taxable_paise']),
                taxPaise: _int(t['cgst_paise']) + _int(t['sgst_paise']) + _int(t['igst_paise']),
              ))
          .toList(),
    );
  }

  final String id;

  /// Credit note (customer returned goods) or debit note (goods sent back to a supplier).
  final bool isCreditNote;
  final String noteNo;
  final DateTime date;
  final DateTime? createdAt;

  /// The bill's invoice no. / the supplier's invoice no.
  final String? againstNo;
  final DateTime? againstDate;
  final String? partyId;
  final String? partyName;
  final String? partyGstin;
  final String? placeOfSupply;

  /// Credit notes: credit (on account) | cash | upi | card | bank.
  final String? refundMode;
  final String? reason;
  final bool isInterState;
  final Map<String, dynamic> seller;
  final int subtotalPaise;
  final int discountPaise;
  final int taxablePaise;
  final int cgstPaise;
  final int sgstPaise;
  final int igstPaise;
  final int roundOffPaise;
  final int totalPaise;
  final List<ReturnNoteItem> items;
  final List<({int rateBp, int taxablePaise, int taxPaise})> taxSummary;

  String get title => isCreditNote ? 'Credit note' : 'Debit note';
  int get taxPaise => cgstPaise + sgstPaise + igstPaise;
}

class ReturnNoteItem {
  const ReturnNoteItem({
    required this.name,
    this.hsn,
    this.batchNo,
    this.expiryDate,
    required this.qty,
    required this.ratePaise,
    required this.discountBp,
    required this.gstRateBp,
    required this.taxablePaise,
    required this.taxPaise,
    required this.totalPaise,
  });

  factory ReturnNoteItem.fromJson(Map<String, dynamic> j) => ReturnNoteItem(
        name: _str(j['name']) ?? '',
        hsn: _str(j['hsn']),
        batchNo: _str(j['batch_no']),
        expiryDate: _date(j['expiry_date']),
        qty: _int(j['qty']),
        ratePaise: _int(j['rate_paise']),
        discountBp: _int(j['discount_bp']),
        gstRateBp: _int(j['gst_rate_bp']),
        taxablePaise: _int(j['taxable_paise']),
        taxPaise: _int(j['cgst_paise']) + _int(j['sgst_paise']) + _int(j['igst_paise']),
        totalPaise: _int(j['total_paise']),
      );

  final String name;
  final String? hsn;
  final String? batchNo;
  final DateTime? expiryDate;
  final int qty;

  /// Credit notes: MRP (GST included); debit notes: purchase rate (before GST).
  final int ratePaise;
  final int discountBp;
  final int gstRateBp;
  final int taxablePaise;
  final int taxPaise;
  final int totalPaise;
}

/// A short reference to a credit note on a bill.
class NoteRef {
  const NoteRef({required this.id, required this.noteNo, required this.date, required this.totalPaise});

  factory NoteRef.fromJson(Map<String, dynamic> j) => NoteRef(
        id: _str(j['id']) ?? '',
        noteNo: _str(j['note_no']) ?? '',
        date: _date(j['return_date']) ?? DateTime.now(),
        totalPaise: _int(j['total_paise']),
      );

  final String id;
  final String noteNo;
  final DateTime date;
  final int totalPaise;
}
