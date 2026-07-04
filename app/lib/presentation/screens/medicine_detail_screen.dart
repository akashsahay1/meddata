import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../data/models/medicine.dart';
import '../../data/models/stock_movement.dart';
import '../../domain/medicine_status.dart';
import '../../services/settings_service.dart';
import '../../state/medicine_provider.dart';
import '../widgets/status_chip.dart';
import 'add_edit_medicine_screen.dart';

class MedicineDetailScreen extends StatelessWidget {
  final String medicineId;
  const MedicineDetailScreen({super.key, required this.medicineId});

  @override
  Widget build(BuildContext context) {
    final MedicineProvider mp = context.watch<MedicineProvider>();
    final SettingsService settings = context.watch<SettingsService>();
    final Medicine? m = mp.findById(medicineId);

    if (m == null) {
      return const Scaffold(
        body: Center(child: Text('Medicine not found')),
      );
    }
    final Medicine med = m;
    final MedicineStatus status = mp.statusOf(med);
    final String cur = settings.currency;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Details'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AddEditMedicineScreen(existing: med),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _delete(context, med),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(med.name,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          if (med.brand.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(med.brand, style: const TextStyle(fontSize: 15)),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              StatusChip.forExpiry(status),
              if (med.quantity == 0)
                StatusChip.outOfStock()
              else if (status.isLowStock)
                StatusChip.lowStock(),
            ],
          ),
          const SizedBox(height: 20),
          _QuantityCard(medicine: med),
          const SizedBox(height: 16),
          _infoCard(context, <List<String>>[
            <String>['Quantity', '${med.quantity} ${med.unit}'],
            <String>['Low-stock alert at', '${med.lowStockThreshold}'],
            <String>['Expiry date', Fmt.date(med.expiryDate)],
            if (med.mfgDate != null)
              <String>['Manufacture date', Fmt.date(med.mfgDate!)],
            if (med.category.isNotEmpty) <String>['Category', med.category],
            if (med.batchNo.isNotEmpty) <String>['Batch / lot', med.batchNo],
            if (med.barcode.isNotEmpty) <String>['Barcode', med.barcode],
            if (med.purchasePrice > 0)
              <String>['Purchase price', Fmt.money(med.purchasePrice, symbol: cur)],
            if (med.sellingPrice > 0)
              <String>['Selling price', Fmt.money(med.sellingPrice, symbol: cur)],
            if (med.sellingPrice > 0)
              <String>['Stock value', Fmt.money(med.stockValue, symbol: cur)],
            if (med.notes.isNotEmpty) <String>['Notes', med.notes],
          ]),
          const SizedBox(height: 16),
          _MovementHistory(medicineId: med.id),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context, Medicine med) async {
    final MedicineProvider mp = context.read<MedicineProvider>();
    final bool ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: const Text('Delete medicine?'),
            content: Text('Remove ${med.name} from your stock?'),
            actions: <Widget>[
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel')),
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Delete')),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    await mp.delete(med.id);
    if (context.mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Deleted ${med.name}'),
          action: SnackBarAction(
            label: 'UNDO',
            onPressed: () => mp.undoDelete(med.id),
          ),
        ),
      );
    }
  }

  Widget _infoCard(BuildContext context, List<List<String>> rows) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.onSurface),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < rows.length; i++) ...<Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 140,
                    child: Text(rows[i][0],
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  Expanded(child: Text(rows[i][1])),
                ],
              ),
            ),
            if (i != rows.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _QuantityCard extends StatelessWidget {
  final Medicine medicine;
  const _QuantityCard({required this.medicine});

  @override
  Widget build(BuildContext context) {
    final MedicineProvider mp = context.read<MedicineProvider>();
    final Color fg = Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: fg),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: <Widget>[
          _roundBtn(context, Icons.remove, () {
            mp.adjustQuantity(medicine.id, -1, StockReason.sell);
          }),
          Expanded(
            child: Column(
              children: <Widget>[
                Text('${medicine.quantity}',
                    style: const TextStyle(
                        fontSize: 32, fontWeight: FontWeight.w800)),
                Text(medicine.unit, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
          _roundBtn(context, Icons.add, () {
            mp.adjustQuantity(medicine.id, 1, StockReason.restock);
          }),
        ],
      ),
    );
  }

  Widget _roundBtn(BuildContext context, IconData icon, VoidCallback onTap) {
    final Color fg = Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          border: Border.all(color: fg, width: 2),
          shape: BoxShape.circle,
        ),
        child: Icon(icon),
      ),
    );
  }
}

class _MovementHistory extends StatelessWidget {
  final String medicineId;
  const _MovementHistory({required this.medicineId});

  @override
  Widget build(BuildContext context) {
    final MedicineProvider mp = context.read<MedicineProvider>();
    return FutureBuilder<List<StockMovement>>(
      future: mp.movementsFor(medicineId),
      builder: (BuildContext context,
          AsyncSnapshot<List<StockMovement>> snapshot) {
        final List<StockMovement> moves = snapshot.data ?? <StockMovement>[];
        if (moves.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Stock history',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                border:
                    Border.all(color: Theme.of(context).colorScheme.onSurface),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: <Widget>[
                  for (int i = 0; i < moves.length && i < 20; i++) ...<Widget>[
                    ListTile(
                      dense: true,
                      leading: Icon(
                        moves[i].change >= 0 ? Icons.add : Icons.remove,
                        size: 18,
                      ),
                      title: Text(
                        '${moves[i].change >= 0 ? '+' : ''}${moves[i].change} · ${moves[i].reason.name}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      trailing: Text(Fmt.dateShort(moves[i].createdAt)),
                    ),
                    if (i != moves.length - 1 && i < 19)
                      const Divider(height: 1),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
