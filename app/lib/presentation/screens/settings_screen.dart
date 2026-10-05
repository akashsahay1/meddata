import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/platform.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/backup_service.dart';
import '../../services/device_id.dart';
import '../../services/settings_service.dart';
import '../../state/medicine_provider.dart';
import '../../theme/app_theme.dart';
import '../widgets/ui_kit.dart';
import 'billing/shop_settings_screen.dart';
import 'import/import_wizard_screen.dart';
import 'upgrade_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const String _appVersion = '1.0.0';
  static const Color _chevron = Color(0xFFB4C4C1);
  static const Color _rowLine = Color(0xFFF2F5F4);

  // Developer / testing options (7 taps on the version). Debug builds only: a
  // release build has no tap counter and no section, so they can't be used
  // to unlock premium or read the device id.
  int _versionTaps = 0;
  bool _devUnlocked = false;
  String _deviceId = '…';
  bool _avatarBusy = false;

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      DeviceId.get().then((String id) {
        if (mounted) setState(() => _deviceId = id);
      });
    }
  }

  void _onVersionTap() {
    if (!kDebugMode || _devUnlocked) return;
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
    final AuthService auth = context.watch<AuthService>();
    final double topInset = MediaQuery.of(context).padding.top;
    // MainShell uses extendBody, so the floating bottom bar's height arrives
    // as bottom padding; without it Log out ends up hidden behind the bar.
    final double bottomInset = MediaQuery.of(context).padding.bottom;

    final String displayName = auth.name?.isNotEmpty == true
        ? auth.name!
        : (auth.email ?? 'Signed in');
    final String? displayEmail =
        auth.name?.isNotEmpty == true ? auth.email : null;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Stack(
        children: <Widget>[
          ListView(
            padding: EdgeInsets.zero,
            children: <Widget>[
              _header(displayName, displayEmail, topInset, auth.avatarUrl),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
                child: _planCard(context, s),
              ),

              // Account
              _sectionLabel('Account'),
              _menuCard(<Widget>[
                _menuRow(
                  icon: Icons.person_outline,
                  label: 'Edit profile',
                  onTap: () => _editProfile(context, auth),
                ),
                _menuRow(
                  icon: Icons.lock_outline,
                  label: 'Change password',
                  onTap: () => _changePassword(context),
                ),
              ]),

              // Billing (GST invoices)
              _sectionLabel('Billing'),
              _menuCard(<Widget>[
                _menuRow(
                  icon: Icons.storefront_outlined,
                  label: 'Shop & invoice details',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => const ShopSettingsScreen())),
                ),
              ]),

              // Appearance
              _sectionLabel('Appearance'),
              _menuCard(<Widget>[
                _menuRow(
                  icon: Icons.brightness_6_outlined,
                  label: 'Theme',
                  value: _themeLabel(s.themeMode),
                  onTap: () => _pickTheme(context, s),
                ),
              ]),

              // Alerts
              _sectionLabel('Alerts'),
              _menuCard(<Widget>[
                _menuRow(
                  icon: Icons.schedule,
                  label: 'Expiry warning window',
                  value: '${s.warningDays} days',
                  onTap: () => _pickWarningDays(context, s),
                ),
                _menuRow(
                  icon: Icons.access_time,
                  label: 'Daily reminder time',
                  value: s.reminderTime.format(context),
                  onTap: () async {
                    final TimeOfDay? t = await showTimePicker(
                        context: context, initialTime: s.reminderTime);
                    if (t != null) await s.setReminderTime(t);
                  },
                ),
                _switchRow(
                  icon: Icons.event_busy_outlined,
                  label: 'Expiry notifications',
                  value: s.notifExpiry,
                  onChanged: s.setNotifExpiry,
                ),
                _switchRow(
                  icon: Icons.inventory_2_outlined,
                  label: 'Low-stock notifications',
                  value: s.notifLowStock,
                  onChanged: s.setNotifLowStock,
                ),
              ]),

              // Data
              _sectionLabel('Data'),
              _menuCard(<Widget>[
                _menuRow(
                  icon: Icons.upload_file_outlined,
                  label: 'Import stock from Excel / CSV',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const ImportWizardScreen()),
                  ),
                ),
                _menuRow(
                  icon: Icons.table_view_outlined,
                  label: 'Export as CSV',
                  onTap: () => _exportCsv(context),
                ),
                _menuRow(
                  icon: Icons.settings_backup_restore,
                  label: 'Restore JSON backup',
                  onTap: () => _importJson(context),
                ),
              ]),

              // Support (WhatsApp; number is set in the admin panel)
              _sectionLabel('Support'),
              _menuCard(<Widget>[
                _menuRow(
                  icon: Icons.support_agent,
                  label: 'Chat with support',
                  onTap: () => _openSupportChat(auth),
                ),
                _menuRow(
                  icon: Icons.rate_review_outlined,
                  label: 'Send feedback',
                  onTap: () => _sendFeedback(auth),
                ),
              ]),

              if (kDebugMode && _devUnlocked) ...<Widget>[
                _sectionLabel('Developer / Testing'),
                _menuCard(<Widget>[
                  _switchRow(
                    icon: Icons.workspace_premium_outlined,
                    label: 'Test premium unlock',
                    value: s.isPremium,
                    onChanged: (bool v) => s.setPremium(v),
                  ),
                  _menuRow(
                    icon: Icons.perm_device_information_outlined,
                    label: 'Device ID',
                    value: _deviceId,
                    trailing: const Icon(Icons.copy, size: 18, color: AppColors.muted),
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: _deviceId));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Device ID copied')),
                      );
                    },
                  ),
                ]),
              ],

              Padding(
                padding: const EdgeInsets.fromLTRB(18, 24, 18, 0),
                child: SecondaryButton(
                  label: 'Log out',
                  icon: Icons.logout,
                  onPressed: () => _confirmLogout(context),
                ),
              ),

              const SizedBox(height: 16),
              Center(
                child: GestureDetector(
                  onTap: kDebugMode ? _onVersionTap : null,
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      'Meddata v$_appVersion',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF9BAAA7),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 24 + bottomInset),
            ],
          ),
          // Header-green strip behind the status bar so scrolled rows don't
          // run under the clock and battery icons.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: topInset,
            child: const ColoredBox(color: AppColors.green),
          ),
        ],
      ),
    );
  }

  // --- Support chat & feedback (WhatsApp) -----------------------------------

  String _signature(AuthService auth) {
    final String who = <String?>[auth.name, auth.email]
        .whereType<String>()
        .where((String v) => v.isNotEmpty)
        .join(' · ');
    final String platform = AppPlatform.name;
    return '— $who\nMeddata v$_appVersion ($platform)';
  }

  /// The support WhatsApp number from /config (digits with country code), or
  /// null when it isn't configured / reachable.
  Future<String?> _supportNumber() async {
    final Map<String, dynamic>? config = await ApiClient().fetchConfig();
    final String number = (config?['support_whatsapp'] as String?) ?? '';
    return number.isEmpty ? null : number;
  }

  Future<void> _openWhatsApp(String message) async {
    final String? number = await _supportNumber();
    if (!mounted) return;
    if (number == null) {
      _toast(
          'Support chat is not available right now. Please try again later.');
      return;
    }
    final Uri uri =
        Uri.https('wa.me', '/$number', <String, String>{'text': message});
    bool opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[Support] could not open WhatsApp: $e');
    }
    if (!opened && mounted) _toast('Could not open WhatsApp.');
  }

  Future<void> _openSupportChat(AuthService auth) =>
      _openWhatsApp('Hi Meddata support,\n\n\n${_signature(auth)}');

  Future<void> _sendFeedback(AuthService auth) async {
    final ({int rating, String message})? result =
        await showDialog<({int rating, String message})>(
      context: context,
      builder: (_) => const _FeedbackDialog(),
    );
    if (result == null || !mounted) return;
    final int rating = result.rating;
    final String stars = '★' * rating + '☆' * (5 - rating);
    await _openWhatsApp('Meddata feedback: $stars ($rating/5)\n'
        '${result.message.isEmpty ? '' : '\n${result.message}\n'}'
        '\n${_signature(auth)}');
  }

  // --- Profile photo --------------------------------------------------------

  Widget _avatar(String name, String? avatarUrl) {
    final Widget initials = Container(
      alignment: Alignment.center,
      color: AppColors.greenMid,
      child: Text(
        initialsOf(name),
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
    return Semantics(
      button: true,
      label: 'Change profile photo',
      child: GestureDetector(
        onTap: _avatarBusy ? null : () => _changeAvatar(avatarUrl != null),
        child: SizedBox(
          width: 70,
          height: 70,
          child: Stack(
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: avatarUrl == null
                      ? initials
                      : Image.network(
                          avatarUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => initials,
                        ),
                ),
              ),
              if (_avatarBusy)
                Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0x99000000),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: Colors.white),
                  ),
                ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: AppColors.orange,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.green, width: 2),
                  ),
                  child: const Icon(Icons.photo_camera,
                      size: 14, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _changeAvatar(bool hasPhoto) async {
    final String? action = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(AppPlatform.isDesktop ? 'Choose a picture' : 'Choose from gallery'),
              onTap: () => Navigator.of(ctx).pop('gallery'),
            ),
            if (AppPlatform.supportsCamera)
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take a photo'),
                onTap: () => Navigator.of(ctx).pop('camera'),
              ),
            if (hasPhoto)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Remove photo',
                    style: TextStyle(color: Colors.red)),
                onTap: () => Navigator.of(ctx).pop('remove'),
              ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    final AuthService auth = context.read<AuthService>();

    if (action == 'remove') {
      setState(() => _avatarBusy = true);
      final String? err = await auth.removeAvatar();
      if (!mounted) return;
      setState(() => _avatarBusy = false);
      _toast(err ?? 'Profile photo removed');
      return;
    }

    final ImageSource source =
        action == 'camera' ? ImageSource.camera : ImageSource.gallery;
    if (source == ImageSource.camera &&
        !(await Permission.camera.request()).isGranted) {
      if (mounted) _toast('Allow camera access in Settings to take a photo.');
      return;
    }
    final XFile? file;
    try {
      // Downscale before upload: the avatar is shown at 64px.
      file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
    } catch (e) {
      debugPrint('[Avatar] pick failed: $e');
      if (mounted) _toast('Could not open the photo picker.');
      return;
    }
    if (file == null || !mounted) return;
    setState(() => _avatarBusy = true);
    final String? err = await auth.uploadAvatar(file.path);
    if (!mounted) return;
    setState(() => _avatarBusy = false);
    _toast(err ?? 'Profile photo updated');
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // --- Green profile header -------------------------------------------------

  Widget _header(
      String name, String? email, double topInset, String? avatarUrl) {
    return Container(
      width: double.infinity,
      color: AppColors.green,
      padding: EdgeInsets.fromLTRB(22, topInset + 24, 22, 30),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          // Opened from the avatar on Home (phones): a way back.
          if (Navigator.of(context).canPop()) ...<Widget>[
            IconButton(
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back, color: Colors.white),
            ),
            const SizedBox(width: 4),
          ],
          _avatar(name, avatarUrl),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: Colors.white,
                  ),
                ),
                if (email != null && email.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.onDarkMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Dark-green trial / premium card -------------------------------------

  Widget _planCard(BuildContext context, SettingsService s) {
    final bool premium = s.isPremium;
    final int daysLeft = s.trialDaysLeft;

    final String eyebrow = premium ? 'Meddata Pro' : 'Free trial';
    final String headline = premium
        ? 'Premium active'
        : (daysLeft > 0 ? '$daysLeft days left' : 'Trial ended');
    final String sub = premium
        ? 'All features unlocked'
        : 'Then choose a plan to keep alerts on';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.greenDarkest,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      eyebrow.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: AppColors.onDarkFaint,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      headline,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      sub,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.onDarkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  premium ? Icons.verified_outlined : Icons.shield_outlined,
                  size: 22,
                  color: AppColors.orange,
                ),
              ),
            ],
          ),
          if (!premium) ...<Widget>[
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const UpgradeScreen()),
                ),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                child: const Text('Upgrade to Pro'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --- Menu building blocks -------------------------------------------------

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: AppColors.muted,
          ),
        ),
      );

  Widget _menuCard(List<Widget> rows) {
    final List<Widget> children = <Widget>[];
    for (int i = 0; i < rows.length; i++) {
      children.add(rows[i]);
      if (i != rows.length - 1) {
        children.add(const Divider(
          height: 1,
          thickness: 1,
          indent: 62,
          color: _rowLine,
        ));
      }
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      ),
    );
  }

  Widget _menuRow({
    required IconData icon,
    required String label,
    String? value,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: <Widget>[
              _iconChip(icon),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ),
              if (value != null)
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 6),
              trailing ??
                  const Icon(Icons.chevron_right, size: 20, color: _chevron),
            ],
          ),
        ),
      ),
    );
  }

  Widget _switchRow({
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    // One node for screen readers: the switch is read with its label.
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: <Widget>[
            _iconChip(icon),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }

  Widget _iconChip(IconData icon) => Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.canvas,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 18, color: AppColors.green),
      );

  // --- Preserved logic ------------------------------------------------------

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

  Future<void> _exportCsv(BuildContext context) async {
    final BackupService b = BackupService();
    final File f = await b.exportCsv();
    await b.share(f, text: 'Medicine stock (CSV)');
  }

  Future<void> _editProfile(BuildContext context, AuthService auth) async {
    final TextEditingController nameCtrl =
        TextEditingController(text: auth.name ?? '');
    final TextEditingController emailCtrl =
        TextEditingController(text: auth.email ?? '');
    final bool? save = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Edit profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (save != true || !context.mounted) return;
    final String name = nameCtrl.text.trim();
    final String email = emailCtrl.text.trim();
    if (name.isEmpty || email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name and email cannot be empty')),
      );
      return;
    }
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String? error = await context
        .read<AuthService>()
        .updateProfile(name: name, email: email);
    messenger.showSnackBar(
      SnackBar(content: Text(error ?? 'Profile updated')),
    );
  }

  Future<void> _changePassword(BuildContext context) async {
    final TextEditingController currentCtrl = TextEditingController();
    final TextEditingController newCtrl = TextEditingController();
    final TextEditingController confirmCtrl = TextEditingController();
    final bool? save = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Change password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: currentCtrl,
              obscureText: true,
              decoration:
                  const InputDecoration(labelText: 'Current password'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New password'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmCtrl,
              obscureText: true,
              decoration:
                  const InputDecoration(labelText: 'Confirm new password'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Update'),
          ),
        ],
      ),
    );
    if (save != true || !context.mounted) return;
    final String current = currentCtrl.text;
    final String next = newCtrl.text;
    final String confirm = confirmCtrl.text;
    if (current.isEmpty || next.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }
    if (next != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New passwords do not match')),
      );
      return;
    }
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String? error = await context.read<AuthService>().changePassword(
          currentPassword: current,
          newPassword: next,
        );
    messenger.showSnackBar(
      SnackBar(content: Text(error ?? 'Password changed')),
    );
  }

  /// Restore a Meddata JSON backup. Spreadsheets go through the import
  /// wizard instead.
  Future<void> _importJson(BuildContext context) async {
    const XTypeGroup group = XTypeGroup(
      label: 'Meddata backup',
      extensions: <String>['json'],
      mimeTypes: <String>['application/json', 'application/octet-stream'],
      uniformTypeIdentifiers: <String>['public.json'],
    );
    final XFile? picked = await openFile(acceptedTypeGroups: <XTypeGroup>[group]);
    if (picked == null || !context.mounted) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final MedicineProvider mp = context.read<MedicineProvider>();
    int count;
    try {
      count = await BackupService().importJson(File(picked.path));
    } catch (e) {
      debugPrint('[Backup] restore failed: $e');
      messenger.showSnackBar(const SnackBar(
        content: Text('This is not a Meddata backup. For Excel or CSV files '
            'use "Import stock from Excel / CSV".'),
      ));
      return;
    }
    await mp.load();
    messenger.showSnackBar(
      SnackBar(content: Text('Imported $count medicines')),
    );
  }
}

/// Star rating + message; pops `(rating, message)` or null on cancel. Owns its
/// controller so it outlives the dialog's exit animation.
class _FeedbackDialog extends StatefulWidget {
  const _FeedbackDialog();

  @override
  State<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<_FeedbackDialog> {
  final TextEditingController _text = TextEditingController();
  int _rating = 0;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Send feedback'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text('How is Meddata working for you?'),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              for (int i = 1; i <= 5; i++)
                Semantics(
                  button: true,
                  selected: i <= _rating,
                  label: '$i star${i == 1 ? '' : 's'}',
                  child: InkResponse(
                    radius: 24,
                    onTap: () => setState(() => _rating = i),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        i <= _rating
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        size: 32,
                        color: AppColors.orange,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          TextField(
            controller: _text,
            maxLines: 4,
            minLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Tell us what you like or what we can improve',
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Opens WhatsApp to send this to our support team.',
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _rating == 0
              ? null
              : () => Navigator.of(context)
                  .pop((rating: _rating, message: _text.text.trim())),
          child: const Text('Send'),
        ),
      ],
    );
  }
}
