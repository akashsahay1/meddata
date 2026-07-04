import 'package:flutter/foundation.dart';

import '../data/models/medicine.dart';
import '../data/models/stock_movement.dart';
import '../data/repositories/medicine_repository.dart';
import '../domain/medicine_status.dart';

enum MedicineFilter { all, expiring, expired, lowStock }

enum MedicineSort { nameAsc, expirySoonest, quantityLowest, recentlyUpdated }

/// Result of an add attempt so the UI can react (e.g. show the paywall).
enum AddResult { success, blockedByFreeLimit, duplicate }

class MedicineProvider extends ChangeNotifier {
  final MedicineRepository _repo;
  MedicineProvider([MedicineRepository? repo])
      : _repo = repo ?? MedicineRepository();

  List<Medicine> _all = <Medicine>[];
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

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    _all = await _repo.getAll();
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

  MedicineStatus statusOf(Medicine m) =>
      MedicineStatus.of(m, warningDays: warningDays);

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
  int get expiringCount => _all.where((Medicine m) {
        final ExpiryState s = statusOf(m).expiryState;
        return s == ExpiryState.expiring;
      }).length;

  int get expiredCount =>
      _all.where((Medicine m) => statusOf(m).isExpired).length;

  int get lowStockCount =>
      _all.where((Medicine m) => statusOf(m).isLowStock).length;

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

  bool canAdd() => Entitlement(isPremium: isPremium).canAddMedicine(_all.length);

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

  Future<void> update(Medicine m) async {
    await _repo.update(m);
    await load();
  }

  Future<void> adjustQuantity(String id, int delta, StockReason reason) async {
    await _repo.adjustQuantity(id, delta, reason);
    await load();
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

  Future<List<StockMovement>> movementsFor(String id) =>
      _repo.movementsFor(id);

  Future<bool> isDuplicate(String name, String batchNo,
          {String? excludeId}) =>
      _repo.existsNameBatch(name, batchNo, excludeId: excludeId);
}
