import '../../domain/gst.dart';

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
  });

  factory SellerDetails.fromJson(Map<String, dynamic> j) => SellerDetails(
        name: _str(j['name']) ?? '',
        legalName: _str(j['legal_name']),
        address: _str(j['address']),
        phone: _str(j['phone']),
        gstin: _str(j['gstin']),
        stateCode: _str(j['state_code']),
        drugLicenseNo: _str(j['drug_license_no']),
      );

  final String name;
  final String? legalName;
  final String? address;
  final String? phone;
  final String? gstin;
  final String? stateCode;
  final String? drugLicenseNo;

  /// Name for the invoice header: the legal name when set.
  String get displayName => legalName ?? name;
}

class BillItem {
  const BillItem({
    required this.lineNo,
    required this.productId,
    required this.batchId,
    required this.name,
    this.hsn,
    this.unit,
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
  });

  factory BillItem.fromJson(Map<String, dynamic> j) => BillItem(
        lineNo: _int(j['line_no']),
        productId: _str(j['product_id']) ?? '',
        batchId: _str(j['batch_id']) ?? '',
        name: _str(j['name']) ?? '',
        hsn: _str(j['hsn']),
        unit: _str(j['unit']),
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
      );

  final int lineNo;
  final String productId;
  final String batchId;
  final String name;
  final String? hsn;
  final String? unit;
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
  });

  factory Bill.fromJson(Map<String, dynamic> j) => Bill(
        id: _str(j['id']) ?? '',
        invoiceNo: _str(j['invoice_no']) ?? '',
        billDate: _date(j['bill_date']) ?? DateTime.now(),
        createdAt: _date(j['created_at']),
        status: _str(j['status']) ?? 'final',
        paymentMode: PaymentMode.from(_str(j['payment_mode'])),
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
      );

  final String id;
  final String invoiceNo;
  final DateTime billDate;
  final DateTime? createdAt;
  final String status;
  final PaymentMode paymentMode;
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

  bool get isCancelled => status == 'cancelled';
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

  bool get isCancelled => status == 'cancelled';
}

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
      };
}
