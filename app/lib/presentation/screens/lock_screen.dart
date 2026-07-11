import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/settings_service.dart';
import '../../services/subscription_service.dart';
import '../../theme/app_theme.dart';
import '../widgets/ui_kit.dart';
import 'subscribe_view.dart';

/// Shown when the 7-day trial has ended with no active subscription. The whole
/// app is locked behind this paywall (cannot be dismissed) until the user pays.
class LockScreen extends StatelessWidget {
  const LockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        body: SafeArea(
          child: Column(
            children: <Widget>[
              // Brand wordmark.
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 10, 18, 0),
                child: Row(
                  children: <Widget>[
                    BrandMark(size: 26),
                    SizedBox(width: 10),
                    Text('Meddata',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            color: AppColors.ink)),
                  ],
                ),
              ),
              // Dark "trial ended" card.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: AppColors.greenDarkest,
                    borderRadius: BorderRadius.circular(AppRadii.cardLg),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                          color: Color(0x660A302E),
                          blurRadius: 44,
                          offset: Offset(0, 20)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text('FREE TRIAL ENDED',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.6,
                                        color: AppColors.onDarkFaint)),
                                SizedBox(height: 6),
                                Text('Your trial has ended',
                                    style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.3,
                                        color: Colors.white)),
                                SizedBox(height: 6),
                                Text(
                                  'Subscribe to keep tracking your medicine '
                                  'stock and expiry. Your data is safe.',
                                  style: TextStyle(
                                      fontSize: 13,
                                      height: 1.45,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.onDarkMuted),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0x2EFF6B2C),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: const Icon(Icons.lock_outline,
                                size: 22, color: AppColors.orange),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          onPressed: () =>
                              context.read<SubscriptionService>().refresh(),
                          icon: const Icon(Icons.refresh,
                              size: 16, color: AppColors.orangeLight),
                          label: const Text('I already paid, refresh',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.orangeLight)),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadii.input),
                              side: const BorderSide(color: Color(0x1FFFFFFF)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
