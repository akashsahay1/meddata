import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/inr.dart';
import '../../../domain/reports/stock_valuation.dart';
import '../../../services/report_export.dart';
import '../../../services/settings_service.dart';
import '../../../state/medicine_provider.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/ui_kit.dart';
import 'report_widgets.dart';

/// Stock valuation: stock on hand valued at purchase rate (cost) and MRP,
/// with a category breakdown and the expired / near-expiry stock apart.
/// Read from this device's inventory, so it works offline; a past date is
/// worked out from the stock ledger (today's stock minus later movements).
class StockValueSection extends StatefulWidget {
  const StockValueSection({super.key});

  @override
  State<StockValueSection> createState() => _StockValueSectionState();
}

class _StockValueSectionState extends State<StockValueSection> {
  static final DateFormat _dmy = DateFormat('d MMM yyyy');

  DateTime? _asOf; // null = today
  StockValuation? _report;
  MedicineProvider? _meds;
  int _request = 0;
  bool _showAll = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final MedicineProvider mp = context.read<MedicineProvider>();
    if (!identical(mp, _meds)) {
      _meds?.removeListener(_load);
      _meds = mp..addListener(_load);
      _load();
    }
  }

  @override
  void dispose() {
    _meds?.removeListener(_load);
    super.dispose();
  }

  DateTime get _today {
    final DateTime n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  Future<void> _load() async {
    final MedicineProvider? mp = _meds;
    if (mp == null) return;
    final int request = ++_request;
    final int nearDays = context.read<SettingsService>().warningDays;
    final DateTime asOf = _asOf ?? _today;
    final List<StockRow> rows = await mp.reports.stockAsOf(_asOf);
    if (!mounted || request != _request) return;
    setState(() => _report =
        StockValuation.build(rows, asOf: asOf, nearDays: nearDays));
  }

  Future<void> _pickDate() async {
    final DateTime? d = await showDatePicker(
      context: context,
      initialDate: _asOf ?? _today,
      firstDate: DateTime(2020),
      lastDate: _today,
      helpText: 'Value stock as of',
    );
    if (d == null || !mounted) return;
    setState(() {
      _asOf = d == _today ? null : d;
      _report = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final StockValuation? v = _report;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
      children: <Widget>[
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 6,
          children: <Widget>[
            Text(
              _asOf == null ? 'As of today' : 'As of ${_dmy.format(_asOf!)}',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            TextButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.event_outlined, size: 18),
              label: const Text('Change date'),
            ),
            if (_asOf != null)
              TextButton(
                onPressed: () {
                  setState(() => _asOf = null);
                  _load();
                },
                child: const Text('Today'),
              ),
          ],
        ),
        if (_asOf != null)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: ReportNote('Stock on that date from the stock history, '
                'valued at today\'s prices. Deleted batches are not included.'),
          ),
        const SizedBox(height: 8),
        if (v == null)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else ..._body(v),
      ],
    );
  }

  List<Widget> _body(StockValuation v) {
    final int maxCat = v.byCategory.fold(
        0, (int m, CategoryValue c) => c.value.mrpPaise > m ? c.value.mrpPaise : m);
    final List<StockRow> sellable =
        v.rows.where((StockRow r) => !r.isExpiredOn(v.asOf)).toList();
    final List<StockRow> shown =
        _showAll ? sellable : sellable.take(15).toList();
    return <Widget>[
      StatPair(
        StatCard(
          label: 'Stock at cost',
          value: Inr.format(v.sellable.costPaise),
          sub: v.sellable.hasUnknownCost
              ? '${v.sellable.unknownCostBatches} without purchase rate'
              : '${v.sellable.units} units',
          subColor: v.sellable.hasUnknownCost
              ? AppColors.ink
              : AppColors.muted,
        ),
        StatCard(
          label: 'Stock at MRP',
          value: Inr.format(v.sellable.mrpPaise),
          sub: '${v.sellable.batches} batches',
        ),
      ),
      const SizedBox(height: 12),
      StatPair(
        StatCard(
          label: 'Expiring in ${v.nearDays} days',
          value: Inr.format(v.nearExpiry.costPaise),
          sub: 'at cost · ${Inr.format(v.nearExpiry.mrpPaise)} MRP',
        ),
        StatCard(
          label: 'Expired',
          value: Inr.format(v.expired.costPaise),
          sub: 'at cost · ${Inr.format(v.expired.mrpPaise)} MRP',
        ),
      ),
      const SizedBox(height: 10),
      const ReportNote('Cost is the purchase rate entered for each batch '
          '(excluding GST); MRP includes GST. Expired stock is not in the '
          'stock value - write it off in the Expiry tab.'),
      if (v.total.hasUnknownCost) ...<Widget>[
        const SizedBox(height: 6),
        ReportNote('${v.total.unknownCostBatches} batch'
            '${v.total.unknownCostBatches == 1 ? ' has' : 'es have'} no purchase '
            'rate (${Inr.format(v.total.unknownCostMrpPaise)} at MRP) and '
            'are left out of the cost figures. Add the rate on the batch.'),
      ],
      const SizedBox(height: 22),
      const SectionHeader(title: 'By category (at MRP)'),
      const SizedBox(height: 12),
      ReportCard(
        child: v.byCategory.isEmpty
            ? const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: ReportNote('No stock on this date.'),
              )
            : Column(
                children: <Widget>[
                  for (final CategoryValue c in v.byCategory)
                    ValueBar(
                      label: c.category,
                      value: Inr.format(c.value.mrpPaise),
                      fraction: maxCat == 0 ? 0 : c.value.mrpPaise / maxCat,
                      detail: 'Cost ${Inr.format(c.value.costPaise)} · '
                          '${c.value.units} units',
                    ),
                ],
              ),
      ),
      if (v.nearExpiryRows.isNotEmpty) ...<Widget>[
        const SizedBox(height: 22),
        SectionHeader(title: 'Expiring within ${v.nearDays} days'),
        const SizedBox(height: 12),
        ReportCard(
          child: Column(children: <Widget>[
            for (final StockRow r in v.nearExpiryRows) _line(r, v.asOf),
          ]),
        ),
      ],
      if (v.expiredRows.isNotEmpty) ...<Widget>[
        const SizedBox(height: 22),
        const SectionHeader(title: 'Expired stock'),
        const SizedBox(height: 12),
        ReportCard(
          child: Column(children: <Widget>[
            for (final StockRow r in v.expiredRows) _line(r, v.asOf),
          ]),
        ),
      ],
      const SizedBox(height: 22),
      SectionHeader(
        title: 'Stock by batch',
        actionLabel: sellable.length > 15
            ? (_showAll ? 'Show less' : 'Show all ${sellable.length}')
            : null,
        onAction: () => setState(() => _showAll = !_showAll),
      ),
      const SizedBox(height: 12),
      ReportCard(
        child: shown.isEmpty
            ? const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: ReportNote('No stock on this date.'),
              )
            : Column(children: <Widget>[
                for (final StockRow r in shown) _line(r, v.asOf),
              ]),
      ),
      const SizedBox(height: 20),
      ExportRow(doc: ReportExport.stockValuation(v)),
    ];
  }

  Widget _line(StockRow r, DateTime asOf) {
    final int days = r.daysLeft(asOf);
    final String when = days < 0
        ? 'expired ${-days} day${days == -1 ? '' : 's'} ago'
        : days == 0
            ? 'expires today'
            : 'exp ${DateFormat('MMM yy').format(r.expiry)}';
    return BatchLine(
      title: r.name,
      subtitle: '${r.batchNo.isEmpty ? 'No batch no.' : 'Batch ${r.batchNo}'}'
          ' · ${r.qty} ${r.unit.isEmpty ? 'units' : r.unit.toLowerCase()} · $when',
      value: r.hasCost ? Inr.format(r.costValuePaise!) : 'No cost',
      valueDetail: 'MRP ${Inr.format(r.mrpValuePaise)}',
    );
  }
}
