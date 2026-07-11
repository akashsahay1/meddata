import 'package:flutter/material.dart';

import '../../domain/medicine_status.dart';
import '../../theme/app_theme.dart';
import 'ui_kit.dart';

// Re-export the shared kit so files importing status_chip.dart also get the
// new widgets (StatusPill, MedicineTile, etc.).
export 'ui_kit.dart';

/// Maps a computed [MedicineStatus] (+ quantity) to the right colored pill.
StatusPill medicineStatusPill(MedicineStatus s, int quantity) {
  if (s.isExpired) return StatusPill.danger('Expired');
  if (s.isExpiring) return StatusPill.danger('Expiring');
  if (quantity == 0) return StatusPill.danger('Out of stock');
  if (s.isLowStock) return StatusPill.low();
  return StatusPill.inStock();
}

/// Backwards-compatible status label. Now rendered as a colored [StatusPill]
/// per the new design; the old {label, icon, emphasized, bold} API is kept so
/// existing call sites keep compiling.
class StatusChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool emphasized;
  final bool bold;
  final Color color;
  final Color bg;

  const StatusChip({
    super.key,
    required this.label,
    this.icon = Icons.circle,
    this.emphasized = false,
    this.bold = true,
    this.color = AppColors.statusGreen,
    this.bg = AppColors.statusGreenBg,
  });

  factory StatusChip.forExpiry(MedicineStatus s) {
    switch (s.expiryState) {
      case ExpiryState.expired:
        return const StatusChip(
          label: 'Expired',
          icon: Icons.error_outline,
          color: AppColors.statusRed,
          bg: AppColors.statusRedBg,
        );
      case ExpiryState.expiring:
        return const StatusChip(
          label: 'Expiring',
          icon: Icons.schedule,
          color: AppColors.statusRed,
          bg: AppColors.statusRedBg,
        );
      case ExpiryState.ok:
        return const StatusChip(
          label: 'In stock',
          icon: Icons.check_circle_outline,
          color: AppColors.statusGreen,
          bg: AppColors.statusGreenBg,
        );
    }
  }

  static Widget lowStock() => const StatusChip(
        label: 'Low',
        icon: Icons.inventory_2_outlined,
        color: AppColors.statusAmber,
        bg: AppColors.statusAmberBg,
      );

  static Widget outOfStock() => const StatusChip(
        label: 'Out of stock',
        icon: Icons.remove_shopping_cart_outlined,
        color: AppColors.statusRed,
        bg: AppColors.statusRedBg,
      );

  @override
  Widget build(BuildContext context) {
    return StatusPill(text: label, color: color, bg: bg);
  }
}
