import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/settings_service.dart';
import '../../theme/app_theme.dart';
import '../widgets/ui_kit.dart';
import 'subscribe_view.dart';

/// Dismissible subscribe screen (opened from Settings / Home). When the trial
/// has ended the app instead shows the non-dismissible LockScreen.
class UpgradeScreen extends StatelessWidget {
  const UpgradeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final SettingsService s = context.watch<SettingsService>();

    if (s.isPremium) return const _PremiumConfirmation();

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            // ---- Header: back button + centered title ---------------------
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: <Widget>[
                  _BackButton(onTap: () => Navigator.of(context).maybePop()),
                ],
              ),
            ),
            // Title and subtitle come from SubscribeView's hero; only the
            // trial countdown is specific to this screen.
            if (s.isTrialActive)
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 6, 22, 0),
                child: _TrialPill(daysLeft: s.trialDaysLeft),
              ),
            const SizedBox(height: 4),
            // ---- Plans / coupon / CTA (logic-owning SubscribeView) --------
            Expanded(
              child: SubscribeView(
                onUnlocked: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// White rounded-square back button matching the design header.
class _BackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: AppColors.border),
        ),
        child: const Icon(Icons.chevron_left, size: 22, color: AppColors.ink),
      ),
    );
  }
}

/// Amber trial countdown pill.
class _TrialPill extends StatelessWidget {
  final int daysLeft;
  const _TrialPill({required this.daysLeft});

  @override
  Widget build(BuildContext context) {
    final String label = daysLeft <= 1
        ? 'Free trial: last day'
        : 'Free trial: $daysLeft days left';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.statusAmberBg,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.schedule, size: 15, color: AppColors.statusAmber),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: AppColors.statusAmber,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when the user is already Premium.
class _PremiumConfirmation extends StatelessWidget {
  const _PremiumConfirmation();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('Subscription')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const BrandMark(size: 64),
              const SizedBox(height: 20),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.statusGreenBg,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.verified_rounded,
                        size: 16, color: AppColors.statusGreen),
                    SizedBox(width: 6),
                    Text(
                      'PRO ACTIVE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                        color: AppColors.statusGreen,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'You are Premium',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Unlimited medicines and all premium features are '
                'unlocked. Thank you!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.muted,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
