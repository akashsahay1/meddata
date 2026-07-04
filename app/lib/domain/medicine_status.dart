import '../core/constants.dart';
import '../data/models/medicine.dart';

/// Expiry state, conveyed by TEXT/ICON only — never by color (B&W design).
enum ExpiryState { expired, expiring, ok }

/// Computed status for a medicine: expiry + low stock, plus display helpers.
class MedicineStatus {
  final ExpiryState expiryState;
  final int daysToExpiry; // negative if already expired
  final bool isLowStock;

  const MedicineStatus({
    required this.expiryState,
    required this.daysToExpiry,
    required this.isLowStock,
  });

  bool get isExpired => expiryState == ExpiryState.expired;
  bool get isExpiring => expiryState == ExpiryState.expiring;
  bool get isOutOfStock => false; // handled via quantity == 0 in UI

  /// Short label for the status chip, e.g. "EXPIRED", "EXPIRES IN 12 DAYS".
  String get expiryLabel {
    switch (expiryState) {
      case ExpiryState.expired:
        final int d = -daysToExpiry;
        if (d == 0) return 'EXPIRES TODAY';
        return 'EXPIRED ${d}D AGO';
      case ExpiryState.expiring:
        if (daysToExpiry == 0) return 'EXPIRES TODAY';
        if (daysToExpiry == 1) return 'EXPIRES TOMORROW';
        return 'EXPIRES IN ${daysToExpiry}D';
      case ExpiryState.ok:
        return 'OK';
    }
  }

  static MedicineStatus of(
    Medicine m, {
    int warningDays = AppConstants.defaultExpiryWarningDays,
    DateTime? now,
  }) {
    final DateTime today = _dateOnly(now ?? DateTime.now());
    final DateTime exp = _dateOnly(m.expiryDate);
    final int days = exp.difference(today).inDays;

    final ExpiryState state;
    if (days < 0) {
      state = ExpiryState.expired;
    } else if (days <= warningDays) {
      state = ExpiryState.expiring;
    } else {
      state = ExpiryState.ok;
    }

    return MedicineStatus(
      expiryState: state,
      daysToExpiry: days,
      isLowStock: m.quantity <= m.lowStockThreshold,
    );
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}

/// Free-tier gating helper. Kept pure so it is easy to unit test.
class Entitlement {
  final bool isPremium;
  const Entitlement({required this.isPremium});

  static const Entitlement free = Entitlement(isPremium: false);
  static const Entitlement premium = Entitlement(isPremium: true);

  /// Whether a new medicine can be added given the current count.
  bool canAddMedicine(int currentCount) {
    if (isPremium) return true;
    return currentCount < AppConstants.freeTierMedicineLimit;
  }

  int get freeLimit => AppConstants.freeTierMedicineLimit;
}
