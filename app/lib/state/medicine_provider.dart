import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../data/db/database_helper.dart';
import '../data/models/medicine.dart';
import '../data/models/stock_import.dart';
import '../data/models/stock_movement.dart';
import '../data/repositories/medicine_repository.dart';
import '../data/repositories/report_repository.dart';
import '../domain/medicine_status.dart';
import '../domain/product_stock.dart';

enum MedicineFilter { all, expiring, expired, lowStock }

enum MedicineSort { nameAsc, expirySoonest, quantityLowest, recentlyUpdated }

/// Result of an add attempt so the UI can react (e.g. show the paywall).
enum AddResult { success, blockedByFreeLimit, duplicate }

class MedicineProvider extends ChangeNotifier {
  final MedicineRepository _repo;
  MedicineProvider([MedicineRepository? repo])
      : _repo = repo ?? MedicineRepository();

  List<Medicine> _all = <Medicine>[];
  List<ProductStock> _products = <ProductStock>[];
  Map<String, int> _productQty = <String, int>{};
  bool _loading = true;
  String _query = '';
  MedicineFilter _filter = MedicineFilter.all;
  MedicineSort _sort = MedicineSort.nameAsc;

  // Injected from settings so status computation matches user preference.
  int warningDays = 30;
  bool isPremium = false;

  bool get loading => _loading;
  String get query => _query;
  MedicineFilter get filter => _filter;
  MedicineSort get sort => _sort;
  int get totalCount => _all.length;

  /// Number of products (all batches of a medicine count once).
  int get productCount => _products.length;
  List<ProductStock> get products => _products;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    _all = await _repo.getAll();
    _products = ProductStock.group(_all);
    _productQty = <String, int>{
      for (final ProductStock p in _products) p.productId: p.totalQty,
    };
    _loading = false;
    notifyListeners();
  }

  void setQuery(String q) {
    _query = q;
    notifyListeners();
  }

  void setFilter(MedicineFilter f) {
    _filter = f;
    notifyListeners();
  }

  void setSort(MedicineSort s) {
    _sort = s;
    notifyListeners();
  }

  /// Status of one batch. Low stock is judged on the product's total stock
  /// across all its batches.
  MedicineStatus statusOf(Medicine m) => MedicineStatus.of(m,
      warningDays: warningDays, productQty: _productQty[m.productId]);

  ProductStock? productById(String productId) {
    for (final ProductStock p in _products) {
      if (p.productId == productId) return p;
    }
    return null;
  }

  /// The shop's product with this barcode, if any (exact match, ignoring
  /// surrounding spaces and letter case).
  ProductStock? productByBarcode(String code) {
    final String c = code.trim().toLowerCase();
    if (c.isEmpty) return null;
    for (final ProductStock p in _products) {
      if (p.first.barcode.trim().toLowerCase() == c) return p;
    }
    return null;
  }

  /// Batches that still hold stock (expiry alerts only matter for these).
  Iterable<Medicine> get _stocked => _all.where((Medicine m) => m.quantity > 0);

  /// All active medicines, ignoring search/filter (used by the alerts screen).
  List<Medicine> get visibleAllForAlerts => List<Medicine>.unmodifiable(_all);

  /// Look up a medicine by id from the full loaded list (ignores filters).
  Medicine? findById(String id) {
    for (final Medicine m in _all) {
      if (m.id == id) return m;
    }
    return null;
  }

  // ---- Derived counts for the dashboard tiles ----
  int get expiringCount =>
      _stocked.where((Medicine m) => statusOf(m).isExpiring).length;

  int get expiredCount =>
      _stocked.where((Medicine m) => statusOf(m).isExpired).length;

  /// Products whose total stock is at or below their low-stock level.
  int get lowStockCount =>
      _products.where((ProductStock p) => p.isLowStock).length;

  /// For alert lists: expired / expiring batches that still have stock,
  /// and one entry (its next batch) per low-stock product.
  List<Medicine> get expiredBatches =>
      _stocked.where((Medicine m) => statusOf(m).isExpired).toList();
  List<Medicine> get expiringBatches =>
      _stocked.where((Medicine m) => statusOf(m).isExpiring).toList()
        ..sort((Medicine a, Medicine b) => a.expiryDate.compareTo(b.expiryDate));
  /// Product counts for the Inventory filter chips (match the product list).
  int get productsExpiringCount => _products
      .where((ProductStock p) => p.inStock.any((Medicine m) => statusOf(m).isExpiring))
      .length;
  int get productsExpiredCount => _products
      .where((ProductStock p) => p.inStock.any((Medicine m) => statusOf(m).isExpired))
      .length;

  List<ProductStock> get lowStockProducts =>
      _products.where((ProductStock p) => p.isLowStock).toList();

  /// Products after search, filter and sort (the Inventory list).
  List<ProductStock> get visibleProducts {
    final String q = _query.trim().toLowerCase();
    Iterable<ProductStock> list = _products;
    if (q.isNotEmpty) {
      list = list.where((ProductStock p) => p.batches.any((Medicine m) =>
          m.name.toLowerCase().contains(q) ||
          m.brand.toLowerCase().contains(q) ||
          m.batchNo.toLowerCase().contains(q) ||
          m.barcode.toLowerCase().contains(q) ||
          m.category.toLowerCase().contains(q)));
    }
    switch (_filter) {
      case MedicineFilter.all:
        break;
      case MedicineFilter.expiring:
        list = list.where((ProductStock p) =>
            p.inStock.any((Medicine m) => statusOf(m).isExpiring));
      case MedicineFilter.expired:
        list = list.where((ProductStock p) =>
            p.inStock.any((Medicine m) => statusOf(m).isExpired));
      case MedicineFilter.lowStock:
        list = list.where((ProductStock p) => p.isLowStock);
    }
    final List<ProductStock> out = list.toList();
    switch (_sort) {
      case MedicineSort.nameAsc:
        break; // already by name
      case MedicineSort.expirySoonest:
        out.sort((ProductStock a, ProductStock b) =>
            a.nearestExpiry.compareTo(b.nearestExpiry));
      case MedicineSort.quantityLowest:
        out.sort((ProductStock a, ProductStock b) => a.totalQty.compareTo(b.totalQty));
      case MedicineSort.recentlyUpdated:
        DateTime last(ProductStock p) => p.batches
            .map((Medicine m) => m.updatedAt)
            .reduce((DateTime a, DateTime b) => a.isAfter(b) ? a : b);
        out.sort((ProductStock a, ProductStock b) => last(b).compareTo(last(a)));
    }
    return out;
  }

  double get totalStockValue =>
      _all.fold(0, (double sum, Medicine m) => sum + m.stockValue);

  /// The list after applying search, filter, and sort.
  List<Medicine> get visible {
    Iterable<Medicine> list = _all;

    if (_query.trim().isNotEmpty) {
      final String q = _query.trim().toLowerCase();
      list = list.where((Medicine m) =>
          m.name.toLowerCase().contains(q) ||
          m.brand.toLowerCase().contains(q) ||
          m.batchNo.toLowerCase().contains(q) ||
          m.barcode.toLowerCase().contains(q) ||
          m.category.toLowerCase().contains(q));
    }

    switch (_filter) {
      case MedicineFilter.all:
        break;
      case MedicineFilter.expiring:
        list = list.where((Medicine m) => statusOf(m).isExpiring);
        break;
      case MedicineFilter.expired:
        list = list.where((Medicine m) => statusOf(m).isExpired);
        break;
      case MedicineFilter.lowStock:
        list = list.where((Medicine m) => statusOf(m).isLowStock);
        break;
    }

    final List<Medicine> result = list.toList();
    switch (_sort) {
      case MedicineSort.nameAsc:
        result.sort((Medicine a, Medicine b) =>
            a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case MedicineSort.expirySoonest:
        result.sort((Medicine a, Medicine b) =>
            a.expiryDate.compareTo(b.expiryDate));
        break;
      case MedicineSort.quantityLowest:
        result.sort((Medicine a, Medicine b) =>
            a.quantity.compareTo(b.quantity));
        break;
      case MedicineSort.recentlyUpdated:
        result.sort((Medicine a, Medicine b) =>
            b.updatedAt.compareTo(a.updatedAt));
        break;
    }
    return result;
  }

  /// Free-plan limit counts products (a new batch of a known medicine is free).
  bool canAdd() =>
      Entitlement(isPremium: isPremium).canAddMedicine(_products.length);

  /// How many more medicines (products) the free plan allows; null = no
  /// limit.
  int? get newMedicineRoom {
    final Entitlement e = Entitlement(isPremium: isPremium);
    if (e.isPremium) return null;
    return math.max(0, e.freeLimit - _products.length);
  }

  /// Save the rows of a spreadsheet import (one transaction), then reload.
  Future<StockImportResult> importStock(List<StockImportRow> rows,
      {void Function(int done, int total)? onProgress}) async {
    final StockImportResult result =
        await _repo.importStock(rows, onProgress: onProgress);
    await load();
    return result;
  }

  Future<AddResult> add(Medicine m, {bool allowDuplicate = false}) async {
    if (!canAdd()) return AddResult.blockedByFreeLimit;
    if (!allowDuplicate &&
        await _repo.existsNameBatch(m.name, m.batchNo)) {
      return AddResult.duplicate;
    }
    await _repo.insert(m);
    await load();
    return AddResult.success;
  }

  /// How many new medicines adding [items] would create: one per name + unit
  /// + brand the shop doesn't have yet (the repository's own test for
  /// "new batch of an existing product").
  int countNewProducts(Iterable<Medicine> items) {
    String key(String name, String unit, String brand) =>
        '${DatabaseHelper.normName(name)}|$unit|${brand.trim().toLowerCase()}';
    final Set<String> known = <String>{
      for (final ProductStock p in _products) key(p.name, p.unit, p.brand),
    };
    return items
        .where((Medicine m) => known.add(key(m.name, m.unit, m.brand)))
        .length;
  }

  /// Whether the free plan has room for [newProducts] more medicines.
  bool canAddProducts(int newProducts) =>
      newProducts <= 0 ||
      Entitlement(isPremium: isPremium)
          .canAddMedicine(_products.length + newProducts - 1);

  /// Adds the reviewed lines of a scanned purchase invoice, each one exactly
  /// like a manual add (a batch joins its product, stock is an opening
  /// movement, everything is queued for sync), then reloads once. Nothing is
  /// added when the new medicines don't fit the free plan.
  Future<AddResult> addFromInvoice(List<Medicine> items) async {
    if (!canAddProducts(countNewProducts(items))) {
      return AddResult.blockedByFreeLimit;
    }
    for (final Medicine m in items) {
      await _repo.insert(m);
    }
    await load();
    return AddResult.success;
  }

  Future<void> update(Medicine m) async {
    await _repo.update(m);
    await load();
  }

  Future<void> adjustQuantity(String id, int delta, StockReason reason) async {
    await _repo.adjustQuantity(id, delta, reason);
    await load();
  }

  /// Writes off the stock of these expired batches (see
  /// [MedicineRepository.writeOffExpired]); returns the units removed.
  Future<int> writeOffExpired(Iterable<String> ids) async {
    int units = 0;
    for (final String id in ids) {
      units += await _repo.writeOffExpired(id);
    }
    await load();
    return units;
  }

  /// Soft-deletes and returns the deleted medicine so the UI can offer undo.
  Future<Medicine?> delete(String id) async {
    final Medicine? m = await _repo.getById(id);
    await _repo.softDelete(id);
    await load();
    return m;
  }

  Future<void> undoDelete(String id) async {
    await _repo.restore(id);
    await load();
  }

  /// Stock report queries over the same inventory database.
  ReportRepository get reports => ReportRepository(_repo.database);

  Future<List<StockMovement>> movementsFor(String id) =>
      _repo.movementsFor(id);

  Future<bool> isDuplicate(String name, String batchNo,
          {String? excludeId}) =>
      _repo.existsNameBatch(name, batchNo, excludeId: excludeId);
}
