// The data on a device belongs to the account's stable server id, not its
// email: changing the email keeps everything (and uploads what is waiting).
// When a different account signs in while the previous one still has changes
// that were never uploaded, nothing is deleted until the user decides.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:med_stock/data/db/database_helper.dart';
import 'package:med_stock/data/models/medicine.dart';
import 'package:med_stock/data/repositories/medicine_repository.dart';
import 'package:med_stock/presentation/screens/account_switch_dialog.dart';
import 'package:med_stock/presentation/screens/auth/login_screen.dart';
import 'package:med_stock/services/api_client.dart';
import 'package:med_stock/services/auth_service.dart';
import 'package:med_stock/services/settings_service.dart';
import 'package:med_stock/sync/sync_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' show Database, Sqflite;

import 'support/test_app.dart';

typedef _Reply = ({int status, Map<String, dynamic>? body});

/// Two accounts on the server (ids 7 and 8); a token names its account.
/// Records which account each pushed change went to.
class _Server extends ApiClient {
  final Map<String, int> ids = <String, int>{
    'owner@example.com': 7,
    'other@example.com': 8,
  };
  final Map<int, String> emails = <int, String>{
    7: 'owner@example.com',
    8: 'other@example.com',
  };
  final Map<int, int> pushed = <int, int>{};
  bool online = true;

  int _account(String token) => int.parse(token.split('-').last);

  Map<String, dynamic> _user(int id) =>
      <String, dynamic>{'id': id, 'email': emails[id], 'name': 'User $id'};

  @override
  Future<_Reply> login(
      {required String email, required String password, String? deviceId}) async {
    final int? id = ids[email];
    if (id == null) return (status: 422, body: <String, dynamic>{'message': 'no'});
    return (
      status: 200,
      body: <String, dynamic>{'token': 'tok-$id', 'user': _user(id)},
    );
  }

  @override
  Future<_Reply> me(String token) async => (
        status: 200,
        body: <String, dynamic>{'user': _user(_account(token))},
      );

  @override
  Future<_Reply> updateProfile(
      {required String token, String? name, String? email}) async {
    final int id = _account(token);
    if (email != null) {
      ids.remove(emails[id]);
      emails[id] = email;
      ids[email] = id;
    }
    return (status: 200, body: <String, dynamic>{'user': _user(id)});
  }

  @override
  Future<void> logout(String token) async {}

  @override
  Future<_Reply> currentShop(String token) async => online
      ? (status: 200, body: <String, dynamic>{'has_data': false})
      : (status: 0, body: null);

  @override
  Future<_Reply> syncPush(String token,
      {required String deviceId,
      required List<Map<String, Object?>> mutations,
      String? platform}) async {
    if (!online) return (status: 0, body: null);
    final int id = _account(token);
    pushed[id] = (pushed[id] ?? 0) + mutations.length;
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
}

/// Signed in as owner@example.com (id 7), or with [prefs] as saved by an
/// older build.
Future<AuthService> _auth(_Server server, {Map<String, Object>? prefs}) async {
  SharedPreferences.setMockInitialValues(prefs ??
      <String, Object>{
        'auth_token_secure': true,
        'auth_email': 'owner@example.com',
        'auth_user_id': '7',
      });
  final SettingsService settings = SettingsService();
  await settings.init();
  final AuthService auth = AuthService(
      settings, 'phone-1', server, MemoryTokenStore()..value = 'tok-7');
  await auth.init();
  return auth;
}

SyncEngine _engine(AuthService auth, _Server server, DatabaseHelper db) =>
    SyncEngine(
      tokenProvider: () => auth.token,
      userKeyProvider: () => auth.userId,
      userEmailProvider: () => auth.email,
      api: server,
      db: db,
      deviceId: () async => 'phone-1',
    );

Medicine _medicine(String name) {
  final DateTime now = DateTime.now();
  return Medicine(
    id: name,
    name: name,
    brand: 'Micro Labs',
    batchNo: 'B1',
    quantity: 10,
    expiryDate: DateTime(2030, 12, 31),
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  late DatabaseHelper db;
  late _Server server;
  late MedicineRepository repo;

  setUp(() {
    db = memoryDatabase();
    server = _Server();
    repo = MedicineRepository(db);
  });

  tearDown(() => db.close());

  Future<Database> sqlite() => db.database;
  Future<int> outboxRows() async => Sqflite.firstIntValue(
      await (await sqlite()).rawQuery('SELECT COUNT(*) FROM outbox'))!;
  Future<String?> state(String key) async {
    final List<Map<String, Object?>> r = await (await sqlite())
        .query('sync_state', where: 'key = ?', whereArgs: <Object?>[key]);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  Future<List<String>> names() async =>
      (await repo.getAll()).map((Medicine m) => m.name).toList()..sort();

  test('the login and /auth/me give the account id, kept across restarts',
      () async {
    final AuthService auth = await _auth(server, prefs: <String, Object>{});
    expect(await auth.login(email: 'other@example.com', password: 'x'), isNull);
    expect(auth.userId, '8');

    final SettingsService settings = SettingsService();
    await settings.init();
    final AuthService again = AuthService(
        settings, 'phone-1', server, MemoryTokenStore()..value = 'tok-8');
    await again.init();
    expect(again.userId, '8');

    await auth.logout();
    expect(auth.userId, isNull);
  });

  test('changing the email keeps the data and uploads the waiting changes',
      () async {
    final AuthService auth = await _auth(server);
    final SyncEngine sync = _engine(auth, server, db);
    addTearDown(sync.dispose);
    await repo.insert(_medicine('Dolo 650'));
    await sync.syncNow();
    expect(await outboxRows(), 0);
    expect(await state('linked_account'), '7');

    // A change waits (offline), then the email is changed in Profile.
    server.online = false;
    await repo.insert(_medicine('Azithral 500'));
    await sync.syncNow();
    expect(await outboxRows(), greaterThan(0));
    server.online = true;
    expect(await auth.updateProfile(email: 'new@example.com'), isNull);
    expect(auth.email, 'new@example.com');
    expect(auth.userId, '7');

    final int before = server.pushed[7]!;
    await sync.syncNow();
    expect(sync.accountSwitch, isNull);
    expect(sync.needsLocalDataChoice, isFalse);
    expect(sync.status, SyncStatus.idle, reason: sync.lastError);
    expect(await outboxRows(), 0, reason: 'the waiting change was uploaded');
    expect(server.pushed[7], greaterThan(before));
    expect(await names(), <String>['Azithral 500', 'Dolo 650']);
    expect(await state('linked_email'), 'new@example.com');
  });

  test(
      'a different account with changes waiting asks first and keeps the '
      'data until the user decides', () async {
    final AuthService auth = await _auth(server);
    final SyncEngine sync = _engine(auth, server, db);
    addTearDown(sync.dispose);
    // Linked to owner@ while offline: the medicine has not been uploaded.
    server.online = false;
    await repo.insert(_medicine('Dolo 650'));
    await sync.syncNow(); // offline: not linked yet
    server.online = true;
    await sync.syncNow();
    expect(await outboxRows(), 0);
    server.online = false;
    await repo.insert(_medicine('Azithral 500'));
    final int waiting = await outboxRows();
    expect(waiting, greaterThan(0));
    server.online = true;

    // other@ signs in on this phone.
    await auth.logout();
    sync.stop();
    expect(await auth.login(email: 'other@example.com', password: 'x'), isNull);
    await sync.syncNow();
    expect(sync.accountSwitch, isNotNull);
    expect(sync.accountSwitch!.previousAccount, 'owner@example.com');
    expect(sync.accountSwitch!.pendingChanges, waiting);
    expect(server.pushed[8], isNull, reason: "owner's changes never go to other");
    expect(await outboxRows(), waiting);
    expect(await names(), <String>['Azithral 500', 'Dolo 650']);

    // Still undecided: syncing again changes nothing.
    await sync.syncNow();
    expect(await outboxRows(), waiting);

    // Sign back in to owner@: the changes are uploaded to owner's shop.
    await auth.signInAgainAs('owner@example.com');
    sync.stop();
    expect(auth.isLoggedIn, isFalse);
    expect(auth.loginHint, 'owner@example.com');
    expect(sync.accountSwitch, isNull);
    expect(await auth.login(email: 'owner@example.com', password: 'x'), isNull);
    expect(auth.loginHint, isNull);
    final int before = server.pushed[7]!;
    await sync.syncNow();
    expect(await outboxRows(), 0);
    expect(server.pushed[7], before + waiting);

    // Now other@ switches in cleanly.
    await auth.logout();
    sync.stop();
    expect(await auth.login(email: 'other@example.com', password: 'x'), isNull);
    await sync.syncNow();
    expect(sync.accountSwitch, isNull);
    expect(await names(), isEmpty);
    expect(await state('linked_account'), '8');
  });

  test('removing the previous account changes needs the explicit call',
      () async {
    final AuthService auth = await _auth(server);
    final SyncEngine sync = _engine(auth, server, db);
    addTearDown(sync.dispose);
    await sync.syncNow(); // linked to owner@, nothing on the device
    server.online = false;
    await repo.insert(_medicine('Dolo 650'));
    server.online = true;
    await auth.logout();
    expect(await auth.login(email: 'other@example.com', password: 'x'), isNull);
    await sync.syncNow();
    expect(sync.accountSwitch, isNotNull);

    await sync.discardPreviousAccountChanges();
    expect(sync.accountSwitch, isNull);
    expect(await names(), isEmpty);
    expect(await outboxRows(), 0);
    expect(await state('linked_account'), '8');
    expect(server.pushed[8], isNull);
  });

  test('a different account with nothing waiting switches cleanly', () async {
    final AuthService auth = await _auth(server);
    final SyncEngine sync = _engine(auth, server, db);
    addTearDown(sync.dispose);
    await repo.insert(_medicine('Dolo 650'));
    await sync.syncNow();
    expect(await outboxRows(), 0);
    int reloads = 0;
    sync.onDataChanged = () => reloads++;

    await auth.logout();
    expect(await auth.login(email: 'other@example.com', password: 'x'), isNull);
    await sync.syncNow();
    expect(sync.accountSwitch, isNull);
    expect(sync.needsLocalDataChoice, isFalse);
    expect(sync.status, SyncStatus.idle, reason: sync.lastError);
    expect(await names(), isEmpty, reason: "owner's copy is safe on the server");
    expect(reloads, greaterThan(0));
    expect(await state('linked_account'), '8');
    expect(await state('linked_email'), 'other@example.com');
  });

  group('a link made by an older build (by email)', () {
    Future<void> legacyLink(String email) async {
      await (await sqlite()).insert('sync_state',
          <String, Object?>{'key': 'linked_user', 'value': email});
    }

    test('moves to the account id without a question', () async {
      final AuthService auth = await _auth(server);
      final SyncEngine sync = _engine(auth, server, db);
      addTearDown(sync.dispose);
      await repo.insert(_medicine('Dolo 650'));
      await legacyLink('Owner@Example.com');

      await sync.syncNow();
      expect(sync.accountSwitch, isNull);
      expect(sync.needsLocalDataChoice, isFalse);
      expect(await outboxRows(), 0);
      expect(server.pushed[7], greaterThan(0));
      expect(await state('linked_account'), '7');
      expect(await state('linked_user'), isNull);

      // Then the email changes: still the same account.
      expect(await auth.updateProfile(email: 'new@example.com'), isNull);
      await repo.insert(_medicine('Azithral 500'));
      await sync.syncNow();
      expect(sync.accountSwitch, isNull);
      expect(await outboxRows(), 0);
      expect(await names(), <String>['Azithral 500', 'Dolo 650']);
    });

    test('keeps syncing while the id is not known yet', () async {
      // An older build's login: no id saved until /auth/me answers.
      final AuthService auth = await _auth(server, prefs: <String, Object>{
        'auth_token_secure': true,
        'auth_email': 'owner@example.com',
      });
      expect(auth.userId, isNull);
      final SyncEngine sync = _engine(auth, server, db);
      addTearDown(sync.dispose);
      await repo.insert(_medicine('Dolo 650'));
      await legacyLink('owner@example.com');

      await sync.syncNow();
      expect(await outboxRows(), 0);
      expect(await state('linked_user'), 'owner@example.com');

      await auth.refreshMe();
      expect(auth.userId, '7');
      await sync.syncNow();
      expect(await state('linked_account'), '7');
      expect(await state('linked_user'), isNull);
      expect(await names(), <String>['Dolo 650']);
    });

    test("another account's email asks first when changes are waiting",
        () async {
      final AuthService auth = await _auth(server);
      final SyncEngine sync = _engine(auth, server, db);
      addTearDown(sync.dispose);
      await repo.insert(_medicine('Dolo 650'));
      await legacyLink('someone@example.com');

      await sync.syncNow();
      expect(sync.accountSwitch?.previousAccount, 'someone@example.com');
      expect(server.pushed, isEmpty);
      expect(await names(), <String>['Dolo 650']);
    });
  });

  group('the question', () {
    Future<(TestApp, SyncEngine)> show(WidgetTester tester) async {
      usePhoneScreen(tester);
      final TestApp app = await TestApp.create(signedIn: true);
      addTearDown(app.dispose);
      await app.addBatch('Dolo 650');
      final SyncEngine sync = app.sync
        ..accountSwitch = const AccountSwitch('owner@example.com', 3);
      await tester.pumpWidget(app.wrap(Builder(
        builder: (BuildContext context) => Scaffold(
          body: TextButton(
            onPressed: () => askAboutPreviousAccountChanges(context, sync),
            child: const Text('ask'),
          ),
        ),
      )));
      await tester.tap(find.text('ask'));
      await tester.pumpAndSettle();
      expect(
          find.textContaining('This device has 3 changes from owner@example.com '
              "that haven't been uploaded"),
          findsOneWidget);
      return (app, sync);
    }

    testWidgets('sign in again signs out and fills in the previous email',
        (WidgetTester tester) async {
      final (TestApp app, SyncEngine _) = await show(tester);
      await tester.tap(find.text('Sign in to owner@example.com'));
      await tester.pumpAndSettle();
      expect(app.auth.isLoggedIn, isFalse);
      expect(app.auth.loginHint, 'owner@example.com');

      await tester.pumpWidget(app.wrap(const LoginScreen()));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, 'owner@example.com'),
          findsOneWidget);
      expect(
          find.text('Log in as owner@example.com to upload the changes saved '
              'on this device.'),
          findsOneWidget);
    });

    testWidgets('removing needs a confirmation', (WidgetTester tester) async {
      final (TestApp app, SyncEngine sync) = await show(tester);
      await tester.tap(find.text('Remove them'));
      await tester.pumpAndSettle();
      expect(find.text('Remove 3 changes?'), findsOneWidget);

      // Changed their mind: back to the question, nothing removed.
      await tester.tap(find.text('Keep them'));
      await tester.pumpAndSettle();
      expect(find.text('Changes not uploaded yet'), findsOneWidget);
      expect(sync.accountSwitch, isNotNull);
      expect((await MedicineRepository(app.db).getAll()), isNotEmpty);

      await tester.tap(find.text('Remove them'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(sync.accountSwitch, isNull);
      expect((await MedicineRepository(app.db).getAll()), isEmpty);
      expect(app.auth.isLoggedIn, isTrue);
    });
  });
}
