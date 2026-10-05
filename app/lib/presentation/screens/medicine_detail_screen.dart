import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../data/models/medicine.dart';
import '../../data/models/stock_movement.dart';
import '../../domain/medicine_status.dart';
import '../../services/settings_service.dart';
import '../../state/medicine_provider.dart';
import '../../theme/app_theme.dart';
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
        backgroundColor: AppColors.canvas,
        body: Center(child: Text('Medicine not found')),
      );
    }
    final Medicine med = m;
    final MedicineStatus status = mp.statusOf(med);
    final String cur = settings.currency;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Details',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
            letterSpacing: -0.2,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.ink),
        actions: <Widget>[
          _AppBarAction(
            icon: Icons.edit_outlined,
            label: 'Edit medicine',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AddEditMedicineScreen(existing: med),
              ),
            ),
          ),
          _AppBarAction(
            icon: Icons.delete_outline,
            label: 'Delete medicine',
            color: AppColors.statusRed,
            onTap: () => _delete(context, med),
          ),
          // With the 48dp touch areas, the delete button keeps its place.
          const SizedBox(width: 7),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 32),
        children: <Widget>[
          _HeaderCard(medicine: med, status: status),
          const SizedBox(height: 16),
          _QuantityCard(medicine: med),
          const SizedBox(height: 16),
          _infoCard(<List<String>>[
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
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.statusRed),
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

  Widget _infoCard(List<List<String>> rows) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < rows.length; i++) ...<Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 140,
                    child: Text(
                      rows[i][0],
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      rows[i][1],
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (i != rows.length - 1)
              const Divider(height: 1, thickness: 1, color: AppColors.divider),
          ],
        ],
      ),
    );
  }
}

class _AppBarAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  const _AppBarAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = AppColors.ink,
  });

  @override
  Widget build(BuildContext context) {
    // 38dp button, 48dp touch area.
    return TapTarget(
      label: label,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.card,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: 19, color: color),
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final Medicine medicine;
  final MedicineStatus status;
  const _HeaderCard({required this.medicine, required this.status});

  @override
  Widget build(BuildContext context) {
    final List<String> subParts = <String>[
      if (medicine.brand.isNotEmpty) medicine.brand,
      if (medicine.category.isNotEmpty) medicine.category,
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.cardLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              InitialsAvatar(
                text: initialsOf(medicine.name),
                size: 56,
                color: AppColors.green,
                bg: AppColors.canvas,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      medicine.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                        letterSpacing: -0.3,
                        height: 1.1,
                      ),
                    ),
                    if (subParts.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          subParts.join(' · '),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              // Expiry chip reads "In stock" when the date is fine; only show
              // that when there's no stock problem to report instead.
              if (status.expiryState != ExpiryState.ok ||
                  (medicine.quantity > 0 && !status.isLowStock))
                StatusChip.forExpiry(status),
              if (medicine.quantity == 0)
                StatusChip.outOfStock()
              else if (status.isLowStock)
                StatusChip.lowStock(),
            ],
          ),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Row(
        children: <Widget>[
          _stepBtn(
            icon: Icons.remove,
            label: 'Remove 1 from stock',
            filled: false,
            onTap: () =>
                mp.adjustQuantity(medicine.id, -1, StockReason.sell),
          ),
          Expanded(
            child: Column(
              children: <Widget>[
                Text(
                  '${medicine.quantity}',
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                    letterSpacing: -0.5,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'in stock (${medicine.unit})',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          _stepBtn(
            icon: Icons.add,
            label: 'Add 1 to stock',
            filled: true,
            onTap: () =>
                mp.adjustQuantity(medicine.id, 1, StockReason.restock),
          ),
        ],
      ),
    );
  }

  Widget _stepBtn({
    required IconData icon,
    required String label,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return TapTarget(
      label: label,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.input),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: filled ? AppColors.orange : AppColors.canvas,
            border: filled ? null : Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppRadii.input),
          ),
          child: Icon(
            icon,
            size: 24,
            color: filled ? Colors.white : AppColors.green,
          ),
        ),
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
        final int shown = moves.length < 20 ? moves.length : 20;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SectionHeader(title: 'Stock history'),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: AppColors.card,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(AppRadii.card),
              ),
              child: Column(
                children: <Widget>[
                  for (int i = 0; i < shown; i++) ...<Widget>[
                    _movementRow(moves[i]),
                    if (i != shown - 1)
                      const Divider(
                          height: 1,
                          thickness: 1,
                          color: AppColors.divider),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _movementRow(StockMovement move) {
    final bool up = move.change >= 0;
    final Color accent = up ? AppColors.statusGreen : AppColors.statusRed;
    final Color accentBg = up ? AppColors.statusGreenBg : AppColors.statusRedBg;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accentBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              up ? Icons.arrow_upward : Icons.arrow_downward,
              size: 17,
              color: accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${up ? '+' : ''}${move.change} ${move.reason.name}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
          Text(
            Fmt.dateShort(move.createdAt),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}
