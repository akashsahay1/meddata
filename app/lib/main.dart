import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/platform.dart';
import 'data/db/database_helper.dart';
import 'l10n/app_localizations.dart';

import 'services/auth_service.dart';
import 'services/device_id.dart';
import 'services/notification_service.dart';
import 'services/settings_service.dart';
import 'services/subscription_service.dart';
import 'state/medicine_provider.dart';
import 'sync/sync_engine.dart';
import 'theme/app_theme.dart';
import 'presentation/screens/auth/login_screen.dart';
import 'presentation/screens/lock_screen.dart';
import 'presentation/screens/main_shell.dart';
import 'presentation/screens/onboarding_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (AppPlatform.isDesktop) {
    // Desktop uses SQLite through FFI; keep the database in the app's
    // support folder (e.g. %APPDATA%\com.medstock\med_stock on Windows).
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseHelper.pathOverride =
        p.join((await getApplicationSupportDirectory()).path, 'meddata.db');
  }

  final SettingsService settings = SettingsService();
  await settings.init();

  final String deviceId = await DeviceId.get();

  final AuthService auth = AuthService(settings, deviceId);
  await auth.init();

  final SubscriptionService subscription =
      SubscriptionService(settings, deviceId);
  // The trial/entitlement/coupon endpoints are user-scoped and require the
  // auth token; supply it from AuthService.
  subscription.tokenProvider = () => auth.token;

  // Inventory is shared by all of the shop's devices through the server.
  final MedicineProvider medicines = MedicineProvider()..load();
  final SyncEngine sync = SyncEngine(
    tokenProvider: () => auth.token,
    userKeyProvider: () => auth.email,
    deviceId: () async => deviceId,
  )..onDataChanged = medicines.load;
  void followLogin() =>
      auth.isLoggedIn ? sync.start() : sync.stop();
  auth.addListener(followLogin);
  followLogin();
  // Catch up as soon as the app comes back to the foreground.
  AppLifecycleListener(onResume: sync.syncNow);

  runApp(MedStockApp(
    settings: settings,
    auth: auth,
    subscription: subscription,
    medicines: medicines,
    sync: sync,
  ));

  // Initialize notifications + background work AFTER the first frame. These
  // touch native plugin channels that can be slow (or stall) on iOS; awaiting
  // them before runApp would freeze the native splash. Best-effort only.
  unawaited(_startBackgroundServices(auth, settings, medicines));
}

/// Best-effort background init, run after runApp so it never blocks first paint.
Future<void> _startBackgroundServices(AuthService auth,
    SettingsService settings, MedicineProvider medicines) async {
  // If already logged in, sync the user's entitlement (premium/trial).
  if (auth.isLoggedIn) auth.refreshMe();

  try {
    await NotificationService.instance.init();
    await NotificationService.instance.requestPermissions();
  } catch (e) {
    debugPrint('Notification init skipped: $e');
  }

  // Keep scheduled alerts in step with the inventory (local edits and
  // changes synced from other devices) and with the alert settings.
  Timer? pending;
  Future<void> refreshAlerts() async {
    try {
      await NotificationService.instance.refreshAll(
        warningDays: settings.warningDays,
        notifyExpiry: settings.notifExpiry,
        notifyLowStock: settings.notifLowStock,
        hour: settings.reminderHour,
        minute: settings.reminderMinute,
      );
    } catch (e) {
      debugPrint('Alert scheduling skipped: $e');
    }
  }

  void scheduleRefresh() {
    pending?.cancel();
    pending = Timer(const Duration(seconds: 3), refreshAlerts);
  }

  medicines.addListener(scheduleRefresh);
  settings.addListener(scheduleRefresh);
  await refreshAlerts();
}

class MedStockApp extends StatelessWidget {
  final SettingsService settings;
  final AuthService auth;
  final SubscriptionService subscription;
  final MedicineProvider medicines;
  final SyncEngine sync;
  const MedStockApp({
    super.key,
    required this.settings,
    required this.auth,
    required this.subscription,
    required this.medicines,
    required this.sync,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<SettingsService>.value(value: settings),
        ChangeNotifierProvider<AuthService>.value(value: auth),
        ChangeNotifierProvider<SubscriptionService>.value(value: subscription),
        ChangeNotifierProvider<MedicineProvider>.value(value: medicines),
        ChangeNotifierProvider<SyncEngine>.value(value: sync),
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
