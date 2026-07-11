import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../data/models/medicine.dart';
import '../../services/settings_service.dart';
import '../../state/medicine_provider.dart';
import '../../theme/app_theme.dart';
import '../widgets/ui_kit.dart';
import 'upgrade_screen.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final SettingsService settings = context.watch<SettingsService>();
    final MedicineProvider mp = context.watch<MedicineProvider>();

    if (!settings.isPremium) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reports')),
        body: _PremiumLock(
          onUpgrade: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const UpgradeScreen()),
          ),
        ),
      );
    }

    final String cur = settings.currency;
    final Map<String, int> byCategory = _byCategory(mp.visibleAllForAlerts);
    final int maxCat =
        byCategory.values.fold(0, (int a, int b) => a > b ? a : b);
    final Color amber = mp.lowStockCount > 0 ? AppColors.statusAmber : AppColors.muted;
    final Color expSoon = mp.expiringCount > 0 ? AppColors.statusRed : AppColors.muted;
    final Color expired = mp.expiredCount > 0 ? AppColors.statusRed : AppColors.muted;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Export PDF',
            onPressed: () => _exportPdf(context, mp, cur),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: <Widget>[
          const SectionHeader(title: 'Overview'),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: StatCard(
                  label: 'Total medicines',
                  value: '${mp.totalCount}',
                  sub: '${byCategory.length} categories',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatCard(
                  label: 'Stock value',
                  value: Fmt.money(mp.totalStockValue, symbol: cur),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: StatCard(
                  label: 'Expiring soon',
                  value: '${mp.expiringCount}',
                  sub: 'Needs attention',
                  subColor: expSoon,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatCard(
                  label: 'Expired',
                  value: '${mp.expiredCount}',
                  sub: 'Remove from stock',
                  subColor: expired,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: StatCard(
                  label: 'Low stock',
                  value: '${mp.lowStockCount}',
                  sub: 'Reorder soon',
                  subColor: amber,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatCard(
                  label: 'Expired value',
                  value: Fmt.money(_expiredValue(mp), symbol: cur),
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          const SectionHeader(title: 'Medicines by category'),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(AppRadii.card),
              border: Border.all(color: AppColors.border),
            ),
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
            child: byCategory.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      'No category data yet.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.muted,
                      ),
                    ),
                  )
                : Column(
                    children: <Widget>[
                      for (final MapEntry<String, int> e in byCategory.entries)
                        _BarRow(label: e.key, value: e.value, max: maxCat),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Map<String, int> _byCategory(List<Medicine> all) {
    final Map<String, int> map = <String, int>{};
    for (final Medicine m in all) {
      final String key = m.category.trim().isEmpty ? 'Uncategorised' : m.category.trim();
      map[key] = (map[key] ?? 0) + 1;
    }
    final List<MapEntry<String, int>> sorted = map.entries.toList()
      ..sort((MapEntry<String, int> a, MapEntry<String, int> b) =>
          b.value.compareTo(a.value));
    return Map<String, int>.fromEntries(sorted.take(8));
  }

  double _expiredValue(MedicineProvider mp) {
    double v = 0;
    for (final Medicine m in mp.visibleAllForAlerts) {
      if (mp.statusOf(m).isExpired) v += m.stockValue;
    }
    return v;
  }

  Future<void> _exportPdf(
      BuildContext context, MedicineProvider mp, String cur) async {
    final pw.Document doc = pw.Document();
    final Map<String, int> byCat = _byCategory(mp.visibleAllForAlerts);
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.Text('Medicine Stock Report',
                style: pw.TextStyle(
                    fontSize: 22, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 12),
            pw.Text('Total medicines: ${mp.totalCount}'),
            pw.Text('Stock value: ${Fmt.money(mp.totalStockValue, symbol: cur)}'),
            pw.Text('Expiring soon: ${mp.expiringCount}'),
            pw.Text('Expired: ${mp.expiredCount}'),
            pw.Text('Low stock: ${mp.lowStockCount}'),
            pw.SizedBox(height: 16),
            pw.Text('By category',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            ...byCat.entries.map((MapEntry<String, int> e) =>
                pw.Text('${e.key}: ${e.value}')),
          ],
        ),
      ),
    );
    await Printing.sharePdf(
        bytes: await doc.save(), filename: 'med_stock_report.pdf');
  }
}

class _BarRow extends StatelessWidget {
  final String label;
  final int value;
  final int max;
  const _BarRow({required this.label, required this.value, required this.max});

  @override
  Widget build(BuildContext context) {
    final double frac = max == 0 ? 0 : value / max;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              Text(
                '$value',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          // Green fill on a soft canvas track.
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) => Container(
              height: 10,
              decoration: BoxDecoration(
                color: AppColors.canvas,
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: c.maxWidth * frac,
                  height: 10,
                  decoration: BoxDecoration(
                    color: AppColors.green,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumLock extends StatelessWidget {
  final VoidCallback onUpgrade;
  const _PremiumLock({required this.onUpgrade});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 76,
              height: 76,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.statusAmberBg,
                borderRadius: BorderRadius.circular(AppRadii.cardLg),
              ),
              child: const Icon(Icons.lock_outline,
                  size: 34, color: AppColors.statusAmber),
            ),
            const SizedBox(height: 20),
            const Text(
              'Reports are a Premium feature',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Upgrade to see stock value, expiry trends, category breakdowns '
              'and export PDF reports.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                fontWeight: FontWeight.w500,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 24),
            PrimaryButton(
              label: 'Upgrade to Premium',
              icon: Icons.workspace_premium_outlined,
              onPressed: onUpgrade,
            ),
          ],
        ),
      ),
    );
  }
}
