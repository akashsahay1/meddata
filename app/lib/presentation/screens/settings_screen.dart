import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../services/backup_service.dart';
import '../../services/device_id.dart';
import '../../services/settings_service.dart';
import '../../state/medicine_provider.dart';
import 'upgrade_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _versionTaps = 0;
  bool _devUnlocked = false;
  String _deviceId = '…';

  @override
  void initState() {
    super.initState();
    DeviceId.get().then((String id) {
      if (mounted) setState(() => _deviceId = id);
    });
  }

  void _onVersionTap() {
    if (_devUnlocked) return;
    _versionTaps++;
    if (_versionTaps >= 7) {
      setState(() => _devUnlocked = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Developer / testing options enabled')),
      );
    } else if (_versionTaps >= 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 700),
          content: Text('${7 - _versionTaps} taps to developer options'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final SettingsService s = context.watch<SettingsService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: <Widget>[
          _header('Appearance'),
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('Theme'),
            subtitle: Text(_themeLabel(s.themeMode)),
            onTap: () => _pickTheme(context, s),
          ),
          const Divider(height: 1),
          _header('Alerts'),
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('Expiry warning window'),
            subtitle: Text('${s.warningDays} days before expiry'),
            onTap: () => _pickWarningDays(context, s),
          ),
          ListTile(
            leading: const Icon(Icons.access_time),
            title: const Text('Daily reminder time'),
            subtitle: Text(s.reminderTime.format(context)),
            onTap: () async {
              final TimeOfDay? t = await showTimePicker(
                  context: context, initialTime: s.reminderTime);
              if (t != null) await s.setReminderTime(t);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.event_busy_outlined),
            title: const Text('Expiry notifications'),
            value: s.notifExpiry,
            onChanged: s.setNotifExpiry,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.inventory_2_outlined),
            title: const Text('Low-stock notifications'),
            value: s.notifLowStock,
            onChanged: s.setNotifLowStock,
          ),
          const Divider(height: 1),
          _header('Data'),
          ListTile(
            leading: const Icon(Icons.file_upload_outlined),
            title: const Text('Export backup (JSON)'),
            onTap: () => _exportJson(context),
          ),
          ListTile(
            leading: const Icon(Icons.table_view_outlined),
            title: const Text('Export as CSV'),
            onTap: () => _exportCsv(context),
          ),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('Import from file (JSON / CSV)'),
            onTap: () => _import(context),
          ),
          const Divider(height: 1),
          _header('Account'),
          Builder(builder: (BuildContext context) {
            final AuthService auth = context.watch<AuthService>();
            return ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: Text(auth.name?.isNotEmpty == true
                  ? auth.name!
                  : (auth.email ?? 'Signed in')),
              subtitle: auth.email != null ? Text(auth.email!) : null,
            );
          }),
          ListTile(
            leading: Icon(s.isPremium
                ? Icons.verified_outlined
                : Icons.workspace_premium_outlined),
            title: Text(s.isPremium ? 'Premium active' : 'Upgrade to Premium'),
            subtitle: Text(s.isPremium
                ? 'All features unlocked'
                : 'Unlimited medicines & more'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const UpgradeScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Log out'),
            onTap: () => _confirmLogout(context),
          ),
          if (_devUnlocked) ...<Widget>[
            const Divider(height: 1),
            _header('Developer / Testing'),
            SwitchListTile(
              secondary: const Icon(Icons.workspace_premium_outlined),
              title: const Text('Test premium unlock'),
              subtitle: const Text(
                  'Unlocks all premium features locally for testing '
                  '(bypasses Google Play).'),
              value: s.isPremium,
              onChanged: (bool v) => s.setPremium(v),
            ),
            ListTile(
              leading: const Icon(Icons.perm_device_information_outlined),
              title: const Text('Device ID'),
              subtitle: Text(_deviceId),
              trailing: const Icon(Icons.copy, size: 18),
              onTap: () {
                Clipboard.setData(ClipboardData(text: _deviceId));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Device ID copied')),
                );
              },
            ),
          ],
          const Divider(height: 1),
          _header('About'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Meddata — Medicine Stock & Expiry Tracker'),
            subtitle: const Text('Version 1.0.0'),
            onTap: _onVersionTap,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6)),
      );

  String _themeLabel(ThemeMode m) {
    switch (m) {
      case ThemeMode.system:
        return 'System default';
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
    }
  }

  Future<void> _pickTheme(BuildContext context, SettingsService s) async {
    final ThemeMode? mode = await showModalBottomSheet<ThemeMode>(
      context: context,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: ThemeMode.values
              .map((ThemeMode m) => ListTile(
                    title: Text(_themeLabel(m)),
                    trailing:
                        s.themeMode == m ? const Icon(Icons.check) : null,
                    onTap: () => Navigator.of(ctx).pop(m),
                  ))
              .toList(),
        ),
      ),
    );
    if (mode != null) await s.setThemeMode(mode);
  }

  Future<void> _pickWarningDays(BuildContext context, SettingsService s) async {
    const List<int> options = <int>[7, 15, 30, 60, 90];
    final int? days = await showModalBottomSheet<int>(
      context: context,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: options
              .map((int d) => ListTile(
                    title: Text('$d days before expiry'),
                    trailing:
                        s.warningDays == d ? const Icon(Icons.check) : null,
                    onTap: () => Navigator.of(ctx).pop(d),
                  ))
              .toList(),
        ),
      ),
    );
    if (days != null) await s.setWarningDays(days);
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final bool ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: const Text('Log out?'),
            content: const Text(
                'You will need to log in again to use the app. Your data stays '
                'safe on this device.'),
            actions: <Widget>[
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel')),
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Log out')),
            ],
          ),
        ) ??
        false;
    if (!ok || !context.mounted) return;
    await context.read<AuthService>().logout();
    // The root gate rebuilds to the login screen automatically.
    if (context.mounted) Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
  }

  Future<void> _exportJson(BuildContext context) async {
    final BackupService b = BackupService();
    final File f = await b.exportJson();
    await b.share(f);
  }

  Future<void> _exportCsv(BuildContext context) async {
    final BackupService b = BackupService();
    final File f = await b.exportCsv();
    await b.share(f, text: 'Medicine stock (CSV)');
  }

  Future<void> _import(BuildContext context) async {
    const XTypeGroup group = XTypeGroup(
      label: 'Backup / CSV',
      extensions: <String>['json', 'csv'],
    );
    final XFile? picked = await openFile(acceptedTypeGroups: <XTypeGroup>[group]);
    if (picked == null) return;
    final String path = picked.path;
    final BackupService b = BackupService();
    int count;
    if (path.toLowerCase().endsWith('.csv')) {
      count = await b.importCsv(File(path));
    } else {
      count = await b.importJson(File(path));
    }
    if (!context.mounted) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    await context.read<MedicineProvider>().load();
    messenger.showSnackBar(
      SnackBar(content: Text('Imported $count medicines')),
    );
  }
}
