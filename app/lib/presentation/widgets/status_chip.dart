import 'package:flutter/material.dart';

import '../../domain/medicine_status.dart';

/// A monochrome status pill. Distinction is by border style + icon + weight,
/// never by color. Expired = filled (inverted), Expiring = solid border,
/// Low stock = dashed-look via double border, OK = subtle.
class StatusChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool emphasized; // inverted fill for the most urgent state
  final bool bold;

  const StatusChip({
    super.key,
    required this.label,
    required this.icon,
    this.emphasized = false,
    this.bold = true,
  });

  factory StatusChip.forExpiry(MedicineStatus s) {
    switch (s.expiryState) {
      case ExpiryState.expired:
        return StatusChip(
          label: s.expiryLabel,
          icon: Icons.error_outline,
          emphasized: true,
        );
      case ExpiryState.expiring:
        return StatusChip(label: s.expiryLabel, icon: Icons.schedule);
      case ExpiryState.ok:
        return StatusChip(
          label: 'OK',
          icon: Icons.check_circle_outline,
          bold: false,
        );
    }
  }

  static Widget lowStock() => const StatusChip(
        label: 'LOW STOCK',
        icon: Icons.inventory_2_outlined,
      );

  static Widget outOfStock() => const StatusChip(
        label: 'OUT OF STOCK',
        icon: Icons.remove_shopping_cart_outlined,
        emphasized: true,
      );

  @override
  Widget build(BuildContext context) {
    final Color fg = Theme.of(context).colorScheme.onSurface;
    final Color bg = Theme.of(context).colorScheme.surface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: emphasized ? fg : bg,
        border: Border.all(color: fg, width: emphasized ? 1 : 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13, color: emphasized ? bg : fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 0.3,
              height: 1,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: emphasized ? bg : fg,
            ),
          ),
        ],
      ),
    );
  }
}
