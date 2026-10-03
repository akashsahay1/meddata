import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../data/models/medicine.dart';
import '../../domain/medicine_status.dart';
import '../../domain/product_stock.dart';
import '../../state/medicine_provider.dart';
import '../../theme/app_theme.dart';
import '../widgets/status_chip.dart';
import 'add_edit_medicine_screen.dart';
import 'medicine_detail_screen.dart';

/// One medicine with all its batches: total stock, and each batch's number,
/// expiry, stock and MRP. Tapping a batch opens it (stock +/−, history,
/// edit); "Add batch" records new stock of this medicine.
class ProductDetailScreen extends StatelessWidget {
  final String productId;
  const ProductDetailScreen({super.key, required this.productId});

  @override
  Widget build(BuildContext context) {
    final MedicineProvider mp = context.watch<MedicineProvider>();
    final ProductStock? p = mp.productById(productId);
    if (p == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This medicine was removed.')),
      );
    }

    final List<String> sub = <String>[
      if (p.brand.isNotEmpty) p.brand,
      if (p.category.isNotEmpty) p.category,
      p.unit,
    ];

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(p.name, overflow: TextOverflow.ellipsis)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => AddEditMedicineScreen(newBatchOf: p.first))),
        icon: const Icon(Icons.add),
        label: const Text('Add batch'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 100),
        children: <Widget>[
          Text(sub.join(' · '), style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(AppRadii.card),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('${p.totalQty} ${p.unit}',
                          style: const TextStyle(
                              fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.ink)),
                      const SizedBox(height: 2),
                      Text(
                        'in stock across ${p.batches.length} '
                        '${p.batches.length == 1 ? 'batch' : 'batches'}',
                        style: const TextStyle(color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                if (p.isLowStock)
                  medicineStatusPill(
                      const MedicineStatus(
                          expiryState: ExpiryState.ok, daysToExpiry: 999, isLowStock: true),
                      p.totalQty),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text('Low-stock alert at ${p.lowStockThreshold} ${p.unit}',
              style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 22),
          const Text('Batches',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink)),
          const SizedBox(height: 4),
          const Text('Earliest expiry first — sell these first.',
              style: TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 12),
          for (final Medicine b in p.batches) ...<Widget>[
            _batchTile(context, mp, b),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _batchTile(BuildContext context, MedicineProvider mp, Medicine b) {
    final MedicineStatus s = mp.statusOf(b);
    // Per-batch view: expiry of this batch; empty batches say so.
    final MedicineStatus batchOnly = MedicineStatus(
        expiryState: b.quantity > 0 ? s.expiryState : ExpiryState.ok,
        daysToExpiry: s.daysToExpiry,
        isLowStock: false);
    return MedicineTile(
      name: b.batchNo.isEmpty ? 'No batch no.' : 'Batch ${b.batchNo}',
      subtitle: b.sellingPrice > 0 ? 'MRP ${Fmt.money(b.sellingPrice)}' : null,
      initials: 'B',
      status: medicineStatusPill(batchOnly, b.quantity),
      qtyLabel: '${b.quantity} ${b.unit}',
      expLabel: 'Exp ${Fmt.dateShort(b.expiryDate)}',
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => MedicineDetailScreen(medicineId: b.id))),
    );
  }
}
