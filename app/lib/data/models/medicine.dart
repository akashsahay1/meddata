import '../../core/constants.dart';

/// A single medicine stock record. Dates are stored in the DB as epoch millis.
class Medicine {
  final String id;
  final String name;
  final String brand;
  final String category;
  final String batchNo;
  final String barcode;
  final int quantity;
  final String unit;
  final int lowStockThreshold;
  final double purchasePrice;
  final double sellingPrice;
  final String? supplierId;
  final DateTime? mfgDate;
  final DateTime expiryDate;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;

  const Medicine({
    required this.id,
    required this.name,
    this.brand = '',
    this.category = '',
    this.batchNo = '',
    this.barcode = '',
    required this.quantity,
    this.unit = 'Tablets',
    this.lowStockThreshold = AppConstants.defaultLowStockThreshold,
    this.purchasePrice = 0,
    this.sellingPrice = 0,
    this.supplierId,
    this.mfgDate,
    required this.expiryDate,
    this.notes = '',
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
  });

  /// Total stock value at selling price (used in reports).
  double get stockValue => sellingPrice * quantity;

  Medicine copyWith({
    String? name,
    String? brand,
    String? category,
    String? batchNo,
    String? barcode,
    int? quantity,
    String? unit,
    int? lowStockThreshold,
    double? purchasePrice,
    double? sellingPrice,
    String? supplierId,
    DateTime? mfgDate,
    DateTime? expiryDate,
    String? notes,
    DateTime? updatedAt,
    bool? isDeleted,
  }) {
    return Medicine(
      id: id,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      category: category ?? this.category,
      batchNo: batchNo ?? this.batchNo,
      barcode: barcode ?? this.barcode,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      supplierId: supplierId ?? this.supplierId,
      mfgDate: mfgDate ?? this.mfgDate,
      expiryDate: expiryDate ?? this.expiryDate,
      notes: notes ?? this.notes,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'brand': brand,
      'category': category,
      'batch_no': batchNo,
      'barcode': barcode,
      'quantity': quantity,
      'unit': unit,
      'low_stock_threshold': lowStockThreshold,
      'purchase_price': purchasePrice,
      'selling_price': sellingPrice,
      'supplier_id': supplierId,
      'mfg_date': mfgDate?.millisecondsSinceEpoch,
      'expiry_date': expiryDate.millisecondsSinceEpoch,
      'notes': notes,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
      'is_deleted': isDeleted ? 1 : 0,
    };
  }

  factory Medicine.fromMap(Map<String, Object?> map) {
    return Medicine(
      id: map['id'] as String,
      name: (map['name'] as String?) ?? '',
      brand: (map['brand'] as String?) ?? '',
      category: (map['category'] as String?) ?? '',
      batchNo: (map['batch_no'] as String?) ?? '',
      barcode: (map['barcode'] as String?) ?? '',
      quantity: (map['quantity'] as int?) ?? 0,
      unit: (map['unit'] as String?) ?? 'Tablets',
      lowStockThreshold: (map['low_stock_threshold'] as int?) ??
          AppConstants.defaultLowStockThreshold,
      purchasePrice: ((map['purchase_price'] as num?) ?? 0).toDouble(),
      sellingPrice: ((map['selling_price'] as num?) ?? 0).toDouble(),
      supplierId: map['supplier_id'] as String?,
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
    );
  }
}
