import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../data/models/medicine.dart';
import '../../domain/medicine_status.dart';
import '../../state/medicine_provider.dart';
import '../widgets/status_chip.dart';
import 'medicine_detail_screen.dart';

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final MedicineProvider mp = context.watch<MedicineProvider>();

    final List<Medicine> expired = <Medicine>[];
    final List<Medicine> expiring = <Medicine>[];
    final List<Medicine> low = <Medicine>[];

    for (final Medicine m in mp.visibleAllForAlerts) {
      final MedicineStatus s = mp.statusOf(m);
      if (s.isExpired) {
        expired.add(m);
      } else if (s.isExpiring) {
        expiring.add(m);
      }
      if (s.isLowStock) low.add(m);
    }
    expiring.sort((Medicine a, Medicine b) =>
        a.expiryDate.compareTo(b.expiryDate));

    final bool empty = expired.isEmpty && expiring.isEmpty && low.isEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Alerts')),
      body: empty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.check_circle_outline, size: 56),
                    SizedBox(height: 16),
                    Text('All good',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    SizedBox(height: 8),
                    Text('No expiring, expired or low-stock items.',
                        textAlign: TextAlign.center),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                if (expired.isNotEmpty)
                  _Section(title: 'Expired', items: expired, mp: mp),
                if (expiring.isNotEmpty)
                  _Section(title: 'Expiring soon', items: expiring, mp: mp),
                if (low.isNotEmpty)
                  _Section(title: 'Low stock', items: low, mp: mp),
              ],
            ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Medicine> items;
  final MedicineProvider mp;
  const _Section(
      {required this.title, required this.items, required this.mp});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text('$title (${items.length})',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.onSurface),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: <Widget>[
              for (int i = 0; i < items.length; i++) ...<Widget>[
                ListTile(
                  title: Text(items[i].name,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                      '${items[i].quantity} ${items[i].unit} · Exp ${Fmt.dateShort(items[i].expiryDate)}'),
                  trailing: StatusChip.forExpiry(mp.statusOf(items[i])),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          MedicineDetailScreen(medicineId: items[i].id),
                    ),
                  ),
                ),
                if (i != items.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
