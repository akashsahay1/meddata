import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/inr.dart';
import '../../../domain/reports/expiry_loss.dart';
import '../../../domain/reports/stock_valuation.dart';
import '../../../services/report_export.dart';
import '../../../state/medicine_provider.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/ui_kit.dart';
import 'report_widgets.dart';

/// Expiry loss: what expired unsold, per month (at cost and MRP), what is
/// about to expire in the next 30 / 60 / 90 days, and "write off" for
/// expired stock still on the shelf. Offline, from this device's data.
class ExpirySection extends StatefulWidget {
  const ExpirySection({super.key});

  @override
  State<ExpirySection> createState() => _ExpirySectionState();
}

class _ExpirySectionState extends State<ExpirySection> {
  static final DateFormat _month = DateFormat('MMM yyyy');
  static final DateFormat _dmy = DateFormat('d MMM yyyy');

  ExpiryLoss? _report;
  MedicineProvider? _meds;
  int _request = 0;
  bool _busy = false;

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

  Future<void> _load() async {
    final MedicineProvider? mp = _meds;
    if (mp == null) return;
    final int request = ++_request;
    final List<StockRow> stock = await mp.reports.stockAsOf();
    final List<WriteOff> offs = await mp.reports.writeOffs();
    if (!mounted || request != _request) return;
    setState(() => _report =
        ExpiryLoss.build(stock: stock, writeOffs: offs, today: DateTime.now()));
  }

  Future<void> _writeOff(List<StockRow> rows) async {
    if (rows.isEmpty || _busy) return;
    final StockValue v = StockValue.of(rows);
    final bool one = rows.length == 1;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(one ? 'Write off ${rows.first.name}?' : 'Write off all expired stock?'),
        content: Text(
          '${v.units} unit${v.units == 1 ? '' : 's'} in ${rows.length} '
          'batch${one ? '' : 'es'} will be removed from stock and recorded as '
          'an expiry loss of ${Inr.format(v.costPaise)} at cost '
          '(${Inr.format(v.mrpPaise)} at MRP). This syncs to your other devices.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Write off'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final MedicineProvider mp = context.read<MedicineProvider>();
    final int units =
        await mp.writeOffExpired(rows.map((StockRow r) => r.batchId));
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Wrote off $units unit${units == 1 ? '' : 's'} of expired stock.')));
  }

  @override
  Widget build(BuildContext context) {
    final ExpiryLoss? e = _report;
    if (e == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final List<ExpiryMonth> months = e.months.take(12).toList();
    final int maxMonth =
        months.fold(0, (int m, ExpiryMonth x) => x.mrpPaise > m ? x.mrpPaise : m);
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
      children: <Widget>[
        const SectionHeader(title: 'About to expire'),
        const SizedBox(height: 6),
        const ReportNote('Value of stock expiring soon - return it to the '
            'supplier or sell it at a discount while you can.'),
        const SizedBox(height: 12),
        for (final ExpiryWindow w in e.windows) ...<Widget>[
          _windowRow(w),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 12),
        StatPair(
          StatCard(
            label: 'Expired, not written off',
            value: Inr.format(e.pending.costPaise),
            sub: 'at cost · ${Inr.format(e.pending.mrpPaise)} MRP',
          ),
          StatCard(
            label: 'Written off so far',
            value: Inr.format(e.writtenOff.costPaise),
            sub: 'at cost · ${Inr.format(e.writtenOff.mrpPaise)} MRP',
          ),
        ),
        if (e.pending.hasUnknownCost || e.writtenOff.hasUnknownCost) ...<Widget>[
          const SizedBox(height: 8),
          const ReportNote('Some batches have no purchase rate; they count '
              'at MRP only.'),
        ],
        if (e.pendingRows.isNotEmpty) ...<Widget>[
          const SizedBox(height: 22),
          const SectionHeader(title: 'Expired stock to write off'),
          const SizedBox(height: 6),
          const ReportNote('Writing off removes the stock (so it leaves the '
              'stock value) and records the loss.'),
          const SizedBox(height: 12),
          ReportCard(
            child: Column(children: <Widget>[
              for (final StockRow r in e.pendingRows)
                BatchLine(
                  title: r.name,
                  subtitle: '${r.batchNo.isEmpty ? 'No batch no.' : 'Batch ${r.batchNo}'}'
                      ' · ${r.qty} units · expired ${_dmy.format(r.expiry)}',
                  value: r.hasCost ? Inr.format(r.costValuePaise!) : 'No cost',
                  valueDetail: 'MRP ${Inr.format(r.mrpValuePaise)}',
                  action: TapTarget(
                    label: 'Write off ${r.name}'
                        '${r.batchNo.isEmpty ? '' : ', batch ${r.batchNo}'}',
                    onTap: _busy ? null : () => _writeOff(<StockRow>[r]),
                    child: const Icon(Icons.delete_sweep_outlined,
                        color: AppColors.green),
                  ),
                ),
            ]),
          ),
          if (e.pendingRows.length > 1) ...<Widget>[
            const SizedBox(height: 12),
            SecondaryButton(
              label: 'Write off all expired',
              icon: Icons.delete_sweep_outlined,
              onPressed: _busy ? null : () => _writeOff(e.pendingRows),
            ),
          ],
        ],
        const SizedBox(height: 22),
        const SectionHeader(title: 'Expiry loss by month'),
        const SizedBox(height: 6),
        const ReportNote('Stock that expired unsold, by the month it expired '
            '(at MRP; cost below).'),
        const SizedBox(height: 12),
        ReportCard(
          child: months.isEmpty
              ? const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: ReportNote('Nothing has expired unsold yet.'),
                )
              : Column(children: <Widget>[
                  for (final ExpiryMonth m in months)
                    ValueBar(
                      label: _month.format(m.month),
                      value: Inr.format(m.mrpPaise),
                      fraction: maxMonth == 0 ? 0 : m.mrpPaise / maxMonth,
                      detail: 'Cost ${Inr.format(m.costPaise)} · ${m.units} units'
                          '${m.pending.isEmpty ? '' : ' · ${m.pending.units} not written off'}',
                    ),
                ]),
        ),
        if (e.upcoming.isNotEmpty) ...<Widget>[
          const SizedBox(height: 22),
          SectionHeader(
              title: 'Expiring in the next ${e.windows.last.days} days'),
          const SizedBox(height: 12),
          ReportCard(
            child: Column(children: <Widget>[
              for (final StockRow r in e.upcoming)
                BatchLine(
                  title: r.name,
                  subtitle: '${r.batchNo.isEmpty ? 'No batch no.' : 'Batch ${r.batchNo}'}'
                      ' · ${r.qty} units · ${_daysText(r.daysLeft(e.today))}',
                  value: r.hasCost ? Inr.format(r.costValuePaise!) : 'No cost',
                  valueDetail: 'MRP ${Inr.format(r.mrpValuePaise)}',
                ),
            ]),
          ),
        ],
        const SizedBox(height: 20),
        ExportRow(doc: ReportExport.expiry(e)),
      ],
    );
  }

  static String _daysText(int d) => d == 0
      ? 'expires today'
      : 'expires in $d day${d == 1 ? '' : 's'}';

  Widget _windowRow(ExpiryWindow w) {
    return ReportCard(
      padding: const EdgeInsets.all(14),
      child: Semantics(
        container: true,
        label: 'Next ${w.days} days: ${Inr.format(w.value.costPaise)} at cost, '
            '${Inr.format(w.value.mrpPaise)} at MRP, ${w.value.batches} batches',
        excludeSemantics: true,
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Next ${w.days} days',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  ReportNote('${w.value.batches} batch'
                      '${w.value.batches == 1 ? '' : 'es'} · ${w.value.units} units'),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  Inr.format(w.value.costPaise),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                ReportNote('MRP ${Inr.format(w.value.mrpPaise)}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
