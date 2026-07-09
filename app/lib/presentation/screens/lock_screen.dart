import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/settings_service.dart';
import '../../services/subscription_service.dart';
import 'subscribe_view.dart';

/// Shown when the 7-day trial has ended with no active subscription. The whole
/// app is locked behind this paywall (cannot be dismissed) until the user pays.
class LockScreen extends StatelessWidget {
  const LockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final Color fg = Theme.of(context).colorScheme.onSurface;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: Column(
                  children: <Widget>[
                    Icon(Icons.lock_outline, size: 48, color: fg),
                    const SizedBox(height: 12),
                    const Text('Your free trial has ended',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    const Text(
                      'Subscribe to keep tracking your medicine stock and '
                      'expiry. Your data is safe.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () =>
                          context.read<SubscriptionService>().refresh(),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('I already paid — refresh'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SubscribeView(
                  onUnlocked: () {
                    // hasAccess flips true → _RootGate rebuilds to HomeScreen.
                    context.read<SubscriptionService>().refresh();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small helper used by other screens to show trial status text.
String trialStatusText(SettingsService s) {
  if (s.isPremium) return 'Premium active';
  if (s.isTrialActive) {
    final int d = s.trialDaysLeft;
    return d <= 1 ? 'Trial: last day' : 'Trial: $d days left';
  }
  return 'Trial ended';
}
