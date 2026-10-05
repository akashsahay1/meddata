import 'package:flutter_test/flutter_test.dart';
import 'package:med_stock/domain/reports/expiry_loss.dart';
import 'package:med_stock/domain/reports/stock_valuation.dart';

final DateTime today = DateTime(2026, 10, 5);

StockRow row(
  String name, {
  int qty = 10,
  int mrp = 3000,
  int cost = 2000,
  int expiresIn = 200,
  String category = 'Pain Relief',
  String batch = 'B1',
}) =>
    StockRow(
      batchId: '$name-$batch',
      productId: name,
      name: name,
      category: category,
      batchNo: batch,
      expiry: DateTime(today.year, today.month, today.day + expiresIn),
      qty: qty,
      mrpPaise: mrp,
      costPaise: cost,
    );

void main() {
  group('StockValuation', () {
    test('values sellable stock at cost and MRP, expired apart', () {
      final StockValuation v = StockValuation.build(<StockRow>[
        row('Dolo 650', qty: 10, mrp: 3000, cost: 2000),
        row('Azithral', qty: 4, mrp: 12000, cost: 8000, category: 'Antibiotic'),
        row('Cough Syrup', qty: 3, mrp: 11250, cost: 7000, expiresIn: 20,
            category: ''),
        row('Old Tonic', qty: 2, mrp: 5000, cost: 3000, expiresIn: -1),
        row('Sold out', qty: 0),
      ], asOf: today, nearDays: 30);

      expect(v.rows.map((StockRow r) => r.name),
          <String>['Azithral', 'Cough Syrup', 'Dolo 650', 'Old Tonic']);
      // 10x20 + 4x80 + 3x70 = 200 + 320 + 210 rupees
      expect(v.sellable.costPaise, 20000 + 32000 + 21000);
      expect(v.sellable.mrpPaise, 30000 + 48000 + 33750);
      expect(v.sellable.units, 17);
      expect(<int>[v.nearExpiry.costPaise, v.nearExpiry.mrpPaise],
          <int>[21000, 33750]);
      expect(<int>[v.expired.costPaise, v.expired.mrpPaise, v.expired.units],
          <int>[6000, 10000, 2]);
      expect(v.total.mrpPaise, v.sellable.mrpPaise + v.expired.mrpPaise);
      expect(v.expiredRows.single.name, 'Old Tonic');
      expect(v.nearExpiryRows.single.name, 'Cough Syrup');

      // Categories of sellable stock, highest MRP value first.
      expect(
          v.byCategory.map((CategoryValue c) =>
              '${c.category} ${c.value.costPaise}/${c.value.mrpPaise}'),
          <String>[
            'Antibiotic 32000/48000',
            'Uncategorised 21000/33750',
            'Pain Relief 20000/30000',
          ]);
    });

    test('a batch can be sold on its expiry date; the day after it is expired',
        () {
      final StockValuation v = StockValuation.build(<StockRow>[
        row('Today', expiresIn: 0),
        row('Yesterday', expiresIn: -1),
      ], asOf: today);
      expect(v.sellable.batches, 1);
      expect(v.nearExpiryRows.single.name, 'Today');
      expect(v.expiredRows.single.name, 'Yesterday');
    });

    test('no purchase rate = unknown cost, not zero and not counted', () {
      final StockValuation v = StockValuation.build(<StockRow>[
        row('Dolo 650', qty: 10, cost: 2000),
        row('Mystery', qty: 5, mrp: 4000, cost: 0),
      ], asOf: today);
      expect(v.sellable.costPaise, 20000);
      expect(v.sellable.mrpPaise, 30000 + 20000);
      expect(v.sellable.hasUnknownCost, isTrue);
      expect(<int>[
        v.sellable.unknownCostBatches,
        v.sellable.unknownCostUnits,
        v.sellable.unknownCostMrpPaise,
      ], <int>[1, 5, 20000]);
      expect(v.rows.last.costValuePaise, isNull);
    });

    test('values on the as-of date', () {
      // Expires 10 days from today: 40 days before today it was 50 days out.
      final StockValuation then = StockValuation.build(
          <StockRow>[row('Dolo 650', expiresIn: 10)],
          asOf: today.subtract(const Duration(days: 40)),
          nearDays: 30);
      expect(then.nearExpiry.isEmpty, isTrue);
      expect(then.sellable.batches, 1);
    });
  });

  group('ExpiryLoss', () {
    WriteOff off(String name, int units, DateTime expiry, DateTime at,
            {int cost = 2000, int mrp = 3000}) =>
        WriteOff(
          batchId: '$name-b',
          productId: name,
          name: name,
          expiry: expiry,
          units: units,
          at: at,
          mrpPaise: mrp,
          costPaise: cost,
        );

    test('expired stock by month: written off and still on the shelf', () {
      final ExpiryLoss e = ExpiryLoss.build(
        stock: <StockRow>[
          // Expired 5 Sep, not written off.
          row('Old Tonic', qty: 2, mrp: 5000, cost: 3000, expiresIn: -30),
          // Expired 3 Oct.
          row('Eye Drops', qty: 1, mrp: 8000, cost: 0, expiresIn: -2),
          row('Fresh', qty: 10, expiresIn: 200),
        ],
        writeOffs: <WriteOff>[
          off('Dolo 650', 4, DateTime(2026, 9, 30), DateTime(2026, 10, 2)),
          off('Crocin', 6, DateTime(2026, 8, 31), DateTime(2026, 9, 1),
              cost: 1500, mrp: 2500),
          off('Nothing', 0, DateTime(2026, 8, 31), DateTime(2026, 9, 1)),
        ],
        today: today,
      );

      expect(e.months.map((ExpiryMonth m) => m.month),
          <DateTime>[DateTime(2026, 10), DateTime(2026, 9), DateTime(2026, 8)]);
      final ExpiryMonth sep = e.months[1];
      expect(<int>[sep.writtenOff.costPaise, sep.pending.costPaise, sep.costPaise],
          <int>[8000, 6000, 14000]);
      expect(sep.mrpPaise, 12000 + 10000);
      expect(sep.units, 6);
      final ExpiryMonth oct = e.months[0];
      expect(<Object>[oct.costPaise, oct.mrpPaise, oct.hasUnknownCost],
          <Object>[0, 8000, true]);
      expect(e.months[2].writtenOff.costPaise, 9000);

      expect(<int>[e.writtenOff.costPaise, e.writtenOff.mrpPaise],
          <int>[8000 + 9000, 12000 + 15000]);
      expect(<int>[e.pending.costPaise, e.pending.mrpPaise], <int>[6000, 18000]);
      expect(e.pendingRows.map((StockRow r) => r.name),
          <String>['Old Tonic', 'Eye Drops']);
      expect(e.writeOffs.map((WriteOff w) => w.name), <String>['Dolo 650', 'Crocin']);
    });

    test('next 30 / 60 / 90 days are cumulative', () {
      final ExpiryLoss e = ExpiryLoss.build(
        stock: <StockRow>[
          row('A', qty: 1, cost: 1000, mrp: 1500, expiresIn: 0),
          row('B', qty: 1, cost: 2000, mrp: 2500, expiresIn: 30),
          row('C', qty: 1, cost: 4000, mrp: 5000, expiresIn: 31),
          row('D', qty: 1, cost: 8000, mrp: 9000, expiresIn: 90),
          row('E', qty: 1, cost: 16000, mrp: 20000, expiresIn: 91),
          row('Empty', qty: 0, expiresIn: 5),
          row('Gone', qty: 3, expiresIn: -1),
        ],
        writeOffs: const <WriteOff>[],
        today: today,
      );
      expect(e.windows.map((ExpiryWindow w) => w.days), <int>[30, 60, 90]);
      expect(e.windows.map((ExpiryWindow w) => w.value.costPaise),
          <int>[3000, 7000, 15000]);
      expect(e.windows.map((ExpiryWindow w) => w.value.mrpPaise),
          <int>[4000, 9000, 18000]);
      expect(e.upcoming.map((StockRow r) => r.name), <String>['A', 'B', 'C', 'D']);
      expect(e.months.single.pending.units, 3);
    });

    test('nothing expired', () {
      final ExpiryLoss e = ExpiryLoss.build(
          stock: <StockRow>[row('Fresh')],
          writeOffs: const <WriteOff>[],
          today: today);
      expect(e.months, isEmpty);
      expect(e.pending.isEmpty && e.writtenOff.isEmpty, isTrue);
    });
  });
}
