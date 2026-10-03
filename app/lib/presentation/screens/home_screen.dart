import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/medicine.dart';
import '../../services/settings_service.dart';
import '../../state/medicine_provider.dart';
import '../../theme/app_theme.dart';
import '../widgets/status_chip.dart'; // exports the shared ui_kit + medicineStatusPill
import '../widgets/sync_badge.dart';
import 'add_edit_medicine_screen.dart';
import 'alerts_screen.dart';
import 'medicine_detail_screen.dart';
import 'settings_screen.dart';
import 'upgrade_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: RefreshIndicator(
        onRefresh: mp.load,
        child: ListView(
          padding: EdgeInsets.zero,
          physics: const AlwaysScrollableScrollPhysics(),
          children: <Widget>[
            _Header(onProfile: () => _open(const SettingsScreen()), onSearch: _addMedicine),
            // The cards overlap the rounded green header by ~40px, matching the design.
            Transform.translate(
              offset: const Offset(0, -40),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
                child: _DashboardBody(
                  mp: mp,
                  settings: settings,
                  currency: settings.currency,
                  onUpgrade: _openUpgrade,
                  onAlerts: () => _open(const AlertsScreen()),
                  onOpenMedicine: (Medicine m) =>
                      _open(MedicineDetailScreen(medicineId: m.id)),
                ),
              ),
            ),
            const SizedBox(height: 56),
          ],
        ),
      ),
    );
  }
}

/// Green rounded-bottom header: greeting, app/store name, profile avatar button
/// and a search-or-add pill.
class _Header extends StatelessWidget {
  final VoidCallback onProfile;
  final VoidCallback onSearch;
  const _Header({required this.onProfile, required this.onSearch});

  String _greeting() {
    final int h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final double topInset = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(22, topInset + 20, 22, 62),
      decoration: const BoxDecoration(
        color: AppColors.green,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(26),
          bottomRight: Radius.circular(26),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _greeting(),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onDarkMuted,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'Meddata',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SyncBadge(onDark: true),
              const SizedBox(width: 10),
              _AvatarButton(onTap: onProfile),
            ],
          ),
          const SizedBox(height: 20),
          Material(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: onSearch,
              borderRadius: BorderRadius.circular(14),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 15, vertical: 13),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.search, size: 18, color: AppColors.onDarkMuted),
                    SizedBox(width: 10),
                    Text(
                      'Search or add medicine',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.onDarkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AvatarButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.greenMid,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: const SizedBox(
          width: 42,
          height: 42,
          child: Icon(Icons.person_outline, size: 22, color: Colors.white),
        ),
      ),
    );
  }
}

/// The overlapping card stack: two StatCards, two AlertCards, an optional trial
/// banner, then the "Needs attention" section.
class _DashboardBody extends StatelessWidget {
  final MedicineProvider mp;
  final SettingsService settings;
  final String currency;
  final VoidCallback onUpgrade;
  final VoidCallback onAlerts;
  final ValueChanged<Medicine> onOpenMedicine;

  const _DashboardBody({
    required this.mp,
    required this.settings,
    required this.currency,
    required this.onUpgrade,
    required this.onAlerts,
    required this.onOpenMedicine,
  });

  static String _grouped(int n) {
    final String s = n.abs().toString();
    final StringBuffer b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i != 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final List<Medicine> all = mp.visibleAllForAlerts;
    final int totalUnits =
        all.fold(0, (int sum, Medicine m) => sum + m.quantity);
    final int catCount = all
        .map((Medicine m) => m.category.trim())
        .where((String c) => c.isNotEmpty)
        .toSet()
        .length;

    final List<Medicine> attention = all.where((Medicine m) {
      final s = mp.statusOf(m);
      return s.isExpired || s.isExpiring || s.isLowStock || m.quantity == 0;
    }).toList()
      ..sort((Medicine a, Medicine b) =>
          _severity(mp, a).compareTo(_severity(mp, b)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: StatCard(
                label: 'Stock value',
                value: '$currency${_grouped(mp.totalStockValue.round())}',
                sub: '${_grouped(totalUnits)} units',
                subColor: AppColors.statusGreen,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                label: 'Medicines',
                value: '${mp.totalCount}',
                sub: catCount == 1 ? '1 category' : '$catCount categories',
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: <Widget>[
            Expanded(
              child: AlertCard(
                icon: Icons.inventory_2_outlined,
                count: mp.lowStockCount,
                label: 'Low on stock',
                color: AppColors.statusAmber,
                bg: AppColors.statusAmberBg,
                onTap: onAlerts,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AlertCard(
                icon: Icons.schedule,
                count: mp.expiringCount,
                label: 'Expiring soon',
                color: AppColors.statusRed,
                bg: AppColors.statusRedBg,
                onTap: onAlerts,
              ),
            ),
          ],
        ),
        if (!settings.isPremium && settings.isTrialActive) ...<Widget>[
          const SizedBox(height: 14),
          _TrialBanner(daysLeft: settings.trialDaysLeft, onUpgrade: onUpgrade),
        ],
        const SizedBox(height: 22),
        SectionHeader(
          title: 'Needs attention',
          actionLabel: 'See all',
          onAction: onAlerts,
        ),
        const SizedBox(height: 12),
        if (attention.isEmpty)
          const _AllGoodCard()
        else
          ...attention.map((Medicine m) {
            final s = mp.statusOf(m);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: MedicineTile(
                name: m.name,
                subtitle: _subtitle(m),
                status: medicineStatusPill(s, m.quantity),
                onTap: () => onOpenMedicine(m),
              ),
            );
          }),
      ],
    );
  }

  static String _subtitle(Medicine m) {
    final String qty = '${m.quantity} ${m.unit}';
    if (m.brand.trim().isEmpty) return qty;
    return '${m.brand} · $qty';
  }

  // Lower value sorts first: expired < expiring < out of stock < low.
  static int _severity(MedicineProvider mp, Medicine m) {
    final s = mp.statusOf(m);
    if (s.isExpired) return 0;
    if (s.isExpiring) return 1;
    if (m.quantity == 0) return 2;
    return 3;
  }
}

/// Friendly empty state shown when nothing needs attention.
class _AllGoodCard extends StatelessWidget {
  const _AllGoodCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.statusGreenBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.check_circle_outline,
                size: 22, color: AppColors.statusGreen),
          ),
          const SizedBox(width: 13),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'All good',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Nothing low or expiring right now.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Subtle orange-tinted trial banner that opens the paywall.
class _TrialBanner extends StatelessWidget {
  final int daysLeft;
  final VoidCallback onUpgrade;
  const _TrialBanner({required this.daysLeft, required this.onUpgrade});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.statusAmberBg,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: InkWell(
        onTap: onUpgrade,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: <Widget>[
              const Icon(Icons.timelapse, size: 18, color: AppColors.orangeHover),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  daysLeft <= 1
                      ? 'Free trial: last day. Subscribe to keep access.'
                      : 'Free trial: $daysLeft days left',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Subscribe',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.orangeHover,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
