import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../data/models/medicine.dart';
import '../../domain/medicine_status.dart';
import 'status_chip.dart';

export 'ui_kit.dart';

/// One row in the medicine list, now rendered as the new white [MedicineTile].
/// The public API ({medicine, status, onTap}) is unchanged so existing call
/// sites keep working.
class MedicineListTile extends StatelessWidget {
  final Medicine medicine;
  final MedicineStatus status;
  final VoidCallback onTap;

  const MedicineListTile({
    super.key,
    required this.medicine,
    required this.status,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final List<String> subParts = <String>[
      if (medicine.brand.isNotEmpty) medicine.brand,
      if (medicine.category.isNotEmpty) medicine.category,
    ];
    return MedicineTile(
      name: medicine.name,
      subtitle: subParts.join(' · '),
      status: medicineStatusPill(status, medicine.quantity),
      qtyLabel: '${medicine.quantity} ${medicine.unit}',
      priceLabel:
          medicine.sellingPrice > 0 ? Fmt.money(medicine.sellingPrice) : null,
      expLabel: 'Exp ${Fmt.dateShort(medicine.expiryDate)}',
      onTap: onTap,
    );
  }
}
