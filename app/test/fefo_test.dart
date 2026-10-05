import 'package:flutter_test/flutter_test.dart';
import 'package:med_stock/domain/fefo.dart';

void main() {
  final DateTime today = DateTime(2026, 10, 5, 15, 30);

  SaleBatch batch(String id, DateTime expiry, int qty, {int mrp = 3000}) => SaleBatch(
        id: id,
        productId: 'p',
        productName: 'Dolo 650',
        batchNo: id,
        expiryDate: expiry,
        mrpPaise: mrp,
        version: 1,
        qty: qty,
      );

  final List<SaleBatch> batches = <SaleBatch>[
    batch('LATE', DateTime(2027, 6, 30), 50),
    batch('EXPIRED', DateTime(2026, 10, 4), 40),
    batch('SOON', DateTime(2026, 12, 31), 5),
    batch('EMPTY', DateTime(2026, 11, 30), 0),
    batch('TODAY', DateTime(2026, 10, 5), 2),
  ];

  List<(String, int)> takes(FefoAllocation a) =>
      a.takes.map((BatchTake t) => (t.batch.id, t.qty)).toList();

  test('sells the earliest expiring batch first, never an expired or empty one', () {
    expect(Fefo.sellable(batches, today).map((SaleBatch b) => b.id), <String>['TODAY', 'SOON', 'LATE']);
    expect(takes(Fefo.allocate(batches, 1, today: today)), <(String, int)>[('TODAY', 1)]);
  });

  test('spills over to the next batch when one runs out', () {
    final FefoAllocation a = Fefo.allocate(batches, 10, today: today);
    expect(takes(a), <(String, int)>[('TODAY', 2), ('SOON', 5), ('LATE', 3)]);
    expect(a.isComplete, isTrue);
  });

  test('reports what no batch can supply', () {
    final FefoAllocation a = Fefo.allocate(batches, 60, today: today);
    expect(takes(a), <(String, int)>[('TODAY', 2), ('SOON', 5), ('LATE', 50)]);
    expect(a.shortfall, 3);
    expect(a.isComplete, isFalse);
  });

  test('a batch the user picked goes first; an expired pick is ignored', () {
    expect(takes(Fefo.allocate(batches, 52, today: today, pinnedBatchId: 'LATE')),
        <(String, int)>[('LATE', 50), ('TODAY', 2)]);
    expect(takes(Fefo.allocate(batches, 3, today: today, pinnedBatchId: 'EXPIRED')),
        <(String, int)>[('TODAY', 2), ('SOON', 1)]);
  });

  test('nothing to sell', () {
    final FefoAllocation a = Fefo.allocate(<SaleBatch>[batch('X', DateTime(2020), 9)], 1, today: today);
    expect(a.takes, isEmpty);
    expect(a.shortfall, 1);
  });
}
