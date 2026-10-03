import '../data/models/medicine.dart';

/// A future day on which stock changes expiry state.
class AlertDay {
  final DateTime day;

  /// Batches that enter the "expiring soon" window on [day].
  final int startExpiring;

  /// Batches whose expiry date passed the day before (first expired day).
  final int expired;

  const AlertDay(this.day, this.startExpiring, this.expired);

  String get message {
    final List<String> parts = <String>[
      if (startExpiring > 0)
        '$startExpiring ${startExpiring == 1 ? 'medicine is' : 'medicines are'} now expiring soon',
      if (expired > 0)
        '$expired ${expired == 1 ? 'medicine has' : 'medicines have'} expired',
    ];
    return '${parts.join(' and ')}. Tap to review.';
  }
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Expiry dates are known in advance, so the days that need an alert can be
/// computed now and scheduled as local notifications — no background work
/// or server involved. Batches with no stock are ignored.
List<AlertDay> planExpiryAlerts(
  List<Medicine> meds, {
  required int warningDays,
  required DateTime today,
  int horizonDays = 60,
}) {
  final DateTime start = _day(today);
  final DateTime end = start.add(Duration(days: horizonDays));
  final Map<DateTime, List<int>> byDay = <DateTime, List<int>>{};

  void add(DateTime day, int index) {
    if (!day.isAfter(start) || day.isAfter(end)) return;
    (byDay[day] ??= <int>[0, 0])[index]++;
  }

  for (final Medicine m in meds) {
    if (m.isDeleted || m.quantity <= 0) continue;
    final DateTime exp = _day(m.expiryDate);
    // Same calendar arithmetic as MedicineStatus: expiring when
    // days-to-expiry <= warningDays, expired when < 0.
    add(DateTime(exp.year, exp.month, exp.day - warningDays), 0);
    add(DateTime(exp.year, exp.month, exp.day + 1), 1);
  }

  final List<DateTime> days = byDay.keys.toList()..sort();
  return <AlertDay>[
    for (final DateTime d in days) AlertDay(d, byDay[d]![0], byDay[d]![1]),
  ];
}
