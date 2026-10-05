import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:med_stock/data/db/database_helper.dart';
import 'package:med_stock/data/models/medicine.dart';
import 'package:med_stock/data/models/stock_import.dart';
import 'package:med_stock/data/models/stock_movement.dart';
import 'package:med_stock/data/repositories/medicine_repository.dart';
import 'package:med_stock/services/import/import_columns.dart';
import 'package:med_stock/services/import/sheet_table.dart';
import 'package:med_stock/services/import/spreadsheet_reader.dart';
import 'package:med_stock/services/import/stock_import_planner.dart';
import 'package:med_stock/sync/outbox.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

void main() {
  sqfliteFfiInit();
  final DatabaseFactory factory = databaseFactoryFfi;
  late DatabaseHelper helper;
  late MedicineRepository repo;
  late String path;

  setUp(() async {
    path = '${await factory.getDatabasesPath()}/import_${const Uuid().v4()}.db';
    helper = DatabaseHelper.at(factory, path);
    repo = MedicineRepository(helper);
  });

  tearDown(() async {
    Outbox.onEnqueued = null;
    await helper.close();
    await factory.deleteDatabase(path);
  });

  Medicine med(String name, String batch, int qty,
      {String brand = 'Micro Labs', String unit = 'Tablets'}) {
    final DateTime now = DateTime.now();
    return Medicine(
      id: const Uuid().v4(),
      name: name,
      brand: brand,
      batchNo: batch,
      quantity: qty,
      unit: unit,
      sellingPrice: 30,
      purchasePrice: 18,
      expiryDate: DateTime(2027, 1, 31),
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<List<Map<String, Object?>>> outbox() async =>
      (await helper.database).query('outbox', orderBy: 'seq');

  /// Reads [csv] the way the wizard does and plans it against the stock.
  Future<ImportPlan> planCsv(String csv,
      {DuplicatePolicy duplicates = DuplicatePolicy.skip}) async {
    final SheetTable t = SpreadsheetReader.read(
        Uint8List.fromList(utf8.encode(csv)),
        fileName: 'stock.csv').single;
    final int header = ColumnGuesser.guessHeaderRow(t);
    return StockImportPlanner.plan(
      t,
      ImportSettings(
        headerRow: header,
        columns: ColumnGuesser.guessColumns(t, header),
        duplicates: duplicates,
      ),
      inventory: await repo.getAll(),
    );
  }

  test('an import saves products, batches and opening stock, queued for sync', () async {
    int pings = 0;
    Outbox.onEnqueued = () => pings++;
    final ImportPlan p = await planCsv(
        'Item Name,Mfr,Batch,Qty,Pack,Exp,MRP,Rate\n'
        'Dolo 650,Micro Labs,D1,20,15\'s,12/27,33.60,24\n'
        'Dolo 650,Micro Labs,D2,5,15\'s,01/28,33.60,24\n'
        'Crocin,GSK,C1,0,TAB,06/27,25,18\n'
        'ORS,,,12,SACHET,30/06/2027,21,15\n');
    expect(p.importable, 3, reason: 'Crocin has quantity 0');

    final List<(int, int)> progress = <(int, int)>[];
    final StockImportResult r = await repo.importStock(p.toSave,
        onProgress: (int done, int total) => progress.add((done, total)));
    expect(<int>[r.medicinesAdded, r.batchesAdded, r.batchesToppedUp, r.unitsAdded],
        <int>[2, 3, 0, 37]);
    expect(progress.last, (3, 3));
    expect(pings, 1, reason: 'one sync nudge for the whole import');

    final List<Medicine> all = await repo.getAll();
    expect(all.map((Medicine m) => '${m.name}/${m.batchNo}/${m.quantity}/${m.unit}'),
        <String>['Dolo 650/D1/20/Strips', 'Dolo 650/D2/5/Strips', 'ORS//12/Sachets']);
    expect(all.where((Medicine m) => m.name == 'Dolo 650').map((Medicine m) => m.productId).toSet(),
        hasLength(1));
    final Medicine d1 = all.first;
    expect(<Object?>[d1.sellingPrice, d1.purchasePrice, d1.expiryDate, d1.brand],
        <Object?>[33.6, 24.0, DateTime(2027, 12, 31), 'Micro Labs']);
    expect((await repo.movementsFor(d1.id)).single.reason, StockReason.add);
    expect(await repo.activeCount(), 2);

    final List<Map<String, Object?>> out = await outbox();
    expect(out.map((Map<String, Object?> o) => o['table_name']), <String>[
      'products', 'batches', 'stock_movements', // D1 creates Dolo 650
      'batches', 'stock_movements', // D2 joins it
      'products', 'batches', 'stock_movements', // ORS
    ]);
    expect(out.every((Map<String, Object?> o) => o['base_version'] == null), isTrue);
    final Map<String, Object?> batch =
        jsonDecode(out[1]['data'] as String) as Map<String, Object?>;
    expect(batch['product_id'], out[0]['row_id']);
    expect(batch['expiry_date'], '2027-12-31');
    expect(batch['mrp_paise'], 3360);
    final Map<String, Object?> move =
        jsonDecode(out[2]['data'] as String) as Map<String, Object?>;
    expect(<Object?>[move['batch_id'], move['delta_units'], move['reason']],
        <Object?>[out[1]['row_id'], 20, 'opening']);
  });

  test('rows join stock already here; a duplicate batch can add quantity', () async {
    final Medicine d1 = med('Dolo 650', 'D1', 4);
    await repo.insert(d1);
    await (await helper.database).delete('outbox');

    final ImportPlan p = await planCsv(
        'Item Name,Batch,Qty,Exp\n'
        'dolo 650,d1,6,12/27\n'
        'Dolo 650,D7,3,12/28\n',
        duplicates: DuplicatePolicy.addQuantity);
    expect(p.rows.map((ImportRow r) => r.action),
        <RowAction>[RowAction.addStock, RowAction.newBatch]);
    final StockImportResult r = await repo.importStock(p.toSave);
    expect(<int>[r.medicinesAdded, r.batchesAdded, r.batchesToppedUp, r.unitsAdded],
        <int>[0, 1, 1, 9]);

    expect((await repo.getById(d1.id))!.quantity, 10);
    final List<StockMovement> moves = await repo.movementsFor(d1.id);
    expect(moves.map((StockMovement m) => m.change), containsAll(<int>[4, 6]));
    final List<Medicine> all = await repo.getAll();
    expect(all.map((Medicine m) => m.batchNo), <String>['D1', 'D7']);
    expect(all.map((Medicine m) => m.productId).toSet(), hasLength(1));
    expect(await repo.activeCount(), 1);

    final List<Map<String, Object?>> out = await outbox();
    expect(out.map((Map<String, Object?> o) => o['table_name']),
        <String>['stock_movements', 'batches', 'stock_movements']);
    expect(jsonDecode(out.first['data'] as String)['reason'], 'purchase');
  });

  test('a medicine deleted since the preview is created again', () async {
    final Medicine d1 = med('Dolo 650', 'D1', 4);
    await repo.insert(d1);
    final ImportPlan p = await planCsv(
        'Item Name,Batch,Qty,Exp\nDolo 650,D2,3,12/28\nDolo 650,D3,1,12/28\n');
    expect(p.toSave.every((StockImportRow s) => s.productId != null), isTrue);

    await repo.softDelete(d1.id); // e.g. another device deleted it meanwhile
    final StockImportResult r = await repo.importStock(p.toSave);
    expect(r.medicinesAdded, 1);
    final List<Medicine> all = await repo.getAll();
    expect(all.map((Medicine m) => m.batchNo), <String>['D2', 'D3']);
    expect(all.map((Medicine m) => m.productId).toSet(), hasLength(1));
    expect(all.first.name, 'Dolo 650');
    expect(all.first.brand, 'Micro Labs');
  });

  test('thousands of rows import in one go', () async {
    final StringBuffer csv = StringBuffer('Item Name,Batch,Qty,Exp\n');
    for (int i = 0; i < 3000; i++) {
      csv.writeln('Medicine ${i % 1000},B$i,${i % 9 + 1},12/27');
    }
    final ImportPlan p = await planCsv(csv.toString());
    final Stopwatch w = Stopwatch()..start();
    final StockImportResult r = await repo.importStock(p.toSave);
    w.stop();
    expect(<int>[r.medicinesAdded, r.batchesAdded], <int>[1000, 3000]);
    expect(await repo.activeCount(), 1000);
    expect((await outbox()).length, 1000 + 3000 * 2);
    expect(w.elapsedMilliseconds, lessThan(20000));
  });
}
