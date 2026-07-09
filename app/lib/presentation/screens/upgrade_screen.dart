import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/settings_service.dart';
import 'subscribe_view.dart';

/// Dismissible subscribe screen (opened from Settings / Home). When the trial
/// has ended the app instead shows the non-dismissible LockScreen.
class UpgradeScreen extends StatelessWidget {
  const UpgradeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final SettingsService s = context.watch<SettingsService>();

    if (s.isPremium) {
      return Scaffold(
        appBar: AppBar(title: const Text('Subscription')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const <Widget>[
                Icon(Icons.verified_outlined, size: 64),
                SizedBox(height: 16),
                Text('You are Premium',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                SizedBox(height: 8),
                Text('Unlimited medicines and all premium features are '
                    'unlocked. Thank you!'),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscription'),
        bottom: s.isTrialActive
            ? PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.only(bottom: 8),
                  alignment: Alignment.center,
                  child: Text(
                    s.trialDaysLeft <= 1
                        ? 'Free trial: last day'
                        : 'Free trial: ${s.trialDaysLeft} days left',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              )
            : null,
      ),
      body: SubscribeView(
        onUnlocked: () => Navigator.of(context).maybePop(),
      ),
    );
  }
}
