import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../core/constants.dart';
import '../data/models/medicine.dart';
import '../data/repositories/medicine_repository.dart';

/// Local export/import (always free) of the medicine list. Exports to CSV;
/// imports from either a JSON backup or CSV.
class BackupService {
  final MedicineRepository _repo;
  BackupService([MedicineRepository? repo])
      : _repo = repo ?? MedicineRepository();

  Future<File> _fileIn(String dir, String name) async {
    final Directory d = Directory(dir);
    if (!await d.exists()) await d.create(recursive: true);
    return File('$dir/$name');
  }

  /// Export all medicines to CSV and share it.
  Future<File> exportCsv() async {
    final List<Medicine> all = await _repo.getAll();
    final List<List<Object?>> rows = <List<Object?>>[
      <Object?>[
        'Name', 'Brand', 'Category', 'Batch', 'Barcode', 'Quantity', 'Unit',
        'Low Stock At', 'Purchase Price', 'Selling Price', 'Expiry',
      ],
      ...all.map((Medicine m) => <Object?>[
            m.name, m.brand, m.category, m.batchNo, m.barcode, m.quantity,
            m.unit, m.lowStockThreshold, m.purchasePrice, m.sellingPrice,
            DateFormat('yyyy-MM-dd').format(m.expiryDate),
          ]),
    ];
    final String csvContent = Csv().encode(rows);
    final Directory dir = await getTemporaryDirectory();
    final String stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final File file = await _fileIn(dir.path, 'med_stock_$stamp.csv');
    await file.writeAsString(csvContent);
    return file;
  }

  Future<void> share(File file, {String text = 'Medicine stock backup'}) async {
    await SharePlus.instance
        .share(ShareParams(files: <XFile>[XFile(file.path)], text: text));
  }

  /// Import a JSON backup file. Adds its medicines to the current inventory
  /// with fresh ids (inventory is synced across devices now, so wiping it
  /// here would not remove anything from the server).
  Future<int> importJson(File file) async {
    final Map<String, dynamic> data =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final List<dynamic> meds = (data['medicines'] as List<dynamic>? ?? <dynamic>[]);
    int count = 0;
    for (final dynamic raw in meds) {
      final Map<String, Object?> row = Map<String, Object?>.from(raw as Map);
      if ((row['is_deleted'] as int? ?? 0) == 1) continue;
      final Medicine m = Medicine.fromMap(row);
      await _repo.insert(Medicine(
        id: const Uuid().v4(),
        name: m.name,
        brand: m.brand,
        category: m.category,
        batchNo: m.batchNo,
        barcode: m.barcode,
        quantity: m.quantity,
        unit: m.unit,
        lowStockThreshold: m.lowStockThreshold,
        purchasePrice: m.purchasePrice,
        sellingPrice: m.sellingPrice,
        mfgDate: m.mfgDate,
        expiryDate: m.expiryDate,
        notes: m.notes,
        createdAt: m.createdAt,
        updatedAt: m.updatedAt,
      ));
      count++;
    }
    return count;
  }

  /// Import medicines from a CSV file (Name, Quantity, Expiry yyyy-MM-dd
  /// required; other columns optional). Appends to existing data.
  Future<int> importCsv(File file) async {
    final String content = await file.readAsString();
    final List<List<dynamic>> rows = Csv().decode(content);
    if (rows.isEmpty) return 0;
    int count = 0;
    final DateFormat df = DateFormat('yyyy-MM-dd');
    // Skip header row if it looks like text.
    final int start = (rows.first.isNotEmpty &&
            rows.first.first.toString().toLowerCase().contains('name'))
        ? 1
        : 0;
    for (int i = start; i < rows.length; i++) {
      final List<dynamic> r = rows[i];
      if (r.isEmpty) continue;
      final String name = r[0].toString().trim();
      if (name.isEmpty) continue;
      DateTime expiry = DateTime.now().add(const Duration(days: 365));
      final int qty = _asInt(r, 5, fallback: _asInt(r, 1));
      try {
        final int expIdx = r.length > 10 ? 10 : r.length - 1;
        expiry = df.parse(r[expIdx].toString().trim());
      } catch (_) {}
      final DateTime now = DateTime.now();
      await _repo.insert(Medicine(
        id: const Uuid().v4(),
        name: name,
        brand: _asStr(r, 1),
        category: _asStr(r, 2),
        batchNo: _asStr(r, 3),
        barcode: _asStr(r, 4),
        quantity: qty,
        unit: _asStr(r, 6, fallback: 'Tablets'),
        lowStockThreshold:
            _asInt(r, 7, fallback: AppConstants.defaultLowStockThreshold),
        purchasePrice: _asDouble(r, 8),
        sellingPrice: _asDouble(r, 9),
        expiryDate: expiry,
        createdAt: now,
        updatedAt: now,
      ));
      count++;
    }
    return count;
  }

  String _asStr(List<dynamic> r, int i, {String fallback = ''}) =>
      (i < r.length && r[i] != null && r[i].toString().trim().isNotEmpty)
          ? r[i].toString().trim()
          : fallback;

  int _asInt(List<dynamic> r, int i, {int fallback = 0}) {
    if (i >= r.length) return fallback;
    return int.tryParse(r[i].toString().trim()) ?? fallback;
  }

  double _asDouble(List<dynamic> r, int i, {double fallback = 0}) {
    if (i >= r.length) return fallback;
    return double.tryParse(r[i].toString().trim()) ?? fallback;
  }
}
