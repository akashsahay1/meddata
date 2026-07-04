import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../services/billing_service.dart';
import '../../services/settings_service.dart';
import '../../state/medicine_provider.dart';

/// Pure black & white subscription / paywall screen.
class UpgradeScreen extends StatefulWidget {
  const UpgradeScreen({super.key});

  @override
  State<UpgradeScreen> createState() => _UpgradeScreenState();
}

class _UpgradeScreenState extends State<UpgradeScreen> {
  String _selected = AppConstants.productYearly;
  bool _busy = false;

  static const List<_PlanInfo> _plans = <_PlanInfo>[
    _PlanInfo(
      id: AppConstants.productYearly,
      title: 'Yearly Plan',
      price: '₹999',
      period: 'per year',
      note: 'BEST VALUE · about ₹83/month',
      badge: 'BEST VALUE',
    ),
    _PlanInfo(
      id: AppConstants.productMonthly,
      title: 'Monthly Plan',
      price: '₹99',
      period: 'per month',
      note: 'Billed monthly, cancel anytime',
    ),
    _PlanInfo(
      id: AppConstants.productLifetime,
      title: 'Lifetime',
      price: '₹2,499',
      period: 'one-time',
      note: 'Pay once, yours forever',
    ),
  ];

  static const List<_Feature> _features = <_Feature>[
    _Feature(Icons.all_inclusive, 'Track unlimited medicines'),
    _Feature(Icons.notifications_active_outlined, 'Advanced expiry alerts'),
    _Feature(Icons.bar_chart_outlined, 'Detailed reports & analytics'),
    _Feature(Icons.cloud_outlined, 'Secure cloud backup & restore'),
    _Feature(Icons.file_download_outlined, 'Export to CSV & PDF'),
    _Feature(Icons.support_agent_outlined, 'Priority support'),
  ];

  Future<void> _subscribe() async {
    final BillingService billing = context.read<BillingService>();
    final ProductDetails? product = billing.productFor(_selected);
    setState(() => _busy = true);
    try {
      if (product != null) {
        await billing.buy(product);
      } else {
        // Store product not available — this is expected until the app is
        // published to Google Play with the subscription products configured
        // and opened via a licensed-tester account. (For testing premium
        // features now, use Settings → tap version 7× → Test premium unlock.)
        _showMessage(
            'Google Play subscriptions become available once the app is '
            'published with these products. See Settings for test options.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      await context.read<BillingService>().restore();
      _showMessage('Restoring purchases…');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final SettingsService settings = context.watch<SettingsService>();
    final MedicineProvider mp = context.watch<MedicineProvider>();
    final Color fg = Theme.of(context).colorScheme.onSurface;

    if (settings.isPremium) {
      return Scaffold(
        appBar: AppBar(title: const Text('Subscription')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.verified_outlined, size: 64),
                const SizedBox(height: 16),
                const Text('You are Premium',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text('Unlimited medicines and all premium features are '
                    'unlocked. Thank you!'),
                const SizedBox(height: 20),
                OutlinedButton(
                  onPressed: _restore,
                  child: const Text('Restore purchases'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Subscription')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          // Free plan status card.
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: fg),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: <Widget>[
                const Icon(Icons.medical_services_outlined, size: 32),
                const SizedBox(height: 8),
                const Text('Free Plan',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('${mp.totalCount} / ${AppConstants.freeTierMedicineLimit} medicines',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (mp.totalCount /
                            AppConstants.freeTierMedicineLimit)
                        .clamp(0, 1)
                        .toDouble(),
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${(AppConstants.freeTierMedicineLimit - mp.totalCount).clamp(0, AppConstants.freeTierMedicineLimit)} more medicines available',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('Premium Features',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          ..._features.map((_Feature f) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: <Widget>[
                    Icon(f.icon, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(f.label,
                            style: const TextStyle(fontSize: 15))),
                  ],
                ),
              )),
          const SizedBox(height: 16),
          const Text('Choose Your Plan',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          ..._plans.map((_PlanInfo p) => _PlanCard(
                plan: p,
                selected: _selected == p.id,
                priceOverride: _storePrice(context, p.id),
                onTap: () => setState(() => _selected = p.id),
              )),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _busy ? null : _subscribe,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Subscribe'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : _restore,
            child: const Text('Restore purchases'),
          ),
          const SizedBox(height: 12),
          const Text(
            'Subscriptions renew automatically until cancelled in Google Play. '
            'Your data always stays on your device.',
            style: TextStyle(fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// If the store returned localized prices, prefer them over the hard-coded ones.
  String? _storePrice(BuildContext context, String id) {
    final ProductDetails? p = context.read<BillingService>().productFor(id);
    return p?.price;
  }
}

class _PlanCard extends StatelessWidget {
  final _PlanInfo plan;
  final bool selected;
  final String? priceOverride;
  final VoidCallback onTap;
  const _PlanCard({
    required this.plan,
    required this.selected,
    required this.onTap,
    this.priceOverride,
  });

  @override
  Widget build(BuildContext context) {
    final Color fg = Theme.of(context).colorScheme.onSurface;
    final Color bg = Theme.of(context).colorScheme.surface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: selected ? fg : bg,
            border: Border.all(color: fg, width: selected ? 2 : 1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected ? bg : fg,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Text(plan.title,
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: selected ? bg : fg)),
                        if (plan.badge != null) ...<Widget>[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              border:
                                  Border.all(color: selected ? bg : fg),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(plan.badge!,
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: selected ? bg : fg)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(plan.note,
                        style: TextStyle(
                            fontSize: 12,
                            color: selected ? bg : fg)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(priceOverride ?? plan.price,
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: selected ? bg : fg)),
                  Text(plan.period,
                      style: TextStyle(
                          fontSize: 11, color: selected ? bg : fg)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanInfo {
  final String id;
  final String title;
  final String price;
  final String period;
  final String note;
  final String? badge;
  const _PlanInfo({
    required this.id,
    required this.title,
    required this.price,
    required this.period,
    required this.note,
    this.badge,
  });
}

class _Feature {
  final IconData icon;
  final String label;
  const _Feature(this.icon, this.label);
}
