import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/medicine_provider.dart';
import '../../sync/sync_engine.dart';
import '../../theme/app_theme.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/desktop_kit.dart';
import '../widgets/ui_kit.dart';
import 'account_switch_dialog.dart';
import 'accounts/gst_reports_screen.dart';
import 'accounts/parties_screen.dart';
import 'accounts/purchases_screen.dart';
import 'add_edit_medicine_screen.dart';
import 'alerts_screen.dart';
import 'billing/bills_screen.dart';
import 'home_screen.dart';
import 'inventory_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'upgrade_screen.dart';

/// Root tab shell: Home, Inventory, a center orange '+' that opens Add
/// Medicine, Bills, Alerts (with a count badge) and Profile. Tab state is
/// preserved with an [IndexedStack]. Phones have room for four tabs around
/// the '+', so Profile is reached from the avatar on Home there (and Parties,
/// Purchases, Reports and GST returns from Home's Business tiles); the
/// desktop rail shows every tab.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  SyncEngine? _sync;
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    _sync = context.read<SyncEngine>()..addListener(_onSync);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onSync());
  }

  @override
  void dispose() {
    _sync?.removeListener(_onSync);
    super.dispose();
  }

  /// This device already had medicines and the shop on the server has data
  /// too (second device / reinstall): ask what to do with the local ones.
  Future<void> _onSync() async {
    final SyncEngine? sync = _sync;
    if (sync == null || _asking || !mounted) return;
    if (sync.accountSwitch != null) {
      // Another account's changes are still waiting to upload.
      _asking = true;
      await askAboutPreviousAccountChanges(context, sync);
      _asking = false;
      return;
    }
    if (!sync.needsLocalDataChoice) return;
    _asking = true;
    final LocalDataChoice? choice = await showDialog<LocalDataChoice>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Medicines already on this device'),
        content: const Text(
          'Your shop already has medicines saved online. What should happen '
          'to the medicines saved only on this device?\n\n'
          'Add them: they are added to your shop (you may get duplicates to '
          'delete).\n'
          "Remove them: this device shows only the shop's medicines.",
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(LocalDataChoice.discard),
            child: const Text('Remove them'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(LocalDataChoice.merge),
            child: const Text('Add them'),
          ),
        ],
      ),
    );
    _asking = false;
    if (choice != null) await sync.resolveLocalData(choice);
  }

  // Tab indices, in rail order. The phone bar shows Home, Inventory, Bills
  // and Alerts only.
  static const int _billsTab = 2;
  static const int _alertsTab = 7;

  /// Built only while showing, so each opens fresh (as it did as a page) and
  /// none of them calls the server until the owner opens it.
  Widget _accountsTab(int index, Widget screen) {
    if (_index != index) return const SizedBox.shrink();
    // Their app bar (no back arrow: nothing to go back to) styled like the
    // other tabs' page header.
    final ThemeData theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        appBarTheme: theme.appBarTheme.copyWith(
          backgroundColor: AppColors.canvas,
          toolbarHeight: 76,
          titleSpacing: kDeskGutter,
          titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
            fontSize: 26,
            letterSpacing: -0.4,
          ),
        ),
      ),
      child: screen,
    );
  }

  List<Widget> get _tabs => <Widget>[
    const HomeScreen(),
    const InventoryScreen(),
    BillsScreen(active: _index == _billsTab),
    _accountsTab(3, const PartiesScreen()),
    _accountsTab(4, const PurchasesScreen()),
    _accountsTab(5, const ReportsScreen()),
    _accountsTab(6, const GstReportsScreen()),
    const AlertsScreen(),
    const SettingsScreen(),
  ];

  Future<void> _addMedicine() async {
    final MedicineProvider mp = context.read<MedicineProvider>();
    if (!mp.canAdd()) {
      Navigator.of(
        context,
      ).push(AdaptiveLayout.route<void>(context, maxWidth: AdaptiveLayout.desktopFormMaxWidth,
builder: (_) => const UpgradeScreen()));
      return;
    }
    await Navigator.of(context).push(
      AdaptiveLayout.route<void>(context, maxWidth: AdaptiveLayout.desktopFormMaxWidth,
builder: (_) => const AddEditMedicineScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final MedicineProvider mp = context.watch<MedicineProvider>();
    final int alertTotal =
        mp.expiringCount + mp.expiredCount + mp.lowStockCount;

    // Wide windows (Windows PC, tablets): side rail instead of the bottom
    // bar; the tabs switch to their desktop layouts.
    final double width = MediaQuery.sizeOf(context).width;
    if (AdaptiveLayout.isDesktop(context)) {
      final bool extendedRail = width >= 1100;
      return Scaffold(
        backgroundColor: AppColors.canvas,
        body: Row(
          children: <Widget>[
            NavigationRail(
              backgroundColor: AppColors.card,
              extended: extendedRail,
              minExtendedWidth: 228,
              labelType: extendedRail
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.all,
              // Nine tabs: scroll them on a short window.
              scrollable: true,
              selectedIndex: _index,
              onDestinationSelected: (int i) => setState(() => _index = i),
              leading: Padding(
                padding: EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: extendedRail ? 20 : 0,
                ),
                child: extendedRail
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              BrandMark(size: 32),
                              SizedBox(width: 9),
                              Text(
                                'Medikabiz',
                                style: TextStyle(
                                  color: AppColors.greenDarkest,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.4,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),
                          SizedBox(
                            width: 184,
                            child: ElevatedButton.icon(
                              onPressed: _addMedicine,
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Add medicine'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.orange,
                                // Ink, not white, on orange: 5.0:1 contrast
                                // (white is 2.8).
                                foregroundColor: AppColors.ink,
                                minimumSize: const Size.fromHeight(46),
                              ),
                            ),
                          ),
                        ],
                      )
                    : FloatingActionButton(
                        tooltip: 'Add medicine',
                        onPressed: _addMedicine,
                        child: const Icon(Icons.add),
                      ),
              ),
              destinations: <NavigationRailDestination>[
                const NavigationRailDestination(
                  icon: Icon(Icons.home_outlined),
                  label: Text('Home'),
                ),
                const NavigationRailDestination(
                  icon: Icon(Icons.grid_view_outlined),
                  label: Text('Inventory'),
                ),
                const NavigationRailDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  label: Text('Bills'),
                ),
                const NavigationRailDestination(
                  icon: Icon(Icons.people_outline),
                  label: Text('Parties'),
                ),
                const NavigationRailDestination(
                  icon: Icon(Icons.local_shipping_outlined),
                  label: Text('Purchases'),
                ),
                const NavigationRailDestination(
                  icon: Icon(Icons.insights_outlined),
                  label: Text('Reports'),
                ),
                const NavigationRailDestination(
                  icon: Icon(Icons.account_balance_outlined),
                  label: Text('GST returns'),
                ),
                NavigationRailDestination(
                  icon: Badge(
                    isLabelVisible: alertTotal > 0,
                    label: Text('$alertTotal'),
                    child: const Icon(Icons.notifications_none),
                  ),
                  label: const Text('Alerts'),
                ),
                const NavigationRailDestination(
                  icon: Icon(Icons.person_outline),
                  label: Text('Profile'),
                ),
              ],
            ),
            const VerticalDivider(width: 1),
            // Each tab lays itself out for the full width (tables, columns).
            Expanded(child: IndexedStack(index: _index, children: _tabs)),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      extendBody: true,
      // extendBody hands the tabs the floating bar's height as bottom padding;
      // lift their (floating) snackbars by it so they aren't hidden behind it.
      body: Builder(
        builder: (BuildContext context) {
          final ThemeData theme = Theme.of(context);
          return Theme(
            data: theme.copyWith(
              snackBarTheme: theme.snackBarTheme.copyWith(
                insetPadding: EdgeInsets.fromLTRB(
                  15,
                  5,
                  15,
                  10 + MediaQuery.of(context).padding.bottom,
                ),
              ),
            ),
            child: IndexedStack(index: _index, children: _tabs),
          );
        },
      ),
      bottomNavigationBar: _BottomBar(
        index: _index,
        alertCount: alertTotal,
        onSelect: (int i) => setState(() => _index = i),
        onAdd: _addMedicine,
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int index;
  final int alertCount;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;

  const _BottomBar({
    required this.index,
    required this.alertCount,
    required this.onSelect,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final double bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: Color(0xFFEAF0EF))),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Color(0x140A302E),
            blurRadius: 24,
            offset: Offset(0, -8),
          ),
        ],
      ),
      padding: EdgeInsets.only(top: 10, bottom: bottomInset),
      child: SizedBox(
        height: 62,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _NavItem(
              icon: Icons.home_outlined,
              label: 'Home',
              selected: index == 0,
              onTap: () => onSelect(0),
            ),
            _NavItem(
              icon: Icons.grid_view_outlined,
              label: 'Inventory',
              selected: index == 1,
              onTap: () => onSelect(1),
            ),
            _CenterAddButton(onTap: onAdd),
            _NavItem(
              icon: Icons.receipt_long_outlined,
              label: 'Bills',
              selected: index == 2,
              onTap: () => onSelect(2),
            ),
            _NavItem(
              icon: Icons.notifications_none,
              label: 'Alerts',
              selected: index == _MainShellState._alertsTab,
              badgeCount: alertCount,
              onTap: () => onSelect(_MainShellState._alertsTab),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final int badgeCount;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final Color color = selected ? AppColors.green : AppColors.muted;
    return Expanded(
      child: Semantics(
        container: true,
        button: true,
        selected: selected,
        label: badgeCount > 0 ? '$label, $badgeCount need attention' : label,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: ExcludeSemantics(
            // Fills the bar's height, so the whole slot is the touch area
            // (icon + label alone is under 48dp).
            child: Column(
              children: <Widget>[
                SizedBox(
                  height: 24,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      Icon(icon, size: 22, color: color),
                      if (badgeCount > 0)
                        Positioned(
                          top: -4,
                          right: -8,
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 16),
                            height: 16,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.statusRed,
                              borderRadius: BorderRadius.circular(
                                AppRadii.pill,
                              ),
                            ),
                            child: Text(
                              badgeCount > 99 ? '99+' : '$badgeCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                // One line, shrunk to fit rather than wrapped out of the bar
                // when the phone uses large text.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CenterAddButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CenterAddButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Transform.translate(
          offset: const Offset(0, -16),
          child: Semantics(
            button: true,
            label: 'Add medicine',
            onTap: onTap,
            excludeSemantics: true,
            child: Tooltip(
              message: 'Add medicine',
              excludeFromSemantics: true,
              child: GestureDetector(
                onTap: onTap,
                child: Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: AppColors.orange,
                    borderRadius: BorderRadius.circular(AppRadii.fab),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Color(0xCCFF6B2C),
                        blurRadius: 24,
                        offset: Offset(0, 12),
                        spreadRadius: -10,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.add, color: Colors.white, size: 26),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
