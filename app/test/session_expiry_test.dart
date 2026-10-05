// A login the server no longer accepts (401: logged out elsewhere, password
// changed or reset) signs the app out wherever it shows up: background sync,
// billing and invoice reading. Being offline, a timeout or a server error
// never does. Signing out keeps the inventory and unsynced changes.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:med_stock/data/db/database_helper.dart';
import 'package:med_stock/data/models/medicine.dart';
import 'package:med_stock/data/repositories/medicine_repository.dart';
import 'package:med_stock/presentation/screens/billing/bills_screen.dart';
import 'package:med_stock/services/accounting_api.dart';
import 'package:med_stock/services/api_client.dart';
import 'package:med_stock/services/auth_service.dart';
import 'package:med_stock/services/billing_api.dart';
import 'package:med_stock/services/invoice_scan_service.dart';
import 'package:med_stock/services/settings_service.dart';
import 'package:med_stock/sync/sync_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;

import 'support/test_app.dart';

typedef _Reply = ({int status, Map<String, dynamic>? body});

/// The server as sync sees it: an empty shop; push answers [pushStatus]
/// (accepting every change when 200); login hands out a new token.
class _SyncServer extends ApiClient {
  int pushStatus = 200;
  int pushes = 0;

  @override
  Future<_Reply> currentShop(String token) async =>
      (status: 200, body: <String, dynamic>{'has_data': false});

  @override
  Future<_Reply> syncPush(String token,
      {required String deviceId,
      required List<Map<String, Object?>> mutations,
      String? platform}) async {
    pushes++;
    if (pushStatus != 200) return (status: pushStatus, body: null);
    return (
      status: 200,
      body: <String, dynamic>{
        'results': <Map<String, Object?>>[
          for (final Map<String, Object?> _ in mutations)
            <String, Object?>{'status': 'ok', 'version': 1},
        ],
      },
    );
  }

  @override
  Future<_Reply> syncPull(String token,
          {required int since, required String deviceId, int limit = 500}) async =>
      (status: 200, body: <String, dynamic>{'changes': <String, dynamic>{}, 'next': since});

  @override
  Future<_Reply> login(
          {required String email, required String password, String? deviceId}) async =>
      (
        status: 200,
        body: <String, dynamic>{
          'token': 'tok-2',
          'user': <String, dynamic>{'id': 7, 'email': email, 'name': 'Akash'},
        },
      );

  @override
  Future<void> logout(String token) async {}
}

Future<AuthService> _signedIn(ApiClient api) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'auth_token_secure': true,
    'auth_email': 'owner@example.com',
    'auth_user_id': '7',
  });
  final SettingsService settings = SettingsService();
  await settings.init();
  final AuthService auth =
      AuthService(settings, 'phone-1', api, MemoryTokenStore()..value = 'tok');
  await auth.init();
  expect(auth.isLoggedIn, isTrue);
  return auth;
}

Medicine _medicine() {
  final DateTime now = DateTime.now();
  return Medicine(
    id: 'm1',
    name: 'Dolo 650',
    brand: 'Micro Labs',
    batchNo: 'B1',
    quantity: 10,
    expiryDate: DateTime(2030, 12, 31),
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('background sync', () {
    late DatabaseHelper db;
    late _SyncServer server;
    late AuthService auth;
    late SyncEngine sync;

    setUp(() async {
      db = memoryDatabase();
      server = _SyncServer();
      auth = await _signedIn(server);
      sync = SyncEngine(
        tokenProvider: () => auth.token,
        userKeyProvider: () => auth.userId,
        userEmailProvider: () => auth.email,
        api: server,
        db: db,
        deviceId: () async => 'phone-1',
      )..onUnauthorized = auth.sessionRejected;
      // A medicine added on this device, not uploaded yet.
      await MedicineRepository(db).insert(_medicine());
    });

    tearDown(() async {
      sync.dispose();
      await db.close();
    });

    Future<int> outboxRows() async => Sqflite.firstIntValue(
        await (await db.database).rawQuery('SELECT COUNT(*) FROM outbox'))!;

    test('a 401 signs out but keeps the unsynced changes for the next login',
        () async {
      server.pushStatus = 401;
      await sync.syncNow();

      expect(auth.isLoggedIn, isFalse);
      expect(auth.sessionExpired, isTrue);
      expect(sync.status, SyncStatus.error);
      final int waiting = await outboxRows();
      expect(waiting, greaterThan(0), reason: 'nothing unsynced is dropped');
      expect((await MedicineRepository(db).getAll()).single.name, 'Dolo 650');

      // Signed out: sync does nothing.
      final int pushes = server.pushes;
      await sync.syncNow();
      expect(server.pushes, pushes);

      // The same account signs in again: the waiting changes are uploaded
      // (no merge/discard question, the device is still linked to it).
      server.pushStatus = 200;
      expect(await auth.login(email: 'owner@example.com', password: 'x'), isNull);
      expect(auth.sessionExpired, isFalse);
      await sync.syncNow();
      expect(sync.needsLocalDataChoice, isFalse);
      expect(sync.status, SyncStatus.idle, reason: sync.lastError);
      expect(await outboxRows(), 0);
    });

    for (final int status in <int>[0, 500, 503, 403]) {
      test('status $status (offline / server error) keeps the user signed in',
          () async {
        server.pushStatus = status;
        await sync.syncNow();

        expect(auth.isLoggedIn, isTrue);
        expect(auth.sessionExpired, isFalse);
        expect(sync.status, status == 0 ? SyncStatus.offline : SyncStatus.error);
        expect(await outboxRows(), greaterThan(0));
      });
    }
  });

  group('AuthService.sessionRejected', () {
    test('ignores a token that is no longer the current one', () async {
      final AuthService auth = await _signedIn(_SyncServer());
      await auth.sessionRejected('an-older-token');
      expect(auth.isLoggedIn, isTrue);
      await auth.sessionRejected('tok');
      expect(auth.isLoggedIn, isFalse);
    });

    test('a normal log out is not reported as an expired session', () async {
      final AuthService auth = await _signedIn(_SyncServer());
      await auth.logout();
      expect(auth.sessionExpired, isFalse);
    });
  });

  group('billing', () {
    /// Answers every call with [status].
    BillingApi api(int status, List<String> rejected) => BillingApi(
          ApiClient(MockClient((http.Request r) async {
            if (status == 0) throw http.ClientException('no route to host');
            return http.Response('{"message":"x"}', status);
          })),
          rejected.add,
        );

    test('a 401 on any call reports the token; other failures do not', () async {
      final List<String> rejected = <String>[];
      final BillingApi unauthorized = api(401, rejected);
      expect(await unauthorized.create('tok', <String, Object?>{}), isA<BillFailed>());
      expect((await unauthorized.list('tok')).status, 401);
      expect((await unauthorized.get('tok', 'b1')).status, 401);
      expect((await unauthorized.cancel('tok', 'b1')).status, 401);
      expect((await unauthorized.shop('tok')).status, 401);
      expect((await unauthorized.updateShop('tok', <String, Object?>{})).status, 401);
      expect(rejected, List<String>.filled(6, 'tok'));
      expect((await unauthorized.list('tok')).message,
          'Your session has expired. Please log in again.');

      rejected.clear();
      expect(await api(0, rejected).create('tok', <String, Object?>{}), isA<BillOffline>());
      expect((await api(0, rejected).list('tok')).isOffline, isTrue);
      expect((await api(500, rejected).shop('tok')).status, 500);
      expect((await api(403, rejected).get('tok', 'b1')).status, 403);
      expect(rejected, isEmpty);
    });

    testWidgets('the bills list signs out on a 401, not when offline',
        (WidgetTester tester) async {
      usePhoneScreen(tester);
      final TestApp app = await TestApp.create(signedIn: true);
      addTearDown(app.dispose);
      int status = 0;
      final BillingApi billing = BillingApi(ApiClient(MockClient((_) async {
        if (status == 0) throw http.ClientException('offline');
        return http.Response('{"message":"Unauthenticated"}', status);
      })));

      await tester.pumpWidget(app.wrap(BillsScreen(api: billing)));
      await tester.pumpAndSettle();
      expect(app.auth.isLoggedIn, isTrue);
      expect(find.text('Try again'), findsOneWidget);

      status = 401;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(app.auth.isLoggedIn, isFalse);
      expect(app.auth.sessionExpired, isTrue);
    });
  });

  group('accounting', () {
    /// Answers every call with [status].
    AccountingApi api(int status, List<String> rejected) => AccountingApi(
          ApiClient(MockClient((http.Request r) async {
            if (status == 0) throw http.ClientException('no route to host');
            return http.Response('{"message":"x"}', status);
          })),
          rejected.add,
        );

    test('a 401 on any call reports the token; other failures do not', () async {
      final List<String> rejected = <String>[];
      final AccountingApi unauthorized = api(401, rejected);
      await unauthorized.parties('tok');
      await unauthorized.party('tok', 'p1');
      await unauthorized.ledger('tok', 'p1');
      await unauthorized.purchases('tok');
      await unauthorized.recordPayment('tok', <String, Object?>{});
      await unauthorized.gstReport('tok', '2026-10', gstr1: true);
      expect(rejected, List<String>.filled(6, 'tok'));

      rejected.clear();
      await api(0, rejected).parties('tok');
      await api(500, rejected).purchases('tok');
      await api(403, rejected).party('tok', 'p1');
      expect(rejected, isEmpty);
    });
  });

  group('invoice reading', () {
    InvoiceScanService service(Object reply, List<String> rejected) =>
        InvoiceScanService(
          baseUrl: 'https://api.test/api/v1',
          client: MockClient((_) async {
            if (reply is int) {
              return http.Response(jsonEncode(<String, String>{'message': 'x'}), reply);
            }
            throw reply;
          }),
          onUnauthorized: rejected.add,
        );

    test('a 401 reports the token and says to log in again', () async {
      final List<String> rejected = <String>[];
      InvoiceScanResponse r = await service(401, rejected)
          .upload(token: 'tok', bytes: <int>[1], filename: 'a.jpg');
      expect(r.message, 'Your session has expired. Please log in again.');
      r = await service(401, rejected).fetch(token: 'tok', id: 1);
      expect(r.scan, isNull);
      expect(rejected, <String>['tok', 'tok']);
    });

    test('offline, a timeout or a server error keeps the user signed in',
        () async {
      final List<String> rejected = <String>[];
      final InvoiceScanResponse offline =
          await service(http.ClientException('offline'), rejected)
              .fetch(token: 'tok', id: 1);
      expect(offline.offline, isTrue);
      expect(offline.message, InvoiceScanService.offlineMessage);
      final InvoiceScanResponse down = await service(503, rejected)
          .upload(token: 'tok', bytes: <int>[1], filename: 'a.jpg');
      expect(down.offline, isFalse);
      expect(down.message, 'The server had a problem. Please try again.');
      expect(rejected, isEmpty);
    });
  });
}
