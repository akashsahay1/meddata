import '../../core/constants.dart';
import '../../domain/pack_size.dart';

/// One batch of a product, flattened for the UI: [id] is the batch id and
/// [productId] its product. Product fields (name, brand, unit, ...) are
/// shared by every batch of the product. Dates are epoch millis in the DB.
class Medicine {
  final String id;
  final String productId;
  final String name;
  final String brand;
  final String category;
  final String batchNo;
  final String barcode;
  final int quantity;
  final String unit;

  /// Pieces in one pack of the product (tablets per strip, ml per bottle),
  /// shared by its batches; 1 when not set. See [PackSize].
  final int packSize;
  final int lowStockThreshold;
  final double purchasePrice;
  final double sellingPrice;
  final DateTime? mfgDate;
  final DateTime expiryDate;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;

  /// GST details of the product (shared by its batches): HSN code, and the
  /// GST rate in basis points (500 = 5%; null = the shop's default rate).
  final String hsn;
  final int? gstRateBp;

  const Medicine({
    required this.id,
    this.productId = '',
    required this.name,
    this.brand = '',
    this.category = '',
    this.batchNo = '',
    this.barcode = '',
    required this.quantity,
    this.unit = 'Tablets',
    this.packSize = 1,
    this.lowStockThreshold = AppConstants.defaultLowStockThreshold,
    this.purchasePrice = 0,
    this.sellingPrice = 0,
    this.mfgDate,
    required this.expiryDate,
    this.notes = '',
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
    this.hsn = '',
    this.gstRateBp,
  });

  /// Pieces a price covers: the strip when the pack size applies, else 1.
  /// [sellingPrice] and [purchasePrice] are per that many pieces.
  int get pricePack => PackSize.pricePack(unit, packSize);

  /// Total stock value at selling price (used in reports).
  double get stockValue => sellingPrice * quantity / pricePack;

  Medicine copyWith({
    String? name,
    String? brand,
    String? category,
    String? batchNo,
    String? barcode,
    int? quantity,
    String? unit,
    int? packSize,
    int? lowStockThreshold,
    double? purchasePrice,
    double? sellingPrice,
    DateTime? mfgDate,
    DateTime? expiryDate,
    String? notes,
    DateTime? updatedAt,
    bool? isDeleted,
    String? hsn,
    int? gstRateBp,
    bool clearGstRate = false,
  }) {
    return Medicine(
      id: id,
      productId: productId,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      category: category ?? this.category,
      batchNo: batchNo ?? this.batchNo,
      barcode: barcode ?? this.barcode,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      packSize: packSize ?? this.packSize,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      mfgDate: mfgDate ?? this.mfgDate,
      expiryDate: expiryDate ?? this.expiryDate,
      notes: notes ?? this.notes,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      hsn: hsn ?? this.hsn,
      gstRateBp: clearGstRate ? null : (gstRateBp ?? this.gstRateBp),
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'product_id': productId,
      'name': name,
      'brand': brand,
      'category': category,
      'batch_no': batchNo,
      'barcode': barcode,
      'quantity': quantity,
      'unit': unit,
      'pack_size': packSize,
      'low_stock_threshold': lowStockThreshold,
      'purchase_price': purchasePrice,
      'selling_price': sellingPrice,
      'mfg_date': mfgDate?.millisecondsSinceEpoch,
      'expiry_date': expiryDate.millisecondsSinceEpoch,
      'notes': notes,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
      'is_deleted': isDeleted ? 1 : 0,
      'hsn': hsn,
      'gst_rate_bp': gstRateBp,
    };
  }

  factory Medicine.fromMap(Map<String, Object?> map) {
    return Medicine(
      id: map['id'] as String,
      productId: (map['product_id'] as String?) ?? '',
      name: (map['name'] as String?) ?? '',
      brand: (map['brand'] as String?) ?? '',
      category: (map['category'] as String?) ?? '',
      batchNo: (map['batch_no'] as String?) ?? '',
      barcode: (map['barcode'] as String?) ?? '',
      quantity: (map['quantity'] as int?) ?? 0,
      unit: AppConstants.canonicalUnit(map['unit'] as String?),
      packSize: ((map['pack_size'] as num?) ?? 1).toInt().clamp(1, PackSize.max),
      lowStockThreshold: (map['low_stock_threshold'] as int?) ??
          AppConstants.defaultLowStockThreshold,
      purchasePrice: ((map['purchase_price'] as num?) ?? 0).toDouble(),
      sellingPrice: ((map['selling_price'] as num?) ?? 0).toDouble(),
      mfgDate: map['mfg_date'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(map['mfg_date'] as int),
      expiryDate:
          DateTime.fromMillisecondsSinceEpoch((map['expiry_date'] as int?) ?? 0),
      notes: (map['notes'] as String?) ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          (map['created_at'] as int?) ?? 0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (map['updated_at'] as int?) ?? 0),
      isDeleted: ((map['is_deleted'] as int?) ?? 0) == 1,
      hsn: (map['hsn'] as String?) ?? '',
      gstRateBp: (map['gst_rate_bp'] as num?)?.toInt(),
    );
  }
}
