import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

export 'ui_kit.dart';

/// A dashboard stat tile, reskinned to the new white rounded card. The public
/// API ({label, value, icon, emphasized, onTap}) is preserved so existing call
/// sites keep working.
class SummaryTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool emphasized;
  final VoidCallback? onTap;

  const SummaryTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.emphasized = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color accent = emphasized ? AppColors.statusRed : AppColors.green;
    final Color chipBg =
        emphasized ? AppColors.statusRedBg : AppColors.canvas;

    final Widget content = Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x140A302E),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: chipBg,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 18, color: accent),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: emphasized ? AppColors.statusRed : AppColors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: content,
    );
  }
}
