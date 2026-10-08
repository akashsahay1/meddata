// Shared setup for widget tests: the app's providers (as in main.dart) over
// an in-memory inventory database, with the backend replaced by a fake so no
// test touches the network.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:med_stock/data/db/database_helper.dart';
import 'package:med_stock/data/models/medicine.dart';
import 'package:med_stock/data/repositories/medicine_repository.dart';
import 'package:med_stock/l10n/app_localizations.dart';
import 'package:med_stock/services/api_client.dart';
import 'package:med_stock/services/auth_service.dart';
import 'package:med_stock/services/settings_service.dart';
import 'package:med_stock/services/subscription_service.dart';
import 'package:med_stock/state/medicine_provider.dart';
import 'package:med_stock/sync/sync_engine.dart';
import 'package:med_stock/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

/// Today at midnight, plus [days].
DateTime day(int days) {
  final DateTime now = DateTime.now();
  return DateTime(now.year, now.month, now.day + days);
}

/// Date-only part of [d].
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// An in-memory database. Widget tests run on a fake clock, where real file
/// I/O never completes; sqflite_common_ffi without an isolate on an
/// in-memory database is fully synchronous, so it works there.
DatabaseHelper memoryDatabase() {
  sqfliteFfiInit();
  return DatabaseHelper.at(databaseFactoryFfiNoIsolate, inMemoryDatabasePath);
}

/// Loads the app's font so text is measured as on a phone (the default test
/// font draws every glyph as a 1em square, which overstates text widths).
Future<void> loadAppFont() async {
  final FontLoader font = FontLoader(AppTheme.fontFamily)
    ..addFont(rootBundle.load('assets/fonts/GoogleSansFlex-Variable.ttf'));
  await font.load();
}

/// A 360dp-wide phone (the common budget-Android width). Functional tests
/// use a tall one so whole forms are built without scrolling.
void usePhoneScreen(WidgetTester tester, {double height = 780}) {
  tester.view.physicalSize = Size(360 * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// The saved login in memory: the real store is platform secure storage,
/// which has no implementation under `flutter test` (a read never completes).
class MemoryTokenStore implements TokenStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String token) async => value = token;

  @override
  Future<void> delete() async => value = null;
}

/// The backend without a network. Master-catalog name search and barcode
/// lookup answer from [catalog]; a GET whose path ends with a key of
/// [responses] answers that JSON (200); every other call fails as if
/// offline. Requested URLs are kept in [requests].
class FakeBackend {
  FakeBackend({
    List<Map<String, Object?>>? catalog,
    Map<String, Object?>? responses,
  })  : catalog = catalog ?? defaultCatalog,
        responses = responses ?? <String, Object?>{};

  static const List<Map<String, Object?>> defaultCatalog =
      <Map<String, Object?>>[
    <String, Object?>{
      'name': 'Paracetamol 500mg',
      'manufacturer': 'GSK',
      'pack_size': '15 tablets',
      'unit': 'strips',
      'price': 22.5,
      'barcode': '8901000000011',
    },
    <String, Object?>{
      'name': 'Pantoprazole 40mg',
      'manufacturer': 'Alkem',
      'unit': 'Tablets',
      'price': 110,
    },
  ];

  final List<Map<String, Object?>> catalog;
  final Map<String, Object?> responses;
  final List<Uri> requests = <Uri>[];

  late final ApiClient api = ApiClient(MockClient(_handle));

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request.url);
    if (request.url.path.endsWith('/medicines/search')) {
      final String q = (request.url.queryParameters['q'] ?? '').toLowerCase();
      final String? code = request.url.queryParameters['barcode'];
      final List<Map<String, Object?>> results = <Map<String, Object?>>[
        for (final Map<String, Object?> m in catalog)
          if (code != null
              ? m['barcode'] == code
              : (m['name']! as String).toLowerCase().startsWith(q))
            m,
      ];
      return http.Response(
          jsonEncode(<String, Object?>{'results': results}), 200,
          headers: <String, String>{'content-type': 'application/json'});
    }
    if (request.method == 'GET') {
      for (final MapEntry<String, Object?> r in responses.entries) {
        if (request.url.path.endsWith(r.key)) {
          return http.Response(jsonEncode(r.value), 200,
              headers: <String, String>{'content-type': 'application/json'});
        }
      }
    }
    return http.Response('{"message":"offline"}', 503);
  }
}

/// The app's services and inventory for one test. Call [dispose] at the end
/// (closes the database).
class TestApp {
  TestApp._(this.db, this.settings, this.auth, this.subscription,
      this.medicines, this.sync, this.backend);

  final DatabaseHelper db;
  final SettingsService settings;
  final AuthService auth;
  final SubscriptionService subscription;
  final MedicineProvider medicines;
  final SyncEngine sync;
  final FakeBackend backend;

  /// Navigator of the app built by [wrap], to open screens the way the app
  /// does (so a screen that pops itself can be checked).
  final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();

  /// An onboarded shop with an empty inventory, signed out unless
  /// [signedIn] (as owner@example.com, token `tok`). [premium] (paid) lifts
  /// the free-plan limit, as the trial does.
  static Future<TestApp> create({
    DatabaseHelper? db,
    bool premium = true,
    bool signedIn = false,
    FakeBackend? backend,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'onboarded': true,
      'cached_premium': premium,
      if (signedIn) ...<String, Object>{
        'auth_token_secure': true,
        'auth_email': 'owner@example.com',
        'auth_name': 'Akash',
      },
    });
    final SettingsService settings = SettingsService();
    await settings.init();
    final FakeBackend fake = backend ?? FakeBackend();
    final AuthService auth = AuthService(settings, 'test-device', fake.api,
        MemoryTokenStore()..value = signedIn ? 'tok' : null);
    await auth.init();
    final SubscriptionService subscription =
        SubscriptionService(settings, 'test-device', fake.api);
    final DatabaseHelper database = db ?? memoryDatabase();
    // Same wiring as MedStockApp: alert window and plan come from settings.
    final MedicineProvider medicines =
        MedicineProvider(MedicineRepository(database))
          ..warningDays = settings.warningDays
          ..isPremium = settings.hasAccess;
    await medicines.load();
    // Never started and signed out, so it never syncs.
    final SyncEngine sync = SyncEngine(
      tokenProvider: () => null,
      userKeyProvider: () => null,
      api: fake.api,
      db: database,
    );
    return TestApp._(
        database, settings, auth, subscription, medicines, sync, fake);
  }

  /// Adds one batch (and its medicine, the first time the name is used), as
  /// the add screen would, and returns it as stored.
  Future<Medicine> addBatch(
    String name, {
    int qty = 20,
    int expiresInDays = 200,
    String brand = 'Micro Labs',
    String batch = '',
    String category = 'Pain Relief / Analgesic',
    String unit = 'Tablets',
    int packSize = 1,
    String barcode = '',
    int lowStock = 10,
    double mrp = 30,
    double purchase = 18,
    DateTime? mfg,
  }) async {
    final DateTime now = DateTime.now();
    final Medicine m = Medicine(
      id: const Uuid().v4(),
      name: name,
      brand: brand,
      category: category,
      batchNo: batch,
      barcode: barcode,
      quantity: qty,
      unit: unit,
      packSize: packSize,
      lowStockThreshold: lowStock,
      sellingPrice: mrp,
      purchasePrice: purchase,
      mfgDate: mfg,
      expiryDate: day(expiresInDays),
      createdAt: now,
      updatedAt: now,
    );
    await medicines.add(m, allowDuplicate: true);
    return medicines.findById(m.id)!;
  }

  /// A shop with one medicine in each state (30-day expiry warning, low
  /// stock at 10 units):
  /// - Paracetamol 500: 6 + 6 units, one batch expiring in 20 days
  /// - Cetirizine (Cipla, batch B-77): 4 units, low
  /// - Dolo 650: 5 units, expired 3 days ago (and low)
  /// - ORS: none left, out of stock
  /// - Azithral 500 (Antibiotic): 50 units, fine
  /// All at ₹30, 71 units in total.
  Future<void> seedShop() async {
    await addBatch('Paracetamol 500', qty: 6, batch: 'P1', expiresInDays: 200);
    await addBatch('Paracetamol 500', qty: 6, batch: 'P2', expiresInDays: 20);
    await addBatch('Cetirizine', qty: 4, batch: 'B-77', brand: 'Cipla');
    await addBatch('Dolo 650', qty: 5, batch: 'D1', expiresInDays: -3);
    await addBatch('ORS', qty: 0, batch: 'O1', expiresInDays: 300);
    await addBatch('Azithral 500',
        qty: 50, batch: 'A1', expiresInDays: 400, category: 'Antibiotic');
  }

  /// [home] inside the app's providers and theme. [textScale] mimics the
  /// phone's font-size setting.
  Widget wrap(Widget home, {double textScale = 1}) {
    return MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<SettingsService>.value(value: settings),
        ChangeNotifierProvider<AuthService>.value(value: auth),
        ChangeNotifierProvider<SubscriptionService>.value(value: subscription),
        ChangeNotifierProvider<MedicineProvider>.value(value: medicines),
        ChangeNotifierProvider<SyncEngine>.value(value: sync),
      ],
      child: MaterialApp(
        navigatorKey: navigator,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        locale: settings.locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const <LocalizationsDelegate<Object?>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: home,
      ),
    );
  }

  /// Pumps an empty app and opens [screen] on top of it, so the screen can
  /// close itself (Navigator.pop) as it does in the app.
  Future<void> open(WidgetTester tester, Widget screen,
      {double textScale = 1}) async {
    await tester.pumpWidget(wrap(const Scaffold(), textScale: textScale));
    navigator.currentState!
        .push(MaterialPageRoute<void>(builder: (_) => screen));
    await tester.pumpAndSettle();
  }

  Future<void> dispose() async {
    sync.dispose();
    await db.close();
  }
}
