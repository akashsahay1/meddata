import 'pack_size.dart';

/// A batch as the bill screen sells it: the batch's price, stock and
/// version, plus the product details a bill line needs.
class SaleBatch {
  const SaleBatch({
    required this.id,
    required this.productId,
    required this.productName,
    this.unit = '',
    this.packSize = 1,
    this.batchNo = '',
    required this.expiryDate,
    required this.mrpPaise,
    required this.version,
    required this.qty,
    this.hsn = '',
    this.gstRateBp,
    this.discountBp = 0,
  });

  final String id;
  final String productId;
  final String productName;
  final String unit;

  /// Pieces per pack of the product (tablets per strip); 1 when not set.
  final int packSize;
  final String batchNo;
  final DateTime expiryDate;
  final int mrpPaise;

  /// The batch's edit_version on the server, sent with the bill so the
  /// server can refuse it if the batch (its price) changed since.
  final int version;

  /// Units in stock as this device knows it.
  final int qty;
  final String hsn;

  /// Null: not set on the product (the shop's default rate applies).
  final int? gstRateBp;

  /// The product's default selling discount.
  final int discountBp;

  /// Pieces [mrpPaise] covers (a strip, or one unit).
  int get pricePack => PackSize.pricePack(unit, packSize);

  /// Expired = the expiry date is before today (it can be sold on the day).
  bool isExpiredOn(DateTime today) => _day(expiryDate).isBefore(_day(today));

  SaleBatch copyWith({int? mrpPaise, int? version, int? qty}) => SaleBatch(
        id: id,
        productId: productId,
        productName: productName,
        unit: unit,
        packSize: packSize,
        batchNo: batchNo,
        expiryDate: expiryDate,
        mrpPaise: mrpPaise ?? this.mrpPaise,
        version: version ?? this.version,
        qty: qty ?? this.qty,
        hsn: hsn,
        gstRateBp: gstRateBp,
        discountBp: discountBp,
      );

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
}

/// Units taken from one batch.
class BatchTake {
  const BatchTake(this.batch, this.qty);
  final SaleBatch batch;
  final int qty;
}

class FefoAllocation {
  const FefoAllocation(this.takes, this.shortfall);
  final List<BatchTake> takes;

  /// Units that no sellable batch could supply (0 = fully allocated).
  final int shortfall;

  bool get isComplete => shortfall == 0;
}

/// First expiry, first out: a sale takes stock from the batch that expires
/// soonest, then the next, and never from an expired or empty batch.
class Fefo {
  Fefo._();

  /// Batches a sale may take from, earliest expiry first.
  static List<SaleBatch> sellable(Iterable<SaleBatch> batches, DateTime today) {
    final List<SaleBatch> out = batches
        .where((SaleBatch b) => b.qty > 0 && !b.isExpiredOn(today))
        .toList()
      ..sort(_order);
    return out;
  }

  /// Split [qty] units over the batches. A [pinnedBatchId] (the user chose
  /// that batch) is used first; the rest spills over in FEFO order.
  static FefoAllocation allocate(Iterable<SaleBatch> batches, int qty,
      {required DateTime today, String? pinnedBatchId}) {
    final List<SaleBatch> order = sellable(batches, today);
    final int pinned = order.indexWhere((SaleBatch b) => b.id == pinnedBatchId);
    if (pinned > 0) order.insert(0, order.removeAt(pinned));

    final List<BatchTake> takes = <BatchTake>[];
    int left = qty;
    for (final SaleBatch b in order) {
      if (left <= 0) break;
      final int take = left < b.qty ? left : b.qty;
      takes.add(BatchTake(b, take));
      left -= take;
    }
    return FefoAllocation(takes, left > 0 ? left : 0);
  }

  static int _order(SaleBatch a, SaleBatch b) {
    final int byExpiry = a.expiryDate.compareTo(b.expiryDate);
    if (byExpiry != 0) return byExpiry;
    final int byNo = a.batchNo.compareTo(b.batchNo);
    return byNo != 0 ? byNo : a.id.compareTo(b.id);
  }
}
