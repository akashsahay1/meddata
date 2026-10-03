import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/medicine_provider.dart';
import '../../sync/sync_engine.dart';
import '../../theme/app_theme.dart';
import 'add_edit_medicine_screen.dart';
import 'alerts_screen.dart';
import 'home_screen.dart';
import 'inventory_screen.dart';
import 'settings_screen.dart';
import 'upgrade_screen.dart';

/// Root tab shell: Home, Inventory, a center orange '+' that opens Add
/// Medicine, Alerts (with a count badge) and Profile. Tab state is preserved
/// with an [IndexedStack].
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
    if (sync == null || !sync.needsLocalDataChoice || _asking || !mounted) return;
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

  static const List<Widget> _tabs = <Widget>[
    HomeScreen(),
    InventoryScreen(),
    AlertsScreen(),
    SettingsScreen(),
  ];

  Future<void> _addMedicine() async {
    final MedicineProvider mp = context.read<MedicineProvider>();
    if (!mp.canAdd()) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const UpgradeScreen()),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AddEditMedicineScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final MedicineProvider mp = context.watch<MedicineProvider>();
    final int alertTotal =
        mp.expiringCount + mp.expiredCount + mp.lowStockCount;

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
                    15, 5, 15, 10 + MediaQuery.of(context).padding.bottom),
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
              icon: Icons.notifications_none,
              label: 'Alerts',
              selected: index == 2,
              badgeCount: alertCount,
              onTap: () => onSelect(2),
            ),
            _NavItem(
              icon: Icons.person_outline,
              label: 'Profile',
              selected: index == 3,
              onTap: () => onSelect(3),
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
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                          borderRadius: BorderRadius.circular(AppRadii.pill),
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
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
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
    );
  }
}
