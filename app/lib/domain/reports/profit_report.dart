/// Gross profit over a date range, as computed by the server from the
/// shop's bills (GET /reports/profit). Money in integer paise.
///
/// Revenue is the taxable value (price excluding GST, after discount); cost
/// is units sold x the batch's purchase rate (excluding GST). Lines whose
/// batch has no purchase rate have an unknown cost: they are left out of
/// cost, profit and margin and listed in [ProfitReport.unknownCost].
library;

int _int(Object? v) => (v as num?)?.toInt() ?? 0;

/// Totals of one day / product / category (or the whole range).
class ProfitRow {
  const ProfitRow({
    this.key = '',
    this.label = '',
    this.category = '',
    required this.qtyUnits,
    required this.revenuePaise,
    required this.salesPaise,
    required this.costedRevenuePaise,
    required this.costPaise,
    required this.profitPaise,
    required this.marginBp,
    required this.unknownCostQtyUnits,
    required this.unknownCostRevenuePaise,
    this.bills = 0,
  });

  /// [key]: the date (Y-m-d), product id or category; [label] what to show.
  factory ProfitRow.fromJson(Map<String, dynamic> j,
          {String key = '', String label = ''}) =>
      ProfitRow(
        key: key,
        label: label,
        category: (j['category'] as String?) ?? '',
        qtyUnits: _int(j['qty_units']),
        revenuePaise: _int(j['revenue_paise']),
        salesPaise: _int(j['sales_paise']),
        costedRevenuePaise: _int(j['costed_revenue_paise']),
        costPaise: _int(j['cost_paise']),
        profitPaise: _int(j['profit_paise']),
        marginBp: (j['margin_bp'] as num?)?.toInt(),
        unknownCostQtyUnits: _int(j['unknown_cost_qty_units']),
        unknownCostRevenuePaise: _int(j['unknown_cost_revenue_paise']),
        bills: _int(j['bills']),
      );

  final String key;
  final String label;
  final String category;
  final int qtyUnits;

  /// Excluding GST, after discount.
  final int revenuePaise;

  /// What customers paid (incl. GST).
  final int salesPaise;

  /// Revenue of the lines with a known cost (what margin is taken over).
  final int costedRevenuePaise;
  final int costPaise;
  final int profitPaise;

  /// Basis points (2386 = 23.86%); null when no line has a known cost.
  final int? marginBp;
  final int unknownCostQtyUnits;
  final int unknownCostRevenuePaise;
  final int bills;

  bool get hasUnknownCost => unknownCostQtyUnits > 0;
}

/// A batch sold without a purchase rate.
class UnknownCostLine {
  const UnknownCostLine({
    required this.productId,
    required this.batchId,
    required this.name,
    required this.batchNo,
    required this.qtyUnits,
    required this.revenuePaise,
  });

  factory UnknownCostLine.fromJson(Map<String, dynamic> j) => UnknownCostLine(
        productId: '${j['product_id'] ?? ''}',
        batchId: '${j['batch_id'] ?? ''}',
        name: (j['name'] as String?) ?? '',
        batchNo: (j['batch_no'] as String?) ?? '',
        qtyUnits: _int(j['qty_units']),
        revenuePaise: _int(j['revenue_paise']),
      );

  final String productId;
  final String batchId;
  final String name;
  final String batchNo;
  final int qtyUnits;
  final int revenuePaise;
}

class ProfitReport {
  const ProfitReport({
    required this.from,
    required this.to,
    required this.totals,
    required this.byDay,
    required this.byProduct,
    required this.byCategory,
    required this.unknownCost,
  });

  factory ProfitReport.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> list(String k) => <Map<String, dynamic>>[
          for (final Object? o in (j[k] as List<dynamic>?) ?? <dynamic>[])
            if (o is Map) Map<String, dynamic>.from(o),
        ];
    return ProfitReport(
      from: DateTime.parse('${j['from']}'),
      to: DateTime.parse('${j['to']}'),
      totals: ProfitRow.fromJson(
          Map<String, dynamic>.from((j['totals'] as Map?) ?? <String, dynamic>{}),
          label: 'Total'),
      byDay: <ProfitRow>[
        for (final Map<String, dynamic> d in list('by_day'))
          ProfitRow.fromJson(d, key: '${d['date']}', label: '${d['date']}'),
      ],
      byProduct: <ProfitRow>[
        for (final Map<String, dynamic> p in list('by_product'))
          ProfitRow.fromJson(p,
              key: '${p['product_id']}', label: (p['name'] as String?) ?? ''),
      ],
      byCategory: <ProfitRow>[
        for (final Map<String, dynamic> c in list('by_category'))
          ProfitRow.fromJson(c,
              key: '${c['category']}', label: '${c['category']}'),
      ],
      unknownCost: list('unknown_cost').map(UnknownCostLine.fromJson).toList(),
    );
  }

  final DateTime from;
  final DateTime to;
  final ProfitRow totals;

  /// Oldest day first; only days with sales.
  final List<ProfitRow> byDay;

  /// Highest revenue first.
  final List<ProfitRow> byProduct;
  final List<ProfitRow> byCategory;
  final List<UnknownCostLine> unknownCost;

  bool get isEmpty => totals.qtyUnits == 0;
}

/// "23.86%" from basis points; "–" when unknown.
String marginText(int? bp) {
  if (bp == null) return '–';
  final String sign = bp < 0 ? '-' : '';
  final int a = bp.abs();
  return '$sign${a ~/ 100}.${(a % 100).toString().padLeft(2, '0')}%';
}
