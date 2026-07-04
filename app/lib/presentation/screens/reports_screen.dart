import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../data/models/medicine.dart';
import '../../services/settings_service.dart';
import '../../state/medicine_provider.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Export PDF',
            onPressed: () => _exportPdf(context, mp, cur),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _statRow(context, <List<String>>[
            <String>['Total medicines', '${mp.totalCount}'],
            <String>['Stock value', Fmt.money(mp.totalStockValue, symbol: cur)],
          ]),
          const SizedBox(height: 12),
          _statRow(context, <List<String>>[
            <String>['Expiring soon', '${mp.expiringCount}'],
            <String>['Expired', '${mp.expiredCount}'],
          ]),
          const SizedBox(height: 12),
          _statRow(context, <List<String>>[
            <String>['Low stock', '${mp.lowStockCount}'],
            <String>[
              'Expired value',
              Fmt.money(_expiredValue(mp), symbol: cur)
            ],
          ]),
          const SizedBox(height: 24),
          const Text('Medicines by category',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          if (byCategory.isEmpty)
            const Text('No category data yet.')
          else
            ...byCategory.entries.map((MapEntry<String, int> e) =>
                _BarRow(label: e.key, value: e.value, max: maxCat)),
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

  Widget _statRow(BuildContext context, List<List<String>> stats) {
    return Row(
      children: <Widget>[
        for (int i = 0; i < stats.length; i++) ...<Widget>[
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border:
                    Border.all(color: Theme.of(context).colorScheme.onSurface),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(stats[i][1],
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(stats[i][0], style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
          if (i != stats.length - 1) const SizedBox(width: 12),
        ],
      ],
    );
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
    final Color fg = Theme.of(context).colorScheme.onSurface;
    final double frac = max == 0 ? 0 : value / max;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600))),
              Text('$value', style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 4),
          // Monochrome bar: black fill on bordered track.
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) => Container(
              height: 14,
              decoration: BoxDecoration(
                border: Border.all(color: fg),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: (c.maxWidth - 2) * frac,
                  decoration: BoxDecoration(
                    color: fg,
                    borderRadius: BorderRadius.circular(2),
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
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.lock_outline, size: 56),
            const SizedBox(height: 16),
            const Text('Reports are a Premium feature',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
              'Upgrade to see stock value, expiry trends, category breakdowns '
              'and export PDF reports.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: onUpgrade, child: const Text('Upgrade')),
          ],
        ),
      ),
    );
  }
}
