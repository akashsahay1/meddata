/// Stock valuation: the stock on hand per batch, valued at purchase rate
/// (cost) and at MRP. Pure Dart, money in integer paise.
///
/// The purchase rate is what the shop entered for the batch (the bill's
/// rate / PTR, excluding GST); a batch without one has an unknown cost and
/// is counted apart rather than as zero.
library;

/// One batch's stock on a given date, as the report reads it from the
/// local database.
class StockRow {
  const StockRow({
    required this.batchId,
    required this.productId,
    required this.name,
    this.brand = '',
    this.category = '',
    this.batchNo = '',
    this.unit = '',
    required this.expiry,
    required this.qty,
    required this.mrpPaise,
    required this.costPaise,
  });

  final String batchId;
  final String productId;
  final String name;
  final String brand;
  final String category;
  final String batchNo;
  final String unit;
  final DateTime expiry;

  /// Units on hand.
  final int qty;

  /// MRP per unit (incl. GST).
  final int mrpPaise;

  /// Purchase rate per unit (excl. GST); 0 = not entered.
  final int costPaise;

  bool get hasCost => costPaise > 0;
  int get mrpValuePaise => qty * mrpPaise;

  /// Null when the purchase rate is unknown.
  int? get costValuePaise => hasCost ? qty * costPaise : null;

  /// '' categories read as "Uncategorised".
  String get categoryLabel =>
      category.trim().isEmpty ? 'Uncategorised' : category.trim();

  /// Whole days from [today] to expiry (negative = expired).
  int daysLeft(DateTime today) =>
      _dateOnly(expiry).difference(_dateOnly(today)).inDays;

  /// Expired on [today]: the expiry date is before it (a batch can still be
  /// sold on its expiry date, as elsewhere in the app).
  bool isExpiredOn(DateTime today) => daysLeft(today) < 0;
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Units and value of a set of batches.
class StockValue {
  int batches = 0;
  int units = 0;
  int mrpPaise = 0;

  /// Cost of the batches with a purchase rate.
  int costPaise = 0;

  /// Batches / units / MRP value without a purchase rate (cost unknown).
  int unknownCostBatches = 0;
  int unknownCostUnits = 0;
  int unknownCostMrpPaise = 0;

  bool get hasUnknownCost => unknownCostBatches > 0;
  bool get isEmpty => batches == 0;

  void add(StockRow r) {
    batches++;
    units += r.qty;
    mrpPaise += r.mrpValuePaise;
    final int? cost = r.costValuePaise;
    if (cost == null) {
      unknownCostBatches++;
      unknownCostUnits += r.qty;
      unknownCostMrpPaise += r.mrpValuePaise;
    } else {
      costPaise += cost;
    }
  }

  static StockValue of(Iterable<StockRow> rows) {
    final StockValue v = StockValue();
    rows.forEach(v.add);
    return v;
  }
}

/// Value of one category's stock.
class CategoryValue {
  CategoryValue(this.category);
  final String category;
  final StockValue value = StockValue();
}

class StockValuation {
  StockValuation._({
    required this.asOf,
    required this.nearDays,
    required this.rows,
    required this.sellable,
    required this.nearExpiry,
    required this.expired,
    required this.total,
    required this.byCategory,
    required this.nearExpiryRows,
    required this.expiredRows,
  });

  /// The date the stock is valued on.
  final DateTime asOf;

  /// "Near expiry" = expires within this many days of [asOf].
  final int nearDays;

  /// Batches with stock, by name then expiry.
  final List<StockRow> rows;

  /// Stock not expired on [asOf] (includes near-expiry stock).
  final StockValue sellable;

  /// Part of [sellable] expiring within [nearDays].
  final StockValue nearExpiry;

  /// Stock already expired on [asOf] (a loss until written off).
  final StockValue expired;

  /// [sellable] + [expired].
  final StockValue total;

  /// [sellable] stock per category, highest MRP value first.
  final List<CategoryValue> byCategory;

  /// Soonest expiry first.
  final List<StockRow> nearExpiryRows;

  /// Longest expired first.
  final List<StockRow> expiredRows;

  /// Values [stock] on [asOf]. Batches without stock are left out.
  static StockValuation build(Iterable<StockRow> stock,
      {required DateTime asOf, int nearDays = 30}) {
    final List<StockRow> rows = stock.where((StockRow r) => r.qty > 0).toList()
      ..sort((StockRow a, StockRow b) {
        final int n = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return n != 0 ? n : a.expiry.compareTo(b.expiry);
      });
    final StockValue sellable = StockValue();
    final StockValue near = StockValue();
    final StockValue expired = StockValue();
    final StockValue total = StockValue();
    final Map<String, CategoryValue> cats = <String, CategoryValue>{};
    final List<StockRow> nearRows = <StockRow>[];
    final List<StockRow> expiredRows = <StockRow>[];

    for (final StockRow r in rows) {
      total.add(r);
      final int days = r.daysLeft(asOf);
      if (days < 0) {
        expired.add(r);
        expiredRows.add(r);
        continue;
      }
      sellable.add(r);
      (cats[r.categoryLabel] ??= CategoryValue(r.categoryLabel)).value.add(r);
      if (days <= nearDays) {
        near.add(r);
        nearRows.add(r);
      }
    }
    int byExpiry(StockRow a, StockRow b) => a.expiry.compareTo(b.expiry);
    nearRows.sort(byExpiry);
    expiredRows.sort(byExpiry);
    final List<CategoryValue> byCategory = cats.values.toList()
      ..sort((CategoryValue a, CategoryValue b) {
        final int v = b.value.mrpPaise.compareTo(a.value.mrpPaise);
        return v != 0 ? v : a.category.compareTo(b.category);
      });

    return StockValuation._(
      asOf: _dateOnly(asOf),
      nearDays: nearDays,
      rows: rows,
      sellable: sellable,
      nearExpiry: near,
      expired: expired,
      total: total,
      byCategory: byCategory,
      nearExpiryRows: nearRows,
      expiredRows: expiredRows,
    );
  }
}
