// Two simulated devices (separate SQLite files) syncing through a REAL
// backend. Skipped unless a server is given:
//
//   flutter test test/integration/sync_two_devices_test.dart \
//     --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1 \
//     --dart-define=SYNC_IT=true
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:med_stock/data/db/database_helper.dart';
import 'package:med_stock/data/models/medicine.dart';
import 'package:med_stock/data/models/stock_movement.dart';
import 'package:med_stock/data/repositories/medicine_repository.dart';
import 'package:med_stock/services/api_client.dart';
import 'package:med_stock/sync/sync_engine.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

const bool _enabled = bool.fromEnvironment('SYNC_IT');

class Device {
  Device(this.name, this.db, this.token, this.email)
      : repo = MedicineRepository(db),
        engine = SyncEngine(
          tokenProvider: () => token,
          userKeyProvider: () => email,
          db: db,
          deviceId: () async => name,
        );
  final String name;
  final DatabaseHelper db;
  final String token;
  final String email;
  final MedicineRepository repo;
  final SyncEngine engine;

  Future<void> sync() => engine.syncNow();
  Future<Medicine> only() async => (await repo.getAll()).single;
}

/// Points a device's API at a dead port to simulate "no internet".
class OfflineApi extends ApiClient {
  @override
  Future<({int status, Map<String, dynamic>? body})> syncPush(String token,
          {required String deviceId,
          required List<Map<String, Object?>> mutations,
          String? platform}) async =>
      (status: 0, body: null);

  @override
  Future<({int status, Map<String, dynamic>? body})> currentShop(String token) async =>
      (status: 0, body: null);
}

void main() {
  if (!_enabled) {
    test('two-device sync against a real backend', () {},
        skip: 'needs a running backend: --dart-define=SYNC_IT=true');
    return;
  }
  sqfliteFfiInit();
  final DatabaseFactory f = databaseFactoryFfi;
  final List<String> paths = <String>[];

  Future<DatabaseHelper> freshDb() async {
    final String path =
        '${await f.getDatabasesPath()}/it_${const Uuid().v4()}.db';
    paths.add(path);
    return DatabaseHelper.at(f, path);
  }

  Future<(String, String)> register() async {
    final String email = 'it-${const Uuid().v4().substring(0, 8)}@test.local';
    final http.Response r = await http.post(
      Uri.parse('${ApiClient.baseUrl}/auth/register'),
      headers: <String, String>{'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: jsonEncode(<String, String>{
        'name': 'IT', 'email': email, 'password': 'Passw0rd!x', 'password_confirmation': 'Passw0rd!x',
      }),
    );
    expect(r.statusCode, inInclusiveRange(200, 201), reason: r.body);
    return ((jsonDecode(r.body) as Map<String, dynamic>)['token'] as String, email);
  }

  Medicine med(String name, int qty, double mrp) {
    final DateTime now = DateTime.now();
    return Medicine(
        id: const Uuid().v4(),
        name: name,
        brand: 'Acme',
        batchNo: 'B1',
        quantity: qty,
        sellingPrice: mrp,
        expiryDate: DateTime(2027, 10, 31),
        createdAt: now,
        updatedAt: now);
  }

  tearDownAll(() async {
    for (final String p in paths) {
      await f.deleteDatabase(p);
    }
  });

  test('phone and PC stay in step: stock, prices, conflicts', () async {
    final (String token, String email) = await register();
    final Device phone = Device('phone', await freshDb(), token, email);
    final Device pc = Device('pc', await freshDb(), token, email);

    // Phone had inventory before it was linked (e.g. upgraded app).
    await phone.repo.insert(med('Paracetamol 500', 10, 30));
    await phone.sync();
    expect(phone.engine.status, SyncStatus.idle, reason: '${phone.engine.lastError}');
    expect(phone.engine.pending, 0);

    // A new PC logs in and receives everything.
    await pc.sync();
    Medicine onPc = await pc.only();
    expect(<Object>[onPc.name, onPc.quantity, onPc.sellingPrice], <Object>['Paracetamol 500', 10, 30.0]);

    // PC sells 3; the phone sees 7.
    await pc.repo.adjustQuantity(onPc.id, -3, StockReason.sell);
    await pc.sync();
    await phone.sync();
    expect((await phone.only()).quantity, 7);

    // Phone raises the price to 32 and syncs; the PC sells one more (no
    // price edit) - that must NOT clash with the price change.
    final Medicine onPhone = await phone.only();
    await phone.repo.update(onPhone.copyWith(sellingPrice: 32));
    await phone.sync();
    await pc.repo.adjustQuantity(onPc.id, -1, StockReason.sell);
    await pc.sync();
    onPc = await pc.only();
    expect(onPc.sellingPrice, 32.0, reason: 'PC must show the new price');
    expect(onPc.quantity, 6);
    expect(pc.engine.issues, isEmpty);

    // Both edit the price "at the same time": phone wins the race...
    await phone.sync();
    await phone.repo.update((await phone.only()).copyWith(sellingPrice: 35));
    await pc.repo.update(onPc.copyWith(sellingPrice: 31)); // PC hasn't seen 35
    await phone.sync();
    await pc.sync();

    // ...so the PC gets a conflict, shows the server price (never its own
    // unconfirmed 31), and keeps its attempt for the user to decide.
    expect((await pc.only()).sellingPrice, 35.0);
    expect(pc.engine.issues, hasLength(1));
    final SyncIssue issue = pc.engine.issues.single;
    expect(<Object>[issue.status, issue.reason, issue.mine['mrp_paise']!], <Object>['conflict', 'version_mismatch', 3100]);
    expect(issue.theirs?['mrp_paise'], 3500);

    // User chooses "keep mine": it is re-applied on top of 35 and wins.
    await pc.engine.keepMine(issue);
    await pc.sync();
    await phone.sync();
    expect(pc.engine.issues, isEmpty);
    expect((await phone.only()).sellingPrice, 31.0);
    expect((await pc.only()).sellingPrice, 31.0);
  });

  test('changes made offline wait and sync later; nothing is lost', () async {
    final (String token, String email) = await register();
    final DatabaseHelper pcDb = await freshDb();
    final Device phone = Device('phone', await freshDb(), token, email);
    await phone.repo.insert(med('Cetirizine', 20, 18));
    await phone.sync();

    final Device pc = Device('pc', pcDb, token, email);
    await pc.sync();
    final Medicine m = await pc.only();

    // PC loses internet and keeps working.
    final SyncEngine offline = SyncEngine(
        tokenProvider: () => token,
        userKeyProvider: () => email,
        db: pcDb,
        api: OfflineApi(),
        deviceId: () async => 'pc');
    await pc.repo.adjustQuantity(m.id, -5, StockReason.sell);
    await offline.syncNow();
    expect(offline.status, SyncStatus.offline);
    expect(offline.pending, 1);
    expect((await pc.only()).quantity, 15, reason: 'local view includes the unsynced sale');

    // Back online.
    await pc.sync();
    await phone.sync();
    expect(pc.engine.pending, 0);
    expect((await phone.only()).quantity, 15);
    expect((await pc.only()).quantity, 15, reason: 'not double-counted after sync');
  });

  test('second device with its own data must choose merge or discard', () async {
    final (String token, String email) = await register();
    final Device phone = Device('phone', await freshDb(), token, email);
    await phone.repo.insert(med('Azithromycin', 6, 120));
    await phone.sync();

    final Device pc = Device('pc', await freshDb(), token, email);
    await pc.repo.insert(med('ORS', 50, 20));
    await pc.sync();
    expect(pc.engine.needsLocalDataChoice, isTrue);
    // Nothing reaches the shop before the user chooses.
    await phone.sync();
    expect((await phone.repo.getAll()).map((Medicine m) => m.name), <String>['Azithromycin']);

    await pc.engine.resolveLocalData(LocalDataChoice.merge);
    await phone.sync();
    final Set<String> names = (await phone.repo.getAll()).map((Medicine m) => m.name).toSet();
    expect(names, <String>{'Azithromycin', 'ORS'});

    // A third device chooses discard: it keeps only the shop's data.
    final Device tab = Device('tab', await freshDb(), token, email);
    await tab.repo.insert(med('Local only', 1, 1));
    await tab.sync();
    await tab.engine.resolveLocalData(LocalDataChoice.discard);
    expect((await tab.repo.getAll()).map((Medicine m) => m.name).toSet(), <String>{'Azithromycin', 'ORS'});
    await phone.sync();
    expect((await phone.repo.getAll()).length, 2, reason: 'discarded items never reach the shop');
  });
}
