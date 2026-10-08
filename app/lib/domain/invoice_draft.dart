import 'dart:math' as math;

import '../core/constants.dart';
import '../data/models/medicine.dart';
import 'medicine_name_key.dart';
import 'pack_size.dart';
import 'product_stock.dart';

export 'pack_size.dart' show kPieceUnits;

/// One line of a scanned purchase invoice, as the user reviews it before it
/// is added to stock. Quantities and prices are per pack, as printed on the
/// bill; [toMedicine] turns them into a batch in the product's own unit.
class InvoiceDraftLine {
  const InvoiceDraftLine({
    required this.id,
    required this.name,
    this.manufacturer = '',
    this.pack = '',
    this.batchNo = '',
    this.expiry,
    this.mfgDate,
    this.quantity = 0,
    this.freeQuantity = 0,
    this.mrp = 0,
    this.rate = 0,
    this.discountPercent = 0,
    this.gstPercent,
    this.hsn = '',
    this.barcode = '',
    this.unit = 'Strips',
    this.unitsPerPack = 1,
    this.product,
    this.asNew = false,
  });

  /// Stable id within the draft (list keys, duplicate flags).
  final String id;
  final String name;
  final String manufacturer;

  /// Pack as printed, e.g. "15's", "1x10", "100ML".
  final String pack;
  final String batchNo;
  final DateTime? expiry;
  final DateTime? mfgDate;

  /// Billed and free packs.
  final int quantity;
  final int freeQuantity;

  /// MRP and purchase rate per pack (rate before discount and GST).
  final double mrp;
  final double rate;
  final double discountPercent;
  final double? gstPercent;
  final String hsn;
  final String barcode;

  /// Unit of a new medicine (a batch of [target] keeps the product's unit).
  final String unit;

  /// Pieces in one pack: used when the stock unit counts pieces.
  final int unitsPerPack;

  /// The shop's medicine this line most likely is (null: none found).
  final ProductStock? product;

  /// The user chose to add it as a new medicine despite the match.
  final bool asNew;

  /// The medicine this line adds a batch to; null = a new medicine.
  ProductStock? get target => asNew ? null : product;

  bool get isNewProduct => target == null;

  /// The unit stock is counted in once added.
  String get stockUnit => target?.unit ?? unit;

  /// Whether stock is counted per piece (tablet, ml) rather than per pack.
  bool get countsPieces => kPieceUnits.contains(stockUnit) && unitsPerPack > 1;

  int get _perPack => countsPieces ? unitsPerPack : 1;

  /// Stock this line adds, in [stockUnit].
  int get stockQuantity => (quantity + freeQuantity) * _perPack;

  /// Purchase rate per pack after the line discount (GST not included).
  double get netRate => rate * (1 - discountPercent / 100);

  /// Pieces a stored price covers: the medicine's own pack when it applies
  /// (a known medicine's, or this line's for a new one), else one unit.
  int get pricePack =>
      PackSize.pricePack(stockUnit, target?.packSize ?? unitsPerPack);

  /// MRP and cost as stored on the batch: per [pricePack] pieces. With the
  /// pack as printed this is the printed price itself (no division).
  double get mrpPerUnit => _round2(mrp * pricePack / _perPack);
  double get costPerUnit => _round2(netRate * pricePack / _perPack);

  /// What must be fixed before the line can be added.
  List<String> get problems => <String>[
    if (name.trim().isEmpty) 'Name missing',
    if (expiry == null) 'Expiry date missing',
    if (quantity + freeQuantity <= 0) 'Quantity missing',
    if (expiry != null && mfgDate != null && !mfgDate!.isBefore(expiry!))
      'Expiry must be after the manufacture date',
  ];

  bool get isValid => problems.isEmpty;

  /// Worth a second look, but doesn't block adding.
  List<String> warnings(DateTime today) => <String>[
    if (batchNo.trim().isEmpty) 'No batch number',
    if (mrp <= 0) 'No MRP',
    if (rate <= 0) 'No purchase rate',
    if (expiry != null &&
        expiry!.isBefore(DateTime(today.year, today.month, today.day)))
      'Already expired',
  ];

  /// The batch to add, built like the manual Add screen builds one: for a
  /// [target] it carries that product's name, unit and brand, so the
  /// repository files it as a new batch of it; otherwise a new medicine.
  /// Only add [isValid] lines (a missing expiry falls back to [now] so the
  /// list can be counted while it is still being fixed).
  Medicine toMedicine({required String id, required DateTime now}) {
    final ProductStock? p = target;
    return Medicine(
      id: id,
      name: p?.name ?? name.trim(),
      brand: p?.brand ?? manufacturer.trim(),
      category: p?.category ?? 'Uncategorised',
      batchNo: batchNo.trim(),
      barcode: p?.first.barcode ?? barcode.trim(),
      quantity: stockQuantity,
      unit: stockUnit,
      // A new medicine remembers its pack as printed, so stock can later be
      // entered and sold as strips + loose; a known one keeps its own.
      packSize: p?.packSize ?? unitsPerPack,
      lowStockThreshold:
          p?.lowStockThreshold ?? AppConstants.defaultLowStockThreshold,
      purchasePrice: costPerUnit,
      sellingPrice: mrpPerUnit,
      mfgDate: mfgDate,
      expiryDate: expiry ?? now,
      notes: p?.first.notes ?? '',
      createdAt: now,
      updatedAt: now,
      // GST details are the product's: a known medicine keeps its own and
      // only takes the bill's where it has none.
      hsn: (p != null && p.first.hsn.trim().isNotEmpty)
          ? p.first.hsn
          : hsn.trim(),
      gstRateBp: p?.first.gstRateBp ?? gstRateBp,
    );
  }

  /// [gstPercent] as basis points (12% -> 1200); null when the bill shows
  /// none or an impossible rate, so the shop's default rate applies.
  int? get gstRateBp {
    final double? g = gstPercent;
    if (g == null || g.isNaN || g < 0 || g > 100) return null;
    return (g * 100).round();
  }

  InvoiceDraftLine copyWith({
    String? name,
    String? manufacturer,
    String? batchNo,
    DateTime? expiry,
    DateTime? mfgDate,
    bool clearMfgDate = false,
    int? quantity,
    int? freeQuantity,
    double? mrp,
    double? rate,
    double? discountPercent,
    String? unit,
    int? unitsPerPack,
    ProductStock? product,
    bool? asNew,
  }) {
    return InvoiceDraftLine(
      id: id,
      name: name ?? this.name,
      manufacturer: manufacturer ?? this.manufacturer,
      pack: pack,
      batchNo: batchNo ?? this.batchNo,
      expiry: expiry ?? this.expiry,
      mfgDate: clearMfgDate ? null : (mfgDate ?? this.mfgDate),
      quantity: quantity ?? this.quantity,
      freeQuantity: freeQuantity ?? this.freeQuantity,
      mrp: mrp ?? this.mrp,
      rate: rate ?? this.rate,
      discountPercent: discountPercent ?? this.discountPercent,
      gstPercent: gstPercent,
      hsn: hsn,
      barcode: barcode,
      unit: unit ?? this.unit,
      unitsPerPack: unitsPerPack ?? this.unitsPerPack,
      product: product ?? this.product,
      asNew: asNew ?? this.asNew,
    );
  }

  static double _round2(double v) => (v * 100).roundToDouble() / 100;
}

/// A scanned purchase invoice under review.
class InvoiceDraft {
  const InvoiceDraft({
    this.supplierName = '',
    this.supplierGstin = '',
    this.invoiceNo = '',
    this.invoiceDate,
    this.notes = '',
    this.lines = const <InvoiceDraftLine>[],
  });

  final String supplierName;
  final String supplierGstin;
  final String invoiceNo;
  final DateTime? invoiceDate;

  /// The reader's note on what to double-check (may be empty).
  final String notes;
  final List<InvoiceDraftLine> lines;

  InvoiceDraft copyWith({List<InvoiceDraftLine>? lines}) => InvoiceDraft(
    supplierName: supplierName,
    supplierGstin: supplierGstin,
    invoiceNo: invoiceNo,
    invoiceDate: invoiceDate,
    notes: notes,
    lines: lines ?? this.lines,
  );
}

/// Turns the server's scan result (`GET /invoices/scan/{id}` -> `result`)
/// into draft lines. Pure: no I/O, so it is unit tested directly.
class InvoiceDraftMapper {
  InvoiceDraftMapper._();

  /// [products] are the shop's medicines on this device: each line is linked
  /// to the one it most likely is (see [matchProduct]).
  static InvoiceDraft fromResult(
    Map<String, dynamic> result, {
    List<ProductStock> products = const <ProductStock>[],
  }) {
    final List<InvoiceDraftLine> lines = <InvoiceDraftLine>[];
    final Object? items = result['items'];
    if (items is List) {
      for (final Object? item in items) {
        if (item is! Map<String, dynamic>) continue;
        final InvoiceDraftLine? line = _line(
          'l${lines.length}',
          item,
          products,
        );
        if (line != null) lines.add(line);
      }
    }
    return InvoiceDraft(
      supplierName: _str(result['supplier_name']),
      supplierGstin: _str(result['supplier_gstin']),
      invoiceNo: _str(result['invoice_no']),
      invoiceDate: parseDate(result['invoice_date']),
      notes: _str(result['notes']),
      lines: lines,
    );
  }

  static InvoiceDraftLine? _line(
    String id,
    Map<String, dynamic> j,
    List<ProductStock> products,
  ) {
    final String name = _str(j['product_name']);
    if (name.isEmpty) return null;
    final Object? m = j['match'];
    final Map<String, dynamic> match = m is Map<String, dynamic>
        ? m
        : const <String, dynamic>{};
    String manufacturer = _str(j['manufacturer']);
    if (manufacturer.isEmpty) manufacturer = _str(match['master_manufacturer']);
    final String pack = _str(j['pack']);
    final String barcode = _str(j['barcode']);
    final ProductStock? product = matchProduct(
      name: name,
      manufacturer: manufacturer,
      barcode: barcode,
      suggestedId: _str(match['product_id']),
      products: products,
    );
    return InvoiceDraftLine(
      id: id,
      name: name,
      manufacturer: manufacturer,
      pack: pack,
      batchNo: _str(j['batch_no']),
      expiry: parseDate(j['expiry_date'], endOfMonth: true),
      mfgDate: parseDate(j['mfg_date']),
      quantity: _int(j['quantity']),
      freeQuantity: _int(j['free_quantity']),
      mrp: _num(j['mrp']) ?? 0,
      rate: _num(j['purchase_rate']) ?? 0,
      discountPercent: (_num(j['discount_percent']) ?? 0)
          .clamp(0.0, 100.0)
          .toDouble(),
      gstPercent: _num(j['gst_percent']),
      hsn: _str(j['hsn']),
      barcode: barcode,
      unit: product?.unit ?? guessUnit(name, pack),
      // The shop's own pack size wins over the invoice's pack text.
      unitsPerPack: product != null && product.packSize > 1
          ? product.packSize
          : unitsPerPack(pack),
      product: product,
    );
  }

  /// The shop's medicine an invoice line most likely is: the server's
  /// suggestion when this device has it, else the same barcode, the same
  /// name, or a loose name match ([MedicineNameKey]). With several
  /// candidates, the one whose brand matches [manufacturer] wins.
  static ProductStock? matchProduct({
    required String name,
    required List<ProductStock> products,
    String manufacturer = '',
    String barcode = '',
    String suggestedId = '',
  }) {
    if (suggestedId.isNotEmpty) {
      for (final ProductStock p in products) {
        if (p.productId == suggestedId) return p;
      }
    }
    final String code = barcode.trim().toLowerCase();
    if (code.isNotEmpty) {
      for (final ProductStock p in products) {
        if (p.first.barcode.trim().toLowerCase() == code) return p;
      }
    }
    final String norm = _norm(name);
    List<ProductStock> hits = products
        .where((ProductStock p) => _norm(p.name) == norm)
        .toList();
    if (hits.isEmpty) {
      final MedicineNameKey want = MedicineNameKey.of(name);
      hits = products
          .where((ProductStock p) => want.matches(MedicineNameKey.of(p.name)))
          .toList();
    }
    if (hits.isEmpty) return null;
    final String maker = _norm(manufacturer);
    if (maker.isNotEmpty) {
      for (final ProductStock p in hits) {
        final String brand = _norm(p.brand);
        if (brand.isNotEmpty &&
            (brand.startsWith(maker) || maker.startsWith(brand))) {
          return p;
        }
      }
    }
    return hits.first;
  }

  /// Pieces in one pack as printed: "15's" -> 15, "1x10" -> 10,
  /// "100ML" -> 100; 1 when the pack doesn't say. See [PackSize.parse].
  static int unitsPerPack(String pack) => PackSize.parse(pack);

  /// A unit for a new medicine from its printed name and pack. Invoices
  /// count packs, so tablets/capsules default to strips (no conversion).
  static String guessUnit(String name, String pack) {
    final String s = '${name.toLowerCase()} ${pack.toLowerCase()}';
    bool has(String pattern) => RegExp(pattern).hasMatch(s);
    if (has(r'\b(inj|injection|vial|amp|ampoule)\b')) return 'Injections';
    if (has(
          r'\b(syp|syr|syrup|susp|suspension|drops?|liquid|solution|'
          r'lotion|mouthwash)\b',
        ) ||
        has(r'\d\s*ml\b')) {
      return 'Bottles';
    }
    if (has(r'\b(cream|crm|gel|oint|ointment|tube)\b')) return 'Tubes';
    if (has(r'\b(sachets?|powder|pdr|granules)\b')) return 'Sachets';
    if (has(r'\b(tabs?|tablets?|caps?|capsules?)\b') ||
        has(r"\d\s*['’`]?\s*s\b") ||
        has(r'\d\s*[x×*]\s*\d')) {
      return 'Strips';
    }
    return 'Pieces';
  }

  /// "2027-06-30" (or "2027-06", month-only) -> a local date; a month-only
  /// value is the last day of the month when [endOfMonth] (expiry).
  static DateTime? parseDate(Object? v, {bool endOfMonth = false}) {
    final RegExpMatch? m = RegExp(
      r'^(\d{4})-(\d{1,2})(?:-(\d{1,2}))?',
    ).firstMatch(_str(v));
    if (m == null) return null;
    final int y = int.parse(m[1]!);
    final int mo = int.parse(m[2]!);
    if (y < 2000 || y > 2100 || mo < 1 || mo > 12) return null;
    if (m[3] == null) {
      return endOfMonth ? DateTime(y, mo + 1, 0) : DateTime(y, mo, 1);
    }
    final int d = int.parse(m[3]!);
    final DateTime date = DateTime(y, mo, d);
    return date.month == mo && date.day == d ? date : null;
  }

  static String _str(Object? v) =>
      v is String ? v.trim() : (v is num ? '$v' : '');

  static double? _num(Object? v) {
    if (v is num) return v.isFinite ? v.toDouble() : null;
    if (v is String) {
      return double.tryParse(v.replaceAll(RegExp(r'[,₹\s%]'), ''));
    }
    return null;
  }

  static int _int(Object? v) => math.max(0, (_num(v) ?? 0).round());

  static String _norm(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
