import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'l10n/app_localizations.dart';

import 'services/auth_service.dart';
import 'services/background_worker.dart';
import 'services/device_id.dart';
import 'services/notification_service.dart';
import 'services/settings_service.dart';
import 'services/subscription_service.dart';
import 'state/medicine_provider.dart';
import 'theme/app_theme.dart';
import 'presentation/screens/auth/login_screen.dart';
import 'presentation/screens/lock_screen.dart';
import 'presentation/screens/main_shell.dart';
import 'presentation/screens/onboarding_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final SettingsService settings = SettingsService();
  await settings.init();

  final String deviceId = await DeviceId.get();

  final AuthService auth = AuthService(settings, deviceId);
  await auth.init();

  await NotificationService.instance.init();
  await BackgroundWorker.init();

  final SubscriptionService subscription =
      SubscriptionService(settings, deviceId);
  // The trial/entitlement/coupon endpoints are user-scoped and require the
  // auth token; supply it from AuthService.
  subscription.tokenProvider = () => auth.token;
  _startBackgroundServices(auth, settings);

  runApp(MedStockApp(
    settings: settings,
    auth: auth,
    subscription: subscription,
  ));
}

/// Kick off background services without blocking first paint.
void _startBackgroundServices(AuthService auth, SettingsService settings) {
  // If already logged in, sync the user's entitlement (premium/trial).
  if (auth.isLoggedIn) auth.refreshMe();
  BackgroundWorker.scheduleDailyDigest(
    warningDays: settings.warningDays,
    notifExpiry: settings.notifExpiry,
    notifLowStock: settings.notifLowStock,
  );
  NotificationService.instance.requestPermissions();
}

class MedStockApp extends StatelessWidget {
  final SettingsService settings;
  final AuthService auth;
  final SubscriptionService subscription;
  const MedStockApp({
    super.key,
    required this.settings,
    required this.auth,
    required this.subscription,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<SettingsService>.value(value: settings),
        ChangeNotifierProvider<AuthService>.value(value: auth),
        ChangeNotifierProvider<SubscriptionService>.value(value: subscription),
        ChangeNotifierProvider<MedicineProvider>(
          create: (_) => MedicineProvider()..load(),
        ),
      ],
      child: Consumer<SettingsService>(
        builder: (BuildContext context, SettingsService s, _) {
          // During trial or paid, the app has full access → unlimited medicines.
          final MedicineProvider mp =
              Provider.of<MedicineProvider>(context, listen: false);
          mp.warningDays = s.warningDays;
          mp.isPremium = s.hasAccess;

          return MaterialApp(
            title: 'Meddata — Medicine Stock & Expiry Tracker',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: s.themeMode,
            locale: s.locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const <LocalizationsDelegate<Object?>>[
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const _RootGate(),
          );
        },
      ),
    );
  }
}

/// Routing gate: onboarding → login/signup → trial/paid app → or the lock
/// paywall once the trial has ended with no active subscription.
class _RootGate extends StatelessWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context) {
    final SettingsService s = context.watch<SettingsService>();
    final AuthService auth = context.watch<AuthService>();
    if (!s.onboarded) return const OnboardingScreen();
    if (!auth.isLoggedIn) return const LoginScreen();
    if (!s.hasAccess) return const LockScreen();
    return const MainShell();
  }
}
