import 'package:flutter_test/flutter_test.dart';
import 'package:med_stock/data/models/medicine.dart';
import 'package:med_stock/domain/expiry_alert_plan.dart';
import 'package:med_stock/domain/medicine_status.dart';

void main() {
  final DateTime today = DateTime(2026, 10, 3, 14, 30);

  Medicine m(DateTime expiry, {int qty = 10}) => Medicine(
        id: '${expiry.millisecondsSinceEpoch}-$qty',
        name: 'X',
        quantity: qty,
        expiryDate: expiry,
        createdAt: today,
        updatedAt: today,
      );

  test('schedules the day a batch enters the window and the day it expires', () {
    final List<AlertDay> plan = planExpiryAlerts(
      <Medicine>[m(DateTime(2026, 11, 20))],
      warningDays: 30,
      today: today,
    );
    expect(plan.map((AlertDay a) => a.day), <DateTime>[DateTime(2026, 10, 21), DateTime(2026, 11, 21)]);
    expect(plan.first.startExpiring, 1);
    expect(plan.last.expired, 1);
  });

  test('plan days agree with MedicineStatus on the day before and the day itself', () {
    final Medicine med = m(DateTime(2026, 11, 20));
    for (final AlertDay a in planExpiryAlerts(<Medicine>[med], warningDays: 30, today: today)) {
      final MedicineStatus before = MedicineStatus.of(med, warningDays: 30, now: a.day.subtract(const Duration(days: 1)));
      final MedicineStatus on = MedicineStatus.of(med, warningDays: 30, now: a.day);
      if (a.startExpiring > 0) {
        expect(<bool>[before.isExpiring, on.isExpiring], <bool>[false, true]);
      } else {
        expect(<bool>[before.isExpired, on.isExpired], <bool>[false, true]);
      }
    }
  });

  test('groups batches per day, skips empty stock, past days and the far future', () {
    final List<AlertDay> plan = planExpiryAlerts(
      <Medicine>[
        m(DateTime(2026, 11, 20)),
        m(DateTime(2026, 11, 20)),
        m(DateTime(2026, 11, 20), qty: 0),
        m(DateTime(2026, 10, 10)), // already expiring: only its expiry day
        m(DateTime(2027, 6, 1)), // beyond 60 days
      ],
      warningDays: 30,
      today: today,
    );
    expect(plan.map((AlertDay a) => a.day), <DateTime>[
      DateTime(2026, 10, 11),
      DateTime(2026, 10, 21),
      DateTime(2026, 11, 21),
    ]);
    expect(plan[1].startExpiring, 2);
    expect(plan[1].message, '2 medicines are now expiring soon. Tap to review.');
    expect(plan[0].message, '1 medicine has expired. Tap to review.');
  });
}
