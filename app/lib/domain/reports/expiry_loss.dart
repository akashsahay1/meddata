/// Expiry loss: stock that expired unsold, per month, and the stock about
/// to expire (so the owner can return it or sell it at a discount). Pure
/// Dart, money in integer paise.
///
/// A month is the batch's expiry month - when the stock stopped being
/// sellable - whether it has been written off since or is still on the
/// shelf. Write-offs are `expiry_writeoff` stock movements.
library;

import 'stock_valuation.dart';

/// Stock written off as expired (one movement).
class WriteOff {
  const WriteOff({
    required this.batchId,
    required this.productId,
    required this.name,
    this.category = '',
    this.batchNo = '',
    required this.expiry,
    required this.units,
    required this.at,
    required this.mrpPaise,
    required this.costPaise,
  });

  final String batchId;
  final String productId;
  final String name;
  final String category;
  final String batchNo;
  final DateTime expiry;

  /// Units removed (positive).
  final int units;

  /// When it was written off.
  final DateTime at;

  /// The batch's MRP / purchase rate per unit (0 = not entered).
  final int mrpPaise;
  final int costPaise;

  /// The same units as a [StockRow], to value them the same way.
  StockRow get asRow => StockRow(
        batchId: batchId,
        productId: productId,
        name: name,
        category: category,
        batchNo: batchNo,
        expiry: expiry,
        qty: units,
        mrpPaise: mrpPaise,
        costPaise: costPaise,
      );
}

/// Expired stock of one expiry month.
class ExpiryMonth {
  ExpiryMonth(this.month);

  /// First day of the month.
  final DateTime month;

  /// Already written off.
  final StockValue writtenOff = StockValue();

  /// Expired but still counted in stock (not written off yet).
  final StockValue pending = StockValue();

  int get costPaise => writtenOff.costPaise + pending.costPaise;
  int get mrpPaise => writtenOff.mrpPaise + pending.mrpPaise;
  int get units => writtenOff.units + pending.units;
  bool get hasUnknownCost => writtenOff.hasUnknownCost || pending.hasUnknownCost;
}

/// Stock expiring within [days] from today (not yet expired).
class ExpiryWindow {
  ExpiryWindow(this.days);
  final int days;
  final StockValue value = StockValue();
}

class ExpiryLoss {
  ExpiryLoss._({
    required this.today,
    required this.months,
    required this.writtenOff,
    required this.pending,
    required this.windows,
    required this.upcoming,
    required this.pendingRows,
    required this.writeOffs,
  });

  final DateTime today;

  /// Newest month first; only months with expired stock.
  final List<ExpiryMonth> months;

  /// All written-off / pending expired stock.
  final StockValue writtenOff;
  final StockValue pending;

  /// Cumulative windows: next 30, 60 and 90 days.
  final List<ExpiryWindow> windows;

  /// Batches expiring within the longest window, soonest first.
  final List<StockRow> upcoming;

  /// Expired batches still in stock (can be written off), oldest first.
  final List<StockRow> pendingRows;

  /// Every write-off, newest first.
  final List<WriteOff> writeOffs;

  static const List<int> windowDays = <int>[30, 60, 90];

  /// [stock] = current stock per batch; [writeOffs] = expiry write-offs.
  static ExpiryLoss build({
    required Iterable<StockRow> stock,
    required Iterable<WriteOff> writeOffs,
    required DateTime today,
    List<int> windowDays = windowDays,
  }) {
    final DateTime day = DateTime(today.year, today.month, today.day);
    final Map<DateTime, ExpiryMonth> months = <DateTime, ExpiryMonth>{};
    ExpiryMonth monthOf(DateTime expiry) {
      final DateTime m = DateTime(expiry.year, expiry.month);
      return months[m] ??= ExpiryMonth(m);
    }

    final StockValue writtenOff = StockValue();
    final StockValue pending = StockValue();
    final List<WriteOff> offs = writeOffs.where((WriteOff w) => w.units > 0).toList()
      ..sort((WriteOff a, WriteOff b) => b.at.compareTo(a.at));
    for (final WriteOff w in offs) {
      writtenOff.add(w.asRow);
      monthOf(w.expiry).writtenOff.add(w.asRow);
    }

    final List<int> sortedDays = List<int>.of(windowDays)..sort();
    final List<ExpiryWindow> windows = <ExpiryWindow>[
      for (final int d in sortedDays) ExpiryWindow(d),
    ];
    final int longest = sortedDays.isEmpty ? 0 : sortedDays.last;
    final List<StockRow> upcoming = <StockRow>[];
    final List<StockRow> pendingRows = <StockRow>[];
    for (final StockRow r in stock) {
      if (r.qty <= 0) continue;
      final int days = r.daysLeft(day);
      if (days < 0) {
        pending.add(r);
        pendingRows.add(r);
        monthOf(r.expiry).pending.add(r);
        continue;
      }
      for (final ExpiryWindow w in windows) {
        if (days <= w.days) w.value.add(r);
      }
      if (days <= longest) upcoming.add(r);
    }
    int byExpiry(StockRow a, StockRow b) => a.expiry.compareTo(b.expiry);
    upcoming.sort(byExpiry);
    pendingRows.sort(byExpiry);

    return ExpiryLoss._(
      today: day,
      months: months.values.toList()
        ..sort((ExpiryMonth a, ExpiryMonth b) => b.month.compareTo(a.month)),
      writtenOff: writtenOff,
      pending: pending,
      windows: windows,
      upcoming: upcoming,
      pendingRows: pendingRows,
      writeOffs: offs,
    );
  }
}
