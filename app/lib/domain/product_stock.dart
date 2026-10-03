import '../data/models/medicine.dart';
import 'medicine_status.dart';

/// One product with all its batches, for product-level views. Stock and
/// low-stock are per product (all batches together); expiry is per batch,
/// and only batches that still have stock count towards expiry alerts.
class ProductStock {
  final String productId;

  /// Batches, earliest expiry first.
  final List<Medicine> batches;

  const ProductStock(this.productId, this.batches);

  Medicine get first => batches.first;
  String get name => first.name;
  String get brand => first.brand;
  String get category => first.category;
  String get unit => first.unit;
  int get lowStockThreshold => first.lowStockThreshold;

  int get totalQty =>
      batches.fold(0, (int sum, Medicine m) => sum + m.quantity);

  bool get isLowStock => totalQty <= lowStockThreshold;

  /// Batches that still hold stock (the ones expiry matters for).
  Iterable<Medicine> get inStock =>
      batches.where((Medicine m) => m.quantity > 0);

  /// Earliest expiry among batches with stock (else among all batches).
  DateTime get nearestExpiry =>
      (inStock.isNotEmpty ? inStock.first : first).expiryDate;

  /// Worst expiry state among batches with stock: expired > expiring > ok.
  ExpiryState worstExpiry(int warningDays) {
    ExpiryState worst = ExpiryState.ok;
    for (final Medicine m in inStock) {
      final ExpiryState s =
          MedicineStatus.of(m, warningDays: warningDays).expiryState;
      if (s == ExpiryState.expired) return s;
      if (s == ExpiryState.expiring) worst = s;
    }
    return worst;
  }

  /// MRP of the batch that sells next (earliest expiry with stock).
  double get currentMrp =>
      (inStock.isNotEmpty ? inStock.first : first).sellingPrice;

  /// Groups batches (any order) into products, sorted by product name.
  static List<ProductStock> group(Iterable<Medicine> batches) {
    final Map<String, List<Medicine>> by = <String, List<Medicine>>{};
    for (final Medicine m in batches) {
      (by[m.productId.isEmpty ? m.id : m.productId] ??= <Medicine>[]).add(m);
    }
    final List<ProductStock> out = <ProductStock>[
      for (final MapEntry<String, List<Medicine>> e in by.entries)
        ProductStock(
            e.key,
            e.value
              ..sort((Medicine a, Medicine b) =>
                  a.expiryDate.compareTo(b.expiryDate))),
    ];
    out.sort((ProductStock a, ProductStock b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }
}
