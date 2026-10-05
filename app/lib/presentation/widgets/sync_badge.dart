import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../sync/sync_engine.dart';
import '../../theme/app_theme.dart';
import '../screens/sync_issues_screen.dart';
import 'ui_kit.dart';

/// Small chip showing whether this device is in step with the shop:
/// synced / syncing / offline / N pending / N need attention. Tapping it
/// opens the sync screen (conflicts to resolve, sync now).
class SyncBadge extends StatelessWidget {
  final bool onDark;
  const SyncBadge({super.key, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    final SyncEngine sync = context.watch<SyncEngine>();
    final (IconData icon, String label, Color color) = describe(sync);
    final Color fg = onDark && color == AppColors.statusGreen ? Colors.white : color;
    void open() => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const SyncIssuesScreen()));
    // The chip stays small; its touch area is 48dp tall.
    return TapTarget(
      label: 'Sync: $label',
      tooltip: false,
      onTap: open,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: open,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: onDark
                ? Colors.white.withValues(alpha: 0.12)
                : color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
            ],
          ),
        ),
      ),
    );
  }

  static (IconData, String, Color) describe(SyncEngine s) {
    if (s.issues.isNotEmpty) {
      return (
        Icons.error_outline,
        '${s.issues.length} need attention',
        AppColors.statusRed,
      );
    }
    switch (s.status) {
      case SyncStatus.syncing:
        return (Icons.sync, 'Syncing', AppColors.muted);
      case SyncStatus.offline:
        return (
          Icons.cloud_off,
          s.pending > 0 ? 'Offline · ${s.pending} pending' : 'Offline',
          AppColors.statusAmber,
        );
      case SyncStatus.error:
        return (Icons.sync_problem, 'Sync error', AppColors.statusRed);
      case SyncStatus.idle:
        if (s.pending > 0) {
          return (Icons.cloud_upload_outlined, '${s.pending} pending', AppColors.statusAmber);
        }
        return (
          Icons.cloud_done_outlined,
          s.lastSuccess == null ? 'Not synced' : 'Synced',
          AppColors.statusGreen,
        );
    }
  }
}
