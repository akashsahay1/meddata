import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../data/models/medicine.dart';
import '../../domain/medicine_status.dart';
import 'status_chip.dart';

/// One row in the medicine list. Fully monochrome; status via chips.
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
    final Color fg = Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        medicine.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      if (medicine.brand.isNotEmpty ||
                          medicine.batchNo.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            <String>[
                              if (medicine.brand.isNotEmpty) medicine.brand,
                              if (medicine.batchNo.isNotEmpty)
                                'Batch ${medicine.batchNo}',
                            ].join('  ·  '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: fg),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      '${medicine.quantity} ${medicine.unit}',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Exp ${Fmt.dateShort(medicine.expiryDate)}',
                      style: TextStyle(fontSize: 12, color: fg),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                StatusChip.forExpiry(status),
                if (medicine.quantity == 0)
                  StatusChip.outOfStock()
                else if (status.isLowStock)
                  StatusChip.lowStock(),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
