import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'l10n/app_localizations.dart';

import 'services/background_worker.dart';
import 'services/billing_service.dart';
import 'services/device_id.dart';
import 'services/notification_service.dart';
import 'services/settings_service.dart';
import 'state/medicine_provider.dart';
import 'theme/app_theme.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/onboarding_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final SettingsService settings = SettingsService();
  await settings.init();

  await NotificationService.instance.init();
  await BackgroundWorker.init();

  final String deviceId = await DeviceId.get();
  final BillingService billing = BillingService(settings, deviceId);
  // Fire and forget — billing/entitlement reconcile in the background.
  _startBackgroundServices(billing, settings);

  runApp(MedStockApp(settings: settings, billing: billing));
}

/// Kick off background services without blocking first paint.
void _startBackgroundServices(BillingService billing, SettingsService settings) {
  billing.init();
  BackgroundWorker.scheduleDailyDigest(
    warningDays: settings.warningDays,
    notifExpiry: settings.notifExpiry,
    notifLowStock: settings.notifLowStock,
  );
  NotificationService.instance.requestPermissions();
}

class MedStockApp extends StatelessWidget {
  final SettingsService settings;
  final BillingService billing;
  const MedStockApp({super.key, required this.settings, required this.billing});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<SettingsService>.value(value: settings),
        Provider<BillingService>.value(value: billing),
        ChangeNotifierProvider<MedicineProvider>(
          create: (_) => MedicineProvider()..load(),
        ),
      ],
      child: Consumer<SettingsService>(
        builder: (BuildContext context, SettingsService s, _) {
          // Keep the medicine provider's derived state in sync with settings.
          final MedicineProvider mp =
              Provider.of<MedicineProvider>(context, listen: false);
          mp.warningDays = s.warningDays;
          mp.isPremium = s.isPremium;

          return MaterialApp(
            title: 'Medicine Stock & Expiry Tracker',
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
            home: s.onboarded ? const HomeScreen() : const OnboardingScreen(),
          );
        },
      ),
    );
  }
}
