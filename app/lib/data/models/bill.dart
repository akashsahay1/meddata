import 'package:intl/intl.dart';

import '../../core/inr.dart';
import '../../domain/gst.dart';
import '../../domain/pack_size.dart';
import 'accounting.dart' show NoteRef;

/// How a bill was paid. Credit = the customer pays later (udhaar).
enum PaymentMode {
  cash('Cash'),
  upi('UPI'),
  card('Card'),
  credit('Credit');

  const PaymentMode(this.label);
  final String label;

  static PaymentMode from(String? v) => PaymentMode.values
      .firstWhere((PaymentMode m) => m.name == v, orElse: () => PaymentMode.cash);
}

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
  // A plain date is a calendar day; a timestamp is shown in local time.
  return s.length <= 10 ? DateTime(d.year, d.month, d.day) : d.toLocal();
}

/// The shop's details as printed on an invoice (copied onto each bill).
class SellerDetails {
  const SellerDetails({
    required this.name,
    this.legalName,
    this.address,
    this.phone,
    this.gstin,
    this.stateCode,
    this.drugLicenseNo,
    this.email,
    this.pharmacistName,
    this.pharmacistRegNo,
    this.pharmacistRegDate,
    this.pharmacistQualification,
    this.fssaiNo,
  });

  factory SellerDetails.fromJson(Map<String, dynamic> j) => SellerDetails(
        name: _str(j['name']) ?? '',
        legalName: _str(j['legal_name']),
        address: _str(j['address']),
        phone: _str(j['phone']),
        gstin: _str(j['gstin']),
        stateCode: _str(j['state_code']),
        drugLicenseNo: _str(j['drug_license_no']),
        email: _str(j['email']),
        pharmacistName: _str(j['pharmacist_name']),
        pharmacistRegNo: _str(j['pharmacist_reg_no']),
        pharmacistRegDate: _date(j['pharmacist_reg_date']),
        pharmacistQualification: _str(j['pharmacist_qualification']),
        fssaiNo: _str(j['fssai_no']),
      );

  final String name;
  final String? legalName;
  final String? address;
  final String? phone;
  final String? gstin;
  final String? stateCode;
  final String? drugLicenseNo;
  final String? email;
  final String? pharmacistName;
  final String? pharmacistRegNo;
  final DateTime? pharmacistRegDate;
  final String? pharmacistQualification;
  final String? fssaiNo;

  /// Name for the invoice header: the legal name when set.
  String get displayName => legalName ?? name;

  /// The optional header lines an invoice prints under the licence no.,
  /// only for what the shop filled in.
  List<String> get extraInvoiceLines {
    final String? regDate =
        pharmacistRegDate == null ? null : DateFormat('dd MMM yyyy').format(pharmacistRegDate!);
    final String who = <String?>[
      pharmacistName,
      if (pharmacistQualification != null) pharmacistName == null ? pharmacistQualification : '($pharmacistQualification)',
    ].whereType<String>().join(' ');
    return <String>[
      if (fssaiNo != null) 'FSSAI Lic. No.: $fssaiNo',
      if (email != null) 'Email: $email',
      if (who.isNotEmpty) 'Pharmacist: $who',
      if (pharmacistRegNo != null)
        'Reg. No.: $pharmacistRegNo${regDate == null ? '' : ' dt. $regDate'}'
      else if (regDate != null)
        'Reg. date: $regDate',
    ];
  }
}

class BillItem {
  const BillItem({
    this.id = 0,
    required this.lineNo,
    required this.productId,
    required this.batchId,
    required this.name,
    this.hsn,
    this.unit,
    this.packSize = 1,
    this.batchNo,
    this.expiryDate,
    required this.qty,
    required this.mrpPaise,
    required this.ratePaise,
    required this.discountBp,
    required this.discountPaise,
    required this.gstRateBp,
    required this.taxablePaise,
    required this.cgstPaise,
    required this.sgstPaise,
    required this.igstPaise,
    required this.totalPaise,
    this.returnedQty = 0,
  });

  factory BillItem.fromJson(Map<String, dynamic> j) => BillItem(
        id: _int(j['id']),
        lineNo: _int(j['line_no']),
        productId: _str(j['product_id']) ?? '',
        batchId: _str(j['batch_id']) ?? '',
        name: _str(j['name']) ?? '',
        hsn: _str(j['hsn']),
        unit: _str(j['unit']),
        packSize: _int(j['pack_size']) < 1 ? 1 : _int(j['pack_size']),
        batchNo: _str(j['batch_no']),
        expiryDate: _date(j['expiry_date']),
        qty: _int(j['qty_units']),
        mrpPaise: _int(j['mrp_paise']),
        ratePaise: _int(j['rate_paise']),
        discountBp: _int(j['discount_bp']),
        discountPaise: _int(j['discount_paise']),
        gstRateBp: _int(j['gst_rate_bp']),
        taxablePaise: _int(j['taxable_paise']),
        cgstPaise: _int(j['cgst_paise']),
        sgstPaise: _int(j['sgst_paise']),
        igstPaise: _int(j['igst_paise']),
        totalPaise: _int(j['total_paise']),
        returnedQty: _int(j['returned_qty']),
      );

  /// Server id of the line (sale returns refer to it).
  final int id;
  final int lineNo;
  final String productId;
  final String batchId;
  final String name;
  final String? hsn;
  final String? unit;

  /// Pieces per pack of the product when the bill was made; 1 when not set.
  final int packSize;
  final String? batchNo;
  final DateTime? expiryDate;
  final int qty;
  final int mrpPaise;
  final int ratePaise;
  final int discountBp;
  final int discountPaise;
  final int gstRateBp;
  final int taxablePaise;
  final int cgstPaise;
  final int sgstPaise;
  final int igstPaise;
  final int totalPaise;

  /// Units already returned on credit notes.
  final int returnedQty;

  int get returnableQty => qty - returnedQty;

  /// Pieces [mrpPaise] covers (a strip, or one unit).
  int get pricePack => PackSize.pricePack(unit ?? '', packSize);
}

/// Taxable value and tax at one GST rate (the invoice's tax summary).
class BillTaxRow {
  const BillTaxRow({
    required this.gstRateBp,
    required this.taxablePaise,
    required this.cgstPaise,
    required this.sgstPaise,
    required this.igstPaise,
  });

  factory BillTaxRow.fromJson(Map<String, dynamic> j) => BillTaxRow(
        gstRateBp: _int(j['gst_rate_bp']),
        taxablePaise: _int(j['taxable_paise']),
        cgstPaise: _int(j['cgst_paise']),
        sgstPaise: _int(j['sgst_paise']),
        igstPaise: _int(j['igst_paise']),
      );

  final int gstRateBp;
  final int taxablePaise;
  final int cgstPaise;
  final int sgstPaise;
  final int igstPaise;

  int get taxPaise => cgstPaise + sgstPaise + igstPaise;
}

/// A GST invoice as the server created it (the source of truth).
class Bill {
  const Bill({
    required this.id,
    required this.invoiceNo,
    required this.billDate,
    this.createdAt,
    required this.status,
    required this.paymentMode,
    this.partyId,
    this.customerName,
    this.customerPhone,
    this.customerGstin,
    this.customerStateCode,
    this.customerAddress,
    this.placeOfSupply,
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
    this.cancelledAt,
    this.cancelReason,
    required this.items,
    required this.taxSummary,
    this.returns = const <NoteRef>[],
    int? paidPaise,
    int? balancePaise,
    int? receivedPaise,
    this.receivedMode,
    this.editedAt,
  })  : paidPaise = paidPaise ?? (paymentMode == PaymentMode.credit ? 0 : totalPaise),
        balancePaise = balancePaise ??
            (paymentMode == PaymentMode.credit && status != 'cancelled' ? totalPaise : 0),
        receivedPaise = receivedPaise ?? (paymentMode == PaymentMode.credit ? 0 : totalPaise);

  factory Bill.fromJson(Map<String, dynamic> j) => Bill(
        id: _str(j['id']) ?? '',
        invoiceNo: _str(j['invoice_no']) ?? '',
        billDate: _date(j['bill_date']) ?? DateTime.now(),
        createdAt: _date(j['created_at']),
        status: _str(j['status']) ?? 'final',
        paymentMode: PaymentMode.from(_str(j['payment_mode'])),
        partyId: _str(j['party_id']),
        customerName: _str(j['customer_name']),
        customerPhone: _str(j['customer_phone']),
        customerGstin: _str(j['customer_gstin']),
        customerStateCode: _str(j['customer_state_code']),
        customerAddress: _str(j['customer_address']),
        placeOfSupply: _str(j['place_of_supply']),
        isInterState: j['is_inter_state'] == true,
        seller: SellerDetails.fromJson(
            Map<String, dynamic>.from((j['seller'] as Map?) ?? <String, dynamic>{})),
        subtotalPaise: _int(j['subtotal_paise']),
        discountPaise: _int(j['discount_paise']),
        taxablePaise: _int(j['taxable_paise']),
        cgstPaise: _int(j['cgst_paise']),
        sgstPaise: _int(j['sgst_paise']),
        igstPaise: _int(j['igst_paise']),
        roundOffPaise: _int(j['round_off_paise']),
        totalPaise: _int(j['total_paise']),
        cancelledAt: _date(j['cancelled_at']),
        cancelReason: _str(j['cancel_reason']),
        items: <BillItem>[
          for (final Object? i in (j['items'] as List<dynamic>?) ?? <dynamic>[])
            BillItem.fromJson(Map<String, dynamic>.from(i! as Map)),
        ],
        taxSummary: <BillTaxRow>[
          for (final Object? t in (j['tax_summary'] as List<dynamic>?) ?? <dynamic>[])
            BillTaxRow.fromJson(Map<String, dynamic>.from(t! as Map)),
        ],
        returns: <NoteRef>[
          for (final Object? r in (j['returns'] as List<dynamic>?) ?? <dynamic>[])
            NoteRef.fromJson(Map<String, dynamic>.from(r! as Map)),
        ],
        paidPaise: (j['paid_paise'] as num?)?.toInt(),
        balancePaise: (j['balance_paise'] as num?)?.toInt(),
        receivedPaise: (j['received_paise'] as num?)?.toInt(),
        receivedMode: j['received_mode'] == null ? null : PaymentMode.from(_str(j['received_mode'])),
        editedAt: _date(j['edited_at']),
      );

  final String id;
  final String invoiceNo;
  final DateTime billDate;
  final DateTime? createdAt;
  final String status;
  final PaymentMode paymentMode;

  /// The customer's account, when the bill was made for one.
  final String? partyId;
  final String? customerName;
  final String? customerPhone;
  final String? customerGstin;
  final String? customerStateCode;
  final String? customerAddress;
  final String? placeOfSupply;
  final bool isInterState;
  final SellerDetails seller;
  final int subtotalPaise;
  final int discountPaise;
  final int taxablePaise;
  final int cgstPaise;
  final int sgstPaise;
  final int igstPaise;
  final int roundOffPaise;
  final int totalPaise;
  final DateTime? cancelledAt;
  final String? cancelReason;
  final List<BillItem> items;
  final List<BillTaxRow> taxSummary;

  /// Credit notes against this bill (when loaded on its own).
  final List<NoteRef> returns;

  /// Money received for the bill so far (at the counter and later).
  final int paidPaise;

  /// Still to be paid (only a credit bill has one).
  final int balancePaise;

  /// Taken at the counter when the bill was made, and how ([receivedMode]
  /// is null when nothing was).
  final int receivedPaise;
  final PaymentMode? receivedMode;

  /// When the bill was last edited in place (null = never).
  final DateTime? editedAt;

  bool get isCancelled => status == 'cancelled';
  bool get hasBalance => !isCancelled && balancePaise > 0;

  /// How it was paid, for the invoice: "UPI", "Part paid", "Credit" (nothing
  /// paid yet) or "Paid" (a credit bill settled since).
  String get paymentLabel {
    if (paymentMode != PaymentMode.credit) return paymentMode.label;
    if (isCancelled) return paymentMode.label;
    if (!hasBalance) return 'Paid';
    return paidPaise > 0 ? 'Part paid' : 'Credit';
  }

  /// "Paid" and "Balance due" lines for an invoice with money still due.
  List<(String, String)> get balanceLines => hasBalance
      ? <(String, String)>[('Paid', Inr.format(paidPaise)), ('Balance due', Inr.format(balancePaise))]
      : const <(String, String)>[];

  /// "Part paid · ₹124.00 due" / "Credit - to be paid" / "Paid · UPI".
  String get paymentStatus => paymentStatusOf(
      cancelled: isCancelled, mode: paymentMode, paid: paidPaise, balance: balancePaise);

  /// Can be edited in place: not cancelled and nothing returned against it.
  bool get canEdit =>
      !isCancelled && returns.isEmpty && items.every((BillItem i) => i.returnedQty == 0);

  /// Some units can still be returned.
  bool get canReturn => !isCancelled && items.any((BillItem i) => i.returnableQty > 0);
  int get taxPaise => cgstPaise + sgstPaise + igstPaise;
  int get unitCount => items.fold(0, (int s, BillItem i) => s + i.qty);

  /// "27 - Maharashtra".
  String? get placeOfSupplyLabel =>
      placeOfSupply == null ? null : GstStates.label(placeOfSupply!);
}

/// One row of the bills list.
class BillSummary {
  const BillSummary({
    required this.id,
    required this.invoiceNo,
    required this.billDate,
    this.createdAt,
    required this.status,
    required this.paymentMode,
    this.customerName,
    this.customerPhone,
    required this.totalPaise,
    required this.itemsCount,
    this.paidPaise = 0,
    this.balancePaise = 0,
  });

  factory BillSummary.fromJson(Map<String, dynamic> j) => BillSummary(
        id: _str(j['id']) ?? '',
        invoiceNo: _str(j['invoice_no']) ?? '',
        billDate: _date(j['bill_date']) ?? DateTime.now(),
        createdAt: _date(j['created_at']),
        status: _str(j['status']) ?? 'final',
        paymentMode: PaymentMode.from(_str(j['payment_mode'])),
        customerName: _str(j['customer_name']),
        customerPhone: _str(j['customer_phone']),
        totalPaise: _int(j['total_paise']),
        itemsCount: _int(j['items_count']),
        paidPaise: _int(j['paid_paise']),
        balancePaise: _int(j['balance_paise']),
      );

  final String id;
  final String invoiceNo;
  final DateTime billDate;
  final DateTime? createdAt;
  final String status;
  final PaymentMode paymentMode;
  final String? customerName;
  final String? customerPhone;
  final int totalPaise;
  final int itemsCount;
  final int paidPaise;
  final int balancePaise;

  bool get isCancelled => status == 'cancelled';
  bool get hasBalance => !isCancelled && balancePaise > 0;
}

/// How a bill stands: cancelled, paid, part paid or all on credit.
String paymentStatusOf(
    {required bool cancelled, required PaymentMode mode, required int paid, required int balance}) {
  if (cancelled) return 'Cancelled';
  if (balance > 0) return paid > 0 ? 'Part paid · ${_rupees(balance)} due' : 'Credit - to be paid';
  if (mode == PaymentMode.credit) return 'Paid';
  return 'Paid · ${mode.label}';
}

String _rupees(int paise) => Inr.format(paise);

/// A page of bills plus totals for the whole date range.
class BillPage {
  const BillPage({
    required this.bills,
    required this.currentPage,
    required this.lastPage,
    required this.total,
    required this.finalCount,
    required this.finalTotalPaise,
    required this.cancelledCount,
    this.dueCount = 0,
    this.duePaise = 0,
  });

  factory BillPage.fromJson(Map<String, dynamic> j) {
    final Map<String, dynamic> meta =
        Map<String, dynamic>.from((j['meta'] as Map?) ?? <String, dynamic>{});
    final Map<String, dynamic> sum =
        Map<String, dynamic>.from((j['summary'] as Map?) ?? <String, dynamic>{});
    return BillPage(
      bills: <BillSummary>[
        for (final Object? b in (j['data'] as List<dynamic>?) ?? <dynamic>[])
          BillSummary.fromJson(Map<String, dynamic>.from(b! as Map)),
      ],
      currentPage: _int(meta['current_page']),
      lastPage: _int(meta['last_page']),
      total: _int(meta['total']),
      finalCount: _int(sum['count']),
      finalTotalPaise: _int(sum['total_paise']),
      cancelledCount: _int(sum['cancelled_count']),
      dueCount: _int(sum['due_count']),
      duePaise: _int(sum['due_paise']),
    );
  }

  final List<BillSummary> bills;
  final int currentPage;
  final int lastPage;
  final int total;

  /// Bills that count (not cancelled) in the range, and their total.
  final int finalCount;
  final int finalTotalPaise;
  final int cancelledCount;

  /// Credit bills in the range with money still to be paid, and how much.
  final int dueCount;
  final int duePaise;

  bool get hasMore => currentPage < lastPage;
}

/// The shop's invoice details (GET/PATCH /shops/current).
class ShopProfile {
  const ShopProfile({
    required this.name,
    this.legalName,
    this.gstin,
    this.stateCode,
    this.drugLicenseNo,
    this.address,
    this.phone,
    this.invoicePrefix,
    this.defaultGstRateBp = 500,
    this.email,
    this.pharmacistName,
    this.pharmacistRegNo,
    this.pharmacistRegDate,
    this.pharmacistQualification,
    this.fssaiNo,
  });

  factory ShopProfile.fromJson(Map<String, dynamic> j) => ShopProfile(
        name: _str(j['name']) ?? '',
        legalName: _str(j['legal_name']),
        gstin: _str(j['gstin']),
        stateCode: _str(j['state_code']),
        drugLicenseNo: _str(j['drug_license_no']),
        address: _str(j['address']),
        phone: _str(j['phone']),
        invoicePrefix: _str(j['invoice_prefix']),
        defaultGstRateBp: (j['default_gst_rate_bp'] as num?)?.toInt() ?? 500,
        email: _str(j['email']),
        pharmacistName: _str(j['pharmacist_name']),
        pharmacistRegNo: _str(j['pharmacist_reg_no']),
        pharmacistRegDate: _date(j['pharmacist_reg_date']),
        pharmacistQualification: _str(j['pharmacist_qualification']),
        fssaiNo: _str(j['fssai_no']),
      );

  final String name;
  final String? legalName;
  final String? gstin;
  final String? stateCode;
  final String? drugLicenseNo;
  final String? address;
  final String? phone;
  final String? invoicePrefix;

  /// GST rate for products that have none set.
  final int defaultGstRateBp;
  final String? email;
  final String? pharmacistName;
  final String? pharmacistRegNo;
  final DateTime? pharmacistRegDate;
  final String? pharmacistQualification;
  final String? fssaiNo;

  /// Enough for a proper tax invoice (GSTIN, state, address).
  bool get invoiceReady =>
      gstin != null && stateCode != null && (address ?? '').isNotEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'legal_name': legalName,
        'gstin': gstin,
        'state_code': stateCode,
        'drug_license_no': drugLicenseNo,
        'address': address,
        'phone': phone,
        'invoice_prefix': invoicePrefix,
        'default_gst_rate_bp': defaultGstRateBp,
        'email': email,
        'pharmacist_name': pharmacistName,
        'pharmacist_reg_no': pharmacistRegNo,
        'pharmacist_reg_date':
            pharmacistRegDate == null ? null : DateFormat('yyyy-MM-dd').format(pharmacistRegDate!),
        'pharmacist_qualification': pharmacistQualification,
        'fssai_no': fssaiNo,
      };
}
