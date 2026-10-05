import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/inr.dart';
import '../../../domain/reports/profit_report.dart';
import '../../../services/auth_service.dart';
import '../../../services/billing_api.dart';
import '../../../services/report_export.dart';
import '../../../services/reports_api.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/ui_kit.dart';
import 'report_widgets.dart';

enum ProfitRange { last7, thisMonth, lastMonth, custom }

/// Gross profit and margin from the shop's bills, worked out on the server
/// (bills live there), so it needs the internet.
class ProfitSection extends StatefulWidget {
  const ProfitSection({super.key, this.api, this.now});

  final ReportsApi? api;

  /// Today, for tests.
  final DateTime? now;

  @override
  State<ProfitSection> createState() => _ProfitSectionState();
}

class _ProfitSectionState extends State<ProfitSection> {
  static final DateFormat _dmy = DateFormat('d MMM yyyy');
  late final ReportsApi _api = widget.api ?? ReportsApi();

  ProfitRange _range = ProfitRange.thisMonth;
  DateTimeRange? _custom;
  ProfitReport? _report;
  ApiOutcome<ProfitReport>? _failure;
  bool _loading = false;
  bool _allProducts = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  DateTime get _today {
    final DateTime n = widget.now ?? DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  DateTimeRange _dates() {
    final DateTime t = _today;
    return switch (_range) {
      ProfitRange.last7 =>
        DateTimeRange(start: t.subtract(const Duration(days: 6)), end: t),
      ProfitRange.thisMonth => DateTimeRange(start: DateTime(t.year, t.month), end: t),
      ProfitRange.lastMonth => DateTimeRange(
          start: DateTime(t.year, t.month - 1), end: DateTime(t.year, t.month, 0)),
      ProfitRange.custom => _custom ?? DateTimeRange(start: t, end: t),
    };
  }

  Future<void> _load() async {
    if (!mounted) return;
    final String? token = context.read<AuthService>().token;
    final int request = ++_request;
    if (token == null) {
      setState(() {
        _report = null;
        _failure = const ApiOutcome<ProfitReport>.failed(401, 'signed_out');
      });
      return;
    }
    setState(() {
      _loading = true;
      _failure = null;
    });
    final DateTimeRange d = _dates();
    final ApiOutcome<ProfitReport> r =
        await _api.profit(token, from: d.start, to: d.end);
    if (!mounted || request != _request) return;
    setState(() {
      _loading = false;
      _report = r.value;
      _failure = r.isOk ? null : r;
    });
  }

  Future<void> _pick(ProfitRange r) async {
    if (r == ProfitRange.custom) {
      final DateTimeRange? picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: _today,
        initialDateRange: _custom ?? _dates(),
        helpText: 'Profit for',
      );
      if (picked == null || !mounted) return;
      if (picked.duration.inDays > 365) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Choose a range of at most a year.')));
        return;
      }
      _custom = picked;
    }
    setState(() => _range = r);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final DateTimeRange d = _dates();
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
      children: <Widget>[
        Wrap(
          spacing: 8,
          children: <Widget>[
            for (final (ProfitRange r, String label) in <(ProfitRange, String)>[
              (ProfitRange.thisMonth, 'This month'),
              (ProfitRange.last7, 'Last 7 days'),
              (ProfitRange.lastMonth, 'Last month'),
              (ProfitRange.custom, 'Choose dates'),
            ])
              _RangePill(
                label: label,
                selected: _range == r,
                onTap: () => _pick(r),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${_dmy.format(d.start)} – ${_dmy.format(d.end)}',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 12),
        ..._content(),
      ],
    );
  }

  List<Widget> _content() {
    final ApiOutcome<ProfitReport>? f = _failure;
    if (f != null) {
      if (f.message == 'signed_out') {
        return const <Widget>[
          ReportMessage(
            icon: Icons.person_outline,
            title: 'Log in to see profit',
            body: 'Profit is worked out from your bills on the Meddata '
                'server. Log in (Profile) and connect to the internet.',
          ),
        ];
      }
      if (f.isOffline) {
        return <Widget>[
          ReportMessage(
            icon: Icons.wifi_off_rounded,
            title: 'You are offline',
            body: 'Profit is worked out from your bills on the Meddata '
                'server, so it needs the internet. Stock value and expiry '
                'reports work offline.',
            actionLabel: 'Try again',
            onAction: _load,
          ),
        ];
      }
      return <Widget>[
        ReportMessage(
          icon: Icons.error_outline,
          title: 'Could not load profit',
          body: f.message ?? 'Something went wrong. Please try again.',
          actionLabel: 'Try again',
          onAction: _load,
        ),
      ];
    }
    final ProfitReport? r = _report;
    if (r == null || _loading) {
      return const <Widget>[
        Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (r.isEmpty) {
      return const <Widget>[
        ReportMessage(
          icon: Icons.receipt_long_outlined,
          title: 'No sales in these dates',
          body: 'Profit comes from your bills. Cancelled bills are not counted.',
        ),
      ];
    }
    final ProfitRow t = r.totals;
    return <Widget>[
      StatPair(
        StatCard(
          label: 'Gross profit',
          value: Inr.format(t.profitPaise),
          sub: 'Margin ${marginText(t.marginBp)}',
          subColor: AppColors.ink,
        ),
        StatCard(
          label: 'Revenue',
          value: Inr.format(t.revenuePaise),
          sub: 'excl. GST · ${t.bills} bill${t.bills == 1 ? '' : 's'}',
        ),
      ),
      const SizedBox(height: 12),
      StatPair(
        StatCard(
          label: 'Cost of goods',
          value: Inr.format(t.costPaise),
          sub: 'at purchase rate',
        ),
        StatCard(
          label: 'Sales incl. GST',
          value: Inr.format(t.salesPaise),
          sub: '${t.qtyUnits} units sold',
        ),
      ),
      const SizedBox(height: 10),
      const ReportNote('Revenue is the bill value excluding GST, after '
          'discount. Cost is units sold x the batch purchase rate (excluding '
          'GST). Cancelled bills are not counted.'),
      if (r.unknownCost.isNotEmpty) ...<Widget>[
        const SizedBox(height: 16),
        _unknownCost(r),
      ],
      if (r.byDay.length > 1) ...<Widget>[
        const SizedBox(height: 22),
        const SectionHeader(title: 'By day'),
        const SizedBox(height: 12),
        ReportCard(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ColumnChart(
                columns: <ChartColumn>[
                  for (final ProfitRow x in r.byDay)
                    ChartColumn(x.key.substring(8), x.revenuePaise, x.profitPaise),
                ],
                semanticLabel: 'Revenue and profit per day, ${r.byDay.length} '
                    'days with sales. Figures are listed below.',
              ),
              const SizedBox(height: 10),
              const Wrap(
                spacing: 16,
                runSpacing: 4,
                children: <Widget>[
                  LegendItem(color: AppColors.green, text: 'Gross profit'),
                  LegendItem(color: AppColors.page, text: 'Revenue'),
                ],
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 12),
      ReportCard(
        child: Column(children: <Widget>[
          for (final ProfitRow x in r.byDay.reversed)
            BatchLine(
              title: DateFormat('EEE, d MMM').format(DateTime.parse(x.key)),
              subtitle: 'Revenue ${Inr.format(x.revenuePaise)}'
                  '${x.hasUnknownCost ? ' · some without cost' : ''}',
              value: Inr.format(x.profitPaise),
              valueDetail: marginText(x.marginBp),
            ),
        ]),
      ),
      const SizedBox(height: 22),
      const SectionHeader(title: 'By category'),
      const SizedBox(height: 12),
      ReportCard(child: _bars(r.byCategory)),
      const SizedBox(height: 22),
      SectionHeader(
        title: 'By medicine',
        actionLabel: r.byProduct.length > 10
            ? (_allProducts ? 'Show less' : 'Show all ${r.byProduct.length}')
            : null,
        onAction: () => setState(() => _allProducts = !_allProducts),
      ),
      const SizedBox(height: 12),
      ReportCard(
        child: _bars(_allProducts ? r.byProduct : r.byProduct.take(10).toList()),
      ),
      const SizedBox(height: 20),
      ExportRow(doc: ReportExport.profit(r)),
    ];
  }

  /// Profit per row as bars (the longest = the biggest profit or loss).
  Widget _bars(List<ProfitRow> rows) {
    final int max = rows.fold(
        0, (int m, ProfitRow x) => x.profitPaise.abs() > m ? x.profitPaise.abs() : m);
    return Column(children: <Widget>[
      for (final ProfitRow x in rows)
        ValueBar(
          label: x.label,
          value: Inr.format(x.profitPaise),
          fraction: max == 0 ? 0 : x.profitPaise.abs() / max,
          negative: x.profitPaise < 0,
          detail: '${x.marginBp == null ? 'No purchase rate' : '${marginText(x.marginBp)} margin'}'
              ' · revenue ${Inr.format(x.revenuePaise)} · '
              '${x.qtyUnits} unit${x.qtyUnits == 1 ? '' : 's'}'
              '${x.hasUnknownCost && x.marginBp != null ? ' · ${x.unknownCostQtyUnits} without cost' : ''}',
        ),
    ]);
  }

  Widget _unknownCost(ProfitReport r) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.statusAmberBg,
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(Icons.info_outline, size: 20, color: AppColors.ink),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Some sales have no purchase rate',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${Inr.format(r.totals.unknownCostRevenuePaise)} of revenue is not '
            'in profit or margin because these batches have no purchase rate. '
            'Add the rate on the batch and the report updates.',
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          for (final UnknownCostLine u in r.unknownCost.take(8))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '• ${u.name}${u.batchNo.isEmpty ? '' : ' (${u.batchNo})'}: '
                '${u.qtyUnits} sold, ${Inr.format(u.revenuePaise)}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
            ),
          if (r.unknownCost.length > 8)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'and ${r.unknownCost.length - 8} more (in the export)',
                style: const TextStyle(fontSize: 12.5, color: AppColors.ink),
              ),
            ),
        ],
      ),
    );
  }
}

/// A date-range choice: a pill like the Bills / Inventory filters, with a
/// 48dp touch area.
class _RangePill extends StatelessWidget {
  const _RangePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TapTarget(
      label: label,
      tooltip: false,
      selected: selected,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.green : AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? AppColors.green : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.ink,
          ),
        ),
      ),
    );
  }
}
