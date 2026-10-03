import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../sync/sync_engine.dart';
import '../../theme/app_theme.dart';
import '../widgets/sync_badge.dart';

/// Sync status plus every change the server didn't accept:
/// - conflict: another device changed the same item first. The other
///   device's value is already shown in the app; the user picks
///   "Use theirs" (drop mine) or "Keep mine" (re-apply mine on top).
/// - rejected: the server refused the change (invalid data, plan limit).
class SyncIssuesScreen extends StatelessWidget {
  const SyncIssuesScreen({super.key});

  static const Map<String, String> _fieldLabels = <String, String>{
    'mrp_paise': 'MRP',
    'purchase_rate_paise': 'Purchase price',
    'name': 'Name',
    'manufacturer': 'Brand',
    'category': 'Category',
    'unit': 'Unit',
    'barcode': 'Barcode',
    'batch_no': 'Batch',
    'expiry_date': 'Expiry',
    'mfg_date': 'Mfg date',
    'low_stock_threshold_units': 'Low-stock at',
    'notes': 'Notes',
    'delta_units': 'Stock change',
  };

  static const Map<String, String> _reasons = <String, String>{
    'version_mismatch': 'Changed on another device first',
    'deleted': 'Deleted on another device',
    'plan_limit': 'Free plan limit reached',
    'invalid': 'Some details were not valid',
    'product_not_found': 'Its medicine no longer exists',
    'batch_not_found': 'Its batch no longer exists',
  };

  String _value(String field, Object? v) {
    if (v == null || v == '') return '—';
    if (field.endsWith('_paise') && v is num) return Fmt.money(v / 100);
    return '$v';
  }

  @override
  Widget build(BuildContext context) {
    final SyncEngine sync = context.watch<SyncEngine>();
    final int? ago = sync.secondsSinceSync;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('Sync')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
        children: <Widget>[
          Row(
            children: <Widget>[
              const SyncBadge(),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  ago == null ? 'Not synced yet' : 'Last synced ${_ago(ago)}',
                  style: const TextStyle(color: AppColors.muted),
                ),
              ),
              TextButton.icon(
                onPressed: sync.status == SyncStatus.syncing ? null : sync.syncNow,
                icon: const Icon(Icons.sync, size: 18),
                label: const Text('Sync now'),
              ),
            ],
          ),
          if (sync.status == SyncStatus.offline)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'No internet. Changes made here are kept on this device and '
                'sent automatically when you are back online.',
                style: TextStyle(color: AppColors.muted),
              ),
            ),
          const SizedBox(height: 16),
          if (sync.issues.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(
                child: Text('Nothing needs your attention.',
                    style: TextStyle(color: AppColors.muted)),
              ),
            ),
          for (final SyncIssue issue in sync.issues) _issueCard(context, sync, issue),
        ],
      ),
    );
  }

  Widget _issueCard(BuildContext context, SyncEngine sync, SyncIssue issue) {
    final bool conflict = issue.status == 'conflict';
    final String what = switch (issue.table) {
      'products' => 'Medicine',
      'batches' => 'Batch',
      _ => 'Stock change',
    };
    final String name = (issue.theirs?['name'] ?? issue.mine['name'] ??
            issue.theirs?['batch_no'] ?? issue.mine['batch_no'] ?? '')
        .toString();
    final List<String> fields = issue.mine.keys
        .where((String k) => _fieldLabels.containsKey(k) && k != 'product_id')
        .toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              name.isEmpty ? what : '$what · $name',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              issue.op == 'delete'
                  ? 'Your delete: ${_reasons[issue.reason] ?? issue.reason}'
                  : (_reasons[issue.reason] ?? issue.reason),
              style: TextStyle(
                  color: conflict ? AppColors.statusAmber : AppColors.statusRed,
                  fontWeight: FontWeight.w600),
            ),
            if (conflict && issue.op != 'delete') ...<Widget>[
              const SizedBox(height: 10),
              Table(
                columnWidths: const <int, TableColumnWidth>{0: IntrinsicColumnWidth()},
                children: <TableRow>[
                  const TableRow(children: <Widget>[
                    SizedBox(),
                    Padding(
                        padding: EdgeInsets.only(left: 12, bottom: 4),
                        child: Text('Yours', style: TextStyle(color: AppColors.muted))),
                    Padding(
                        padding: EdgeInsets.only(left: 12, bottom: 4),
                        child: Text('Now in shop', style: TextStyle(color: AppColors.muted))),
                  ]),
                  for (final String f in fields)
                    TableRow(children: <Widget>[
                      Text(_fieldLabels[f]!, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: Text(_value(f, issue.mine[f]))),
                      Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: Text(_value(f, issue.theirs?[f]),
                              style: const TextStyle(fontWeight: FontWeight.w700))),
                    ]),
                ],
              ),
            ],
            if (!conflict && issue.mine.isNotEmpty && issue.table == 'stock_movements')
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Stock change: ${issue.mine['delta_units']}'),
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: <Widget>[
                if (conflict)
                  OutlinedButton(
                    onPressed: () => sync.useTheirs(issue),
                    child: const Text('Use theirs'),
                  ),
                if (conflict && !issue.serverDeleted)
                  ElevatedButton(
                    onPressed: () async {
                      await sync.keepMine(issue);
                      await sync.syncNow();
                    },
                    child: const Text('Keep mine'),
                  ),
                if (!conflict)
                  OutlinedButton(
                    onPressed: () => sync.dismiss(issue),
                    child: const Text('Dismiss'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _ago(int s) {
    if (s < 60) return 'just now';
    if (s < 3600) return '${s ~/ 60} min ago';
    return '${s ~/ 3600} h ago';
  }
}
