import 'package:flutter_test/flutter_test.dart';
import 'package:med_stock/core/constants.dart';
import 'package:med_stock/data/models/medicine.dart';
import 'package:med_stock/domain/medicine_status.dart';

Medicine _med({
  required int daysToExpiry,
  int quantity = 100,
  int lowStockThreshold = 10,
  DateTime? now,
}) {
  final DateTime base = now ?? DateTime(2026, 1, 1);
  return Medicine(
    id: 'x',
    name: 'Test',
    quantity: quantity,
    lowStockThreshold: lowStockThreshold,
    expiryDate: base.add(Duration(days: daysToExpiry)),
    createdAt: base,
    updatedAt: base,
  );
}

void main() {
  final DateTime now = DateTime(2026, 1, 1);

  group('Expiry status', () {
    test('past expiry is EXPIRED', () {
      final MedicineStatus s =
          MedicineStatus.of(_med(daysToExpiry: -5, now: now), now: now);
      expect(s.isExpired, isTrue);
      expect(s.expiryLabel, contains('EXPIRED'));
    });

    test('within warning window is EXPIRING', () {
      final MedicineStatus s = MedicineStatus.of(
          _med(daysToExpiry: 10, now: now),
          warningDays: 30, now: now);
      expect(s.isExpiring, isTrue);
      expect(s.expiryLabel, 'EXPIRES IN 10D');
    });

    test('beyond warning window is OK', () {
      final MedicineStatus s = MedicineStatus.of(
          _med(daysToExpiry: 90, now: now),
          warningDays: 30, now: now);
      expect(s.expiryState, ExpiryState.ok);
    });

    test('expires today edge case', () {
      final MedicineStatus s =
          MedicineStatus.of(_med(daysToExpiry: 0, now: now), now: now);
      expect(s.isExpiring, isTrue);
      expect(s.expiryLabel, 'EXPIRES TODAY');
    });

    test('warning window is configurable', () {
      final Medicine m = _med(daysToExpiry: 45, now: now);
      expect(MedicineStatus.of(m, warningDays: 30, now: now).expiryState,
          ExpiryState.ok);
      expect(MedicineStatus.of(m, warningDays: 60, now: now).isExpiring,
          isTrue);
    });
  });

  group('Low stock', () {
    test('quantity at threshold is low stock', () {
      final MedicineStatus s = MedicineStatus.of(
          _med(daysToExpiry: 100, quantity: 10, lowStockThreshold: 10,
              now: now),
          now: now);
      expect(s.isLowStock, isTrue);
    });

    test('quantity above threshold is not low', () {
      final MedicineStatus s = MedicineStatus.of(
          _med(daysToExpiry: 100, quantity: 11, lowStockThreshold: 10,
              now: now),
          now: now);
      expect(s.isLowStock, isFalse);
    });
  });

  group('Free-tier gating', () {
    test('free user blocked at the limit', () {
      const Entitlement free = Entitlement.free;
      expect(free.canAddMedicine(AppConstants.freeTierMedicineLimit - 1),
          isTrue);
      expect(
          free.canAddMedicine(AppConstants.freeTierMedicineLimit), isFalse);
    });

    test('premium user is never blocked', () {
      const Entitlement premium = Entitlement.premium;
      expect(premium.canAddMedicine(9999), isTrue);
    });
  });
}
