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
    DatabaseHelper.pathOverride = p.join(
      (await getApplicationSupportDirectory()).path,
      'meddata.db',
    );
  }

  final SettingsService settings = SettingsService();
  await settings.init();

  final String deviceId = await DeviceId.get();

  final AuthService auth = AuthService(settings, deviceId);
  await auth.init();

  final SubscriptionService subscription = SubscriptionService(
    settings,
    deviceId,
  );
  // The trial/entitlement/coupon endpoints are user-scoped and require the
  // auth token; supply it from AuthService.
  subscription.tokenProvider = () => auth.token;

  // Inventory is shared by all of the shop's devices through the server.
  final MedicineProvider medicines = MedicineProvider()..load();
  final SyncEngine sync =
      SyncEngine(
          tokenProvider: () => auth.token,
          // Local data belongs to the account's server id, so changing the email
          // keeps it; the email is only shown in messages.
          userKeyProvider: () => auth.userId,
          userEmailProvider: () => auth.email,
          deviceId: () async => deviceId,
        )
        ..onDataChanged = medicines.load
        // The server refused the login during a sync: sign out as on a 401
        // anywhere else (offline or a server error never signs out).
        ..onUnauthorized = auth.sessionRejected;
  bool wasLoggedIn = auth.isLoggedIn;
  void followLogin() {
    auth.isLoggedIn ? sync.start() : sync.stop();
    if (wasLoggedIn && !auth.isLoggedIn) {
      // Signed out (here or because the server refused the login): close
      // any screens open on top, so the login screen shows.
      _navigator.currentState?.popUntil((Route<dynamic> r) => r.isFirst);
    }
    wasLoggedIn = auth.isLoggedIn;
  }

  auth.addListener(followLogin);
  followLogin();
  // Catch up as soon as the app comes back to the foreground, plan
  // included. The counter PC can stay open for days: the plan is also
  // re-read every hour, so a renewal, an expiry or a change made in the
  // admin panel reaches the app without a restart.
  AppLifecycleListener(onResume: () {
    sync.syncNow();
    if (auth.isLoggedIn) auth.refreshMe();
  });
  Timer.periodic(const Duration(hours: 1), (_) {
    if (auth.isLoggedIn) auth.refreshMe();
  });

  runApp(
    MeddataApp(
      settings: settings,
      auth: auth,
      subscription: subscription,
      medicines: medicines,
      sync: sync,
    ),
  );

  // Initialize notifications + background work AFTER the first frame. These
  // touch native plugin channels that can be slow (or stall) on iOS; awaiting
  // them before runApp would freeze the native splash. Best-effort only.
  unawaited(_startBackgroundServices(auth, settings, medicines));
}

/// The app's navigator, to close open screens when the user is signed out.
final GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();

/// Best-effort background init, run after runApp so it never blocks first paint.
Future<void> _startBackgroundServices(
  AuthService auth,
  SettingsService settings,
  MedicineProvider medicines,
) async {
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

/// Root application widget. The package identifier remains `med_stock` for
/// compatibility, while the customer-facing product name is Meddata.
class MeddataApp extends StatelessWidget {
  final SettingsService settings;
  final AuthService auth;
  final SubscriptionService subscription;
  final MedicineProvider medicines;
  final SyncEngine sync;
  const MeddataApp({
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
          final MedicineProvider mp = Provider.of<MedicineProvider>(
            context,
            listen: false,
          );
          mp.warningDays = s.warningDays;
          mp.isPremium = s.hasAccess;

          return MaterialApp(
            navigatorKey: _navigator,
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
