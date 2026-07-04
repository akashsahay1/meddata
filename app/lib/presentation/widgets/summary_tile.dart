import 'package:flutter/material.dart';

/// A bordered dashboard stat tile (monochrome). Emphasize via inverted fill.
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
    final Color fg = Theme.of(context).colorScheme.onSurface;
    final Color bg = Theme.of(context).colorScheme.surface;
    final Color content = emphasized ? bg : fg;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: emphasized ? fg : bg,
          border: Border.all(color: fg),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, size: 18, color: content),
                const Spacer(),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: content,
                    height: 1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: content,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
