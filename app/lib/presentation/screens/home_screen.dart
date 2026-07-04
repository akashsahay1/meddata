import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../data/models/medicine.dart';
import '../../services/settings_service.dart';
import '../../state/medicine_provider.dart';
import '../widgets/medicine_list_tile.dart';
import '../widgets/summary_tile.dart';
import 'add_edit_medicine_screen.dart';
import 'alerts_screen.dart';
import 'medicine_detail_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'upgrade_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _addMedicine() async {
    final MedicineProvider mp = context.read<MedicineProvider>();
    if (!mp.canAdd()) {
      _openUpgrade();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AddEditMedicineScreen()),
    );
  }

  void _openUpgrade() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const UpgradeScreen()),
    );
  }

  void _open(Widget screen) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final MedicineProvider mp = context.watch<MedicineProvider>();
    final SettingsService settings = context.watch<SettingsService>();
    final List<Medicine> items = mp.visible;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Medicine Stock'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Alerts',
            icon: const Icon(Icons.notifications_none),
            onPressed: () => _open(const AlertsScreen()),
          ),
          IconButton(
            tooltip: 'Reports',
            icon: const Icon(Icons.bar_chart_outlined),
            onPressed: () => _open(const ReportsScreen()),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _open(const SettingsScreen()),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addMedicine,
        icon: const Icon(Icons.add),
        label: const Text('Add Medicine'),
      ),
      body: RefreshIndicator(
        onRefresh: mp.load,
        child: CustomScrollView(
          slivers: <Widget>[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: _Dashboard(
                  mp: mp,
                  settings: settings,
                  onUpgrade: _openUpgrade,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: _SearchAndFilters(controller: _search),
              ),
            ),
            if (mp.loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(
                  hasAny: mp.totalCount > 0,
                  onAdd: _addMedicine,
                ),
              )
            else
              SliverList.separated(
                itemCount: items.length,
                separatorBuilder: (_, int _) => const Divider(height: 1),
                itemBuilder: (BuildContext context, int i) {
                  final Medicine m = items[i];
                  return Dismissible(
                    key: ValueKey<String>(m.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      color: Theme.of(context).colorScheme.onSurface,
                      child: Icon(Icons.delete_outline,
                          color: Theme.of(context).colorScheme.surface),
                    ),
                    onDismissed: (_) => _deleteWithUndo(m),
                    child: MedicineListTile(
                      medicine: m,
                      status: mp.statusOf(m),
                      onTap: () => _open(MedicineDetailScreen(medicineId: m.id)),
                    ),
                  );
                },
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 88)),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteWithUndo(Medicine m) async {
    final MedicineProvider mp = context.read<MedicineProvider>();
    await mp.delete(m.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Deleted ${m.name}'),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () => mp.undoDelete(m.id),
        ),
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  final MedicineProvider mp;
  final SettingsService settings;
  final VoidCallback onUpgrade;
  const _Dashboard(
      {required this.mp, required this.settings, required this.onUpgrade});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: SummaryTile(
                label: 'Total Medicines',
                value: '${mp.totalCount}',
                icon: Icons.medication_outlined,
                onTap: () => mp.setFilter(MedicineFilter.all),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SummaryTile(
                label: 'Expiring Soon',
                value: '${mp.expiringCount}',
                icon: Icons.schedule,
                onTap: () => mp.setFilter(MedicineFilter.expiring),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: SummaryTile(
                label: 'Expired',
                value: '${mp.expiredCount}',
                icon: Icons.error_outline,
                emphasized: mp.expiredCount > 0,
                onTap: () => mp.setFilter(MedicineFilter.expired),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SummaryTile(
                label: 'Low Stock',
                value: '${mp.lowStockCount}',
                icon: Icons.inventory_2_outlined,
                onTap: () => mp.setFilter(MedicineFilter.lowStock),
              ),
            ),
          ],
        ),
        if (!settings.isPremium) ...<Widget>[
          const SizedBox(height: 10),
          _FreeTierBar(count: mp.totalCount, onUpgrade: onUpgrade),
        ],
      ],
    );
  }
}

class _FreeTierBar extends StatelessWidget {
  final int count;
  final VoidCallback onUpgrade;
  const _FreeTierBar({required this.count, required this.onUpgrade});

  @override
  Widget build(BuildContext context) {
    final int limit = AppConstants.freeTierMedicineLimit;
    final double frac = (count / limit).clamp(0, 1).toDouble();
    final Color fg = Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: fg),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('Free plan — $count / $limit medicines',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              GestureDetector(
                onTap: onUpgrade,
                child: Text('UPGRADE',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        decoration: TextDecoration.underline,
                        color: fg)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchAndFilters extends StatelessWidget {
  final TextEditingController controller;
  const _SearchAndFilters({required this.controller});

  @override
  Widget build(BuildContext context) {
    final MedicineProvider mp = context.watch<MedicineProvider>();
    return Column(
      children: <Widget>[
        TextField(
          controller: controller,
          onChanged: mp.setQuery,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search name, batch or barcode',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: mp.query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      controller.clear();
                      mp.setQuery('');
                    },
                  ),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: <Widget>[
              _FilterChip(
                label: 'All',
                selected: mp.filter == MedicineFilter.all,
                onTap: () => mp.setFilter(MedicineFilter.all),
              ),
              _FilterChip(
                label: 'Expiring',
                selected: mp.filter == MedicineFilter.expiring,
                onTap: () => mp.setFilter(MedicineFilter.expiring),
              ),
              _FilterChip(
                label: 'Expired',
                selected: mp.filter == MedicineFilter.expired,
                onTap: () => mp.setFilter(MedicineFilter.expired),
              ),
              _FilterChip(
                label: 'Low stock',
                selected: mp.filter == MedicineFilter.lowStock,
                onTap: () => mp.setFilter(MedicineFilter.lowStock),
              ),
              const SizedBox(width: 4),
              _SortButton(mp: mp),
            ],
          ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final Color fg = Theme.of(context).colorScheme.onSurface;
    final Color bg = Theme.of(context).colorScheme.surface;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? fg : bg,
            border: Border.all(color: fg),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? bg : fg,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  final MedicineProvider mp;
  const _SortButton({required this.mp});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<MedicineSort>(
      initialValue: mp.sort,
      onSelected: mp.setSort,
      itemBuilder: (_) => const <PopupMenuEntry<MedicineSort>>[
        PopupMenuItem<MedicineSort>(
            value: MedicineSort.nameAsc, child: Text('Name (A–Z)')),
        PopupMenuItem<MedicineSort>(
            value: MedicineSort.expirySoonest, child: Text('Expiry (soonest)')),
        PopupMenuItem<MedicineSort>(
            value: MedicineSort.quantityLowest, child: Text('Quantity (lowest)')),
        PopupMenuItem<MedicineSort>(
            value: MedicineSort.recentlyUpdated, child: Text('Recently updated')),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.onSurface),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: const <Widget>[
            Icon(Icons.sort, size: 16),
            SizedBox(width: 4),
            Text('Sort', style: TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool hasAny;
  final VoidCallback onAdd;
  const _EmptyState({required this.hasAny, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              hasAny ? Icons.search_off : Icons.inventory_2_outlined,
              size: 56,
            ),
            const SizedBox(height: 16),
            Text(
              hasAny ? 'No medicines match' : 'No medicines yet',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              hasAny
                  ? 'Try a different search or filter.'
                  : 'Tap “Add Medicine” to add your first item.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
