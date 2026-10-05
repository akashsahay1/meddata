import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../data/models/medicine.dart';
import '../../data/models/stock_import.dart';
import 'import_columns.dart';
import 'import_values.dart';
import 'sheet_table.dart';

/// What to do with a row whose medicine and batch are already in stock, or
/// already on an earlier row of the file.
enum DuplicatePolicy { skip, addQuantity }

/// What importing a row will do.
enum RowAction { newMedicine, newBatch, addStock, skip }

/// The choices made in the import wizard.
class ImportSettings {
  /// Index of the row with the column names; -1 when the sheet has none.
  final int headerRow;
  final Map<ImportField, int> columns;
  final DateOrder dateOrder;
  final DuplicatePolicy duplicates;
  final bool skipZeroQuantity;

  /// Unit of a new medicine whose row doesn't say.
  final String defaultUnit;

  /// New medicines the free plan still allows; null = no limit.
  final int? newMedicineRoom;

  const ImportSettings({
    required this.headerRow,
    required this.columns,
    this.dateOrder = DateOrder.dayFirst,
    this.duplicates = DuplicatePolicy.skip,
    this.skipZeroQuantity = true,
    this.defaultUnit = 'Tablets',
    this.newMedicineRoom,
  });

  /// Required details that have no column yet.
  List<ImportField> get missing => <ImportField>[
        for (final ImportField f in ImportField.values)
          if (f.required && !columns.containsKey(f)) f,
      ];
}

/// One data row of the file and what importing it will do.
class ImportRow {
  /// The row's number in the spreadsheet (1 = first row).
  final int rowNumber;
  final String name;
  final String brand;
  final String batchNo;
  final int? quantity;
  final String unit;
  final DateTime? expiry;
  final RowAction action;

  /// Where an imported row goes, e.g. "New batch of the medicine on row 4".
  final String? detail;

  /// Why the row is skipped.
  final List<String> errors;

  /// Imported, but something was left out or read in a particular way.
  final List<String> warnings;

  const ImportRow({
    required this.rowNumber,
    required this.name,
    this.brand = '',
    this.batchNo = '',
    this.quantity,
    this.unit = '',
    this.expiry,
    required this.action,
    this.detail,
    this.errors = const <String>[],
    this.warnings = const <String>[],
  });

  bool get imported => action != RowAction.skip;
}

/// The checked rows of a file, and what saving them writes.
class ImportPlan {
  final List<ImportRow> rows;
  final List<StockImportRow> toSave;
  final int newMedicines;
  final int newBatches;
  final int addStock;
  final int skipped;

  /// Rows whose medicine and batch were already in stock or on an earlier row.
  final int duplicates;

  /// Rows with a quantity of 0 (skipped when [ImportSettings.skipZeroQuantity]).
  final int zeroQuantity;

  /// Rows skipped because the free plan has no room for their medicine.
  final int overLimit;

  /// New medicines in the file, whether or not the free plan has room.
  final int newMedicinesInFile;

  /// The file had more than [StockImportPlanner.maxRows] data rows.
  final bool truncated;

  const ImportPlan({
    required this.rows,
    required this.toSave,
    required this.newMedicines,
    required this.newBatches,
    required this.addStock,
    required this.skipped,
    required this.duplicates,
    required this.zeroQuantity,
    required this.overLimit,
    required this.newMedicinesInFile,
    required this.truncated,
  });

  int get importable => rows.length - skipped;
  int get withWarnings =>
      rows.where((ImportRow r) => r.imported && r.warnings.isNotEmpty).length;
}

/// Checks every row of a sheet against the column mapping and the shop's
/// stock, and works out what to save. Pure Dart: no database, no UI.
///
/// A row joins a medicine already in stock with the same name (ignoring
/// case and spacing) when the manufacturer and unit don't contradict it;
/// otherwise it's a new medicine, which later rows of the same medicine
/// join. The same medicine and batch number (or, without a batch number,
/// the same expiry date) twice is a duplicate: skipped, or its quantity
/// added, as the user chooses.
class StockImportPlanner {
  StockImportPlanner._();

  /// Data rows read from one file.
  static const int maxRows = 10000;

  static const Uuid _uuid = Uuid();
  static final RegExp _totalRow =
      RegExp(r'^(grand |sub ?)?total\b', caseSensitive: false);
  static final RegExp _scientific =
      RegExp(r'^\d(\.\d+)?e\+?\d+$', caseSensitive: false);
  static final RegExp _space = RegExp(r'\s+');
  static final RegExp _notAlnum = RegExp(r'[^a-z0-9]+');

  static ImportPlan plan(
    SheetTable sheet,
    ImportSettings settings, {
    List<Medicine> inventory = const <Medicine>[],
    DateTime? now,
  }) {
    final DateTime stamp = now ?? DateTime.now();
    final DateTime today = DateTime(stamp.year, stamp.month, stamp.day);
    final Map<String, List<_Product>> byName = _index(inventory);
    final List<ImportRow> rows = <ImportRow>[];
    // In row order: (product, batch) to create, or a ready top-up row.
    final List<Object> entries = <Object>[];
    final List<Object?>? header =
        settings.headerRow >= 0 && settings.headerRow < sheet.rows.length
            ? sheet.rows[settings.headerRow]
            : null;
    int planned = 0;
    int newMedicines = 0;
    int newBatches = 0;
    int addStock = 0;
    int duplicates = 0;
    int zero = 0;
    int overLimit = 0;
    int dataRows = 0;
    bool truncated = false;

    void skip(int rowNumber, _Draft d, String reason) {
      rows.add(d.toRow(rowNumber, RowAction.skip, errors: <String>[reason]));
    }

    for (int r = settings.headerRow + 1; r < sheet.rows.length; r++) {
      final List<Object?> cells = sheet.rows[r];
      if (!SheetTable.rowHasData(cells)) continue;
      // Exports repeat the column names at the top of every page.
      if (header != null && _sameAsHeader(cells, header)) continue;
      if (dataRows == maxRows) {
        truncated = true;
        break;
      }
      dataRows++;
      final int rowNumber = r + 1;
      final _Draft d = _read(cells, settings, today);
      if (d.errors.isEmpty && d.quantity == 0) {
        zero++;
        if (settings.skipZeroQuantity) d.errors.add('Quantity is 0');
      }
      if (d.errors.isNotEmpty) {
        rows.add(d.toRow(rowNumber, RowAction.skip));
        continue;
      }

      final String norm = _norm(d.name);
      _Product? p = _match(byName[norm], d.brand, d.unit);
      final bool created = p == null;
      if (p == null) {
        // Say why a medicine of the same name isn't used.
        final _Product? sameName = _match(byName[norm], d.brand, null);
        final List<_Product> others = byName[norm] ?? const <_Product>[];
        final String unit = d.unit ?? settings.defaultUnit;
        if (sameName != null && sameName.unit != unit) {
          d.warnings.add('${sameName.name} is already listed in '
              '${sameName.unit}; this row is added as a separate medicine '
              'in $unit');
        } else if (sameName == null && others.isNotEmpty) {
          d.warnings.add('${others.first.name} by ${others.first.brand} '
              'is already listed; this one by ${d.brand} is added as a '
              'separate medicine');
        }
        final int? room = settings.newMedicineRoom;
        p = _Product.planned('new${planned++}', d.name, d.brand, unit,
            rowNumber, blocked: room != null && newMedicines >= room);
        (byName[norm] ??= <_Product>[]).add(p);
        if (!p.blocked) newMedicines++;
      }
      if (p.blocked) {
        overLimit++;
        skip(rowNumber, d,
            'Free plan limit reached: no room for more medicines');
        continue;
      }

      final String key = _batchKey(d.batchNo, d.expiry!);
      final _Batch? same = p.batches[key];
      if (same != null) {
        duplicates++;
        final String where = same.existingId != null
            ? 'already in stock'
            : 'also on row ${same.row}';
        if (settings.duplicates == DuplicatePolicy.skip) {
          skip(rowNumber, d,
              same.existingId != null
                  ? 'Already in stock (same medicine and batch)'
                  : 'Same medicine and batch as row ${same.row}');
          continue;
        }
        if (d.quantity == 0) {
          skip(rowNumber, d, 'Same batch $where; quantity 0 adds nothing');
          continue;
        }
        if (same.existingId != null) {
          entries.add(StockImportRow(
            medicine: _medicine(p, d, d.quantity!, stamp),
            productId: p.existingId,
            productKey: p.key,
            addToBatchId: same.existingId,
          ));
          rows.add(d.toRow(rowNumber, RowAction.addStock,
              unit: p.unit,
              detail: 'Adds ${d.quantity} to the batch already in stock'));
        } else {
          same.quantity += d.quantity!;
          rows.add(d.toRow(rowNumber, RowAction.addStock,
              unit: p.unit, detail: 'Quantity added to row ${same.row}'));
        }
        addStock++;
        continue;
      }

      final _Batch b = _Batch.planned(rowNumber, d, d.quantity!);
      p.batches[key] = b;
      p.absorb(d);
      entries.add((p, b));
      if (created) {
        rows.add(d.toRow(rowNumber, RowAction.newMedicine, unit: p.unit));
      } else {
        newBatches++;
        rows.add(d.toRow(rowNumber, RowAction.newBatch,
            unit: p.unit,
            detail: p.existingId != null
                ? 'New batch of ${p.name} (already in stock)'
                : 'New batch of the medicine on row ${p.row}'));
      }
    }

    final List<StockImportRow> toSave = <StockImportRow>[
      for (final Object e in entries)
        switch (e) {
          (final _Product p, final _Batch b) => StockImportRow(
              medicine: _medicine(p, b.draft!, b.quantity, stamp),
              productId: p.existingId,
              productKey: p.key,
            ),
          _ => e as StockImportRow,
        },
    ];
    return ImportPlan(
      rows: rows,
      toSave: toSave,
      newMedicines: newMedicines,
      newBatches: newBatches,
      addStock: addStock,
      skipped: rows.where((ImportRow r) => !r.imported).length,
      duplicates: duplicates,
      zeroQuantity: zero,
      overLimit: overLimit,
      newMedicinesInFile: planned,
      truncated: truncated,
    );
  }

  /// One row's values, with what's wrong (errors skip the row) and what was
  /// adjusted (warnings).
  static _Draft _read(
      List<Object?> cells, ImportSettings s, DateTime today) {
    final _Draft d = _Draft();
    Object? cell(ImportField f) {
      final int? c = s.columns[f];
      return c == null || c < 0 || c >= cells.length ? null : cells[c];
    }

    String line(ImportField f) =>
        ImportValues.text(cell(f)).replaceAll(_space, ' ');

    d.name = line(ImportField.name);
    if (_totalRow.hasMatch(d.name)) {
      d.errors.add('Looks like a total row');
      return d;
    }
    if (d.name.isEmpty) {
      d.errors.add('Medicine name is missing');
    } else if (d.name.length > 255) {
      d.errors.add('Medicine name is longer than 255 characters');
    }

    d.brand = line(ImportField.manufacturer);
    if (d.brand.length > 255) {
      d.brand = d.brand.substring(0, 255);
      d.warnings.add('Manufacturer shortened to 255 characters');
    }
    d.category = ImportValues.categoryFrom(line(ImportField.category));

    d.batchNo = line(ImportField.batchNo);
    if (d.batchNo.length > 64) {
      d.errors.add('Batch no. is longer than 64 characters');
    }

    final String barcode = line(ImportField.barcode).replaceAll(' ', '');
    if (_scientific.hasMatch(barcode)) {
      d.warnings.add('Barcode "$barcode" was rounded by Excel (format the '
          'column as Text); left blank');
    } else if (barcode.length > 64) {
      d.warnings.add('Barcode is longer than 64 characters; left blank');
    } else {
      d.barcode = barcode;
    }

    final QuantityValue q = ImportValues.parseQuantity(cell(ImportField.quantity));
    if (q.error != null) {
      d.errors.add(q.error!);
    } else {
      d.quantity = q.value;
      if (q.note != null) d.warnings.add(q.note!);
    }

    final String unit = line(ImportField.unit);
    if (unit.isNotEmpty) {
      d.unit = ImportValues.unitFrom(unit);
      if (d.unit == null) d.warnings.add('Unit "$unit" not recognised');
    }

    final String low = line(ImportField.lowStock);
    if (low.isNotEmpty) {
      d.lowStock = ImportValues.parseWhole(cell(ImportField.lowStock));
      if (d.lowStock == null) {
        d.warnings.add('Low-stock level "$low" is not a whole number; '
            'using ${AppConstants.defaultLowStockThreshold}');
      }
    }

    d.purchase = _money(line(ImportField.purchaseRate),
        cell(ImportField.purchaseRate), 'Purchase rate', d);
    d.mrp = _money(line(ImportField.mrp), cell(ImportField.mrp), 'MRP', d);

    final Object? exp = cell(ImportField.expiryDate);
    final String expText = ImportValues.text(exp);
    if (expText.isEmpty) {
      d.errors.add('Expiry date is missing');
    } else {
      final CellDate? e = ImportValues.parseDate(exp, order: s.dateOrder);
      if (e == null) {
        d.errors.add('Expiry date "$expText" not understood '
            '(use e.g. 31/12/2027 or 12/27)');
      } else {
        d.expiry = ImportValues.expiryOf(e);
        if (d.expiry!.isBefore(today)) d.warnings.add('Already expired');
      }
    }

    final Object? mfg = cell(ImportField.mfgDate);
    final String mfgText = ImportValues.text(mfg);
    if (mfgText.isNotEmpty) {
      final CellDate? m = ImportValues.parseDate(mfg, order: s.dateOrder);
      if (m == null) {
        d.warnings.add('Mfg date "$mfgText" not understood; left blank');
      } else if (m.date.isAfter(today)) {
        d.warnings.add('Mfg date is in the future; left blank');
      } else if (d.expiry != null && !m.date.isBefore(d.expiry!)) {
        d.warnings.add('Mfg date is not before the expiry date; left blank');
      } else {
        d.mfg = m.date;
      }
    }

    d.notes = ImportValues.text(cell(ImportField.notes));
    if (d.notes.length > 2000) {
      d.notes = d.notes.substring(0, 2000);
      d.warnings.add('Notes shortened to 2000 characters');
    }
    return d;
  }

  static double? _money(String text, Object? v, String label, _Draft d) {
    if (text.isEmpty) return null;
    final double? n = ImportValues.parseMoney(v);
    if (n == null) d.warnings.add('$label "$text" is not a price; left blank');
    return n;
  }

  static Medicine _medicine(_Product p, _Draft d, int quantity, DateTime now) =>
      Medicine(
        id: _uuid.v4(),
        productId: p.existingId ?? '',
        name: p.name,
        brand: p.brand,
        category: p.category,
        batchNo: d.batchNo,
        barcode: p.barcode,
        quantity: quantity,
        unit: p.unit,
        lowStockThreshold: p.lowStock,
        purchasePrice: d.purchase ?? 0,
        sellingPrice: d.mrp ?? 0,
        mfgDate: d.mfg,
        expiryDate: d.expiry!,
        notes: p.notes,
        createdAt: now,
        updatedAt: now,
      );

  /// Medicines in stock by normalised name, with their batches.
  static Map<String, List<_Product>> _index(List<Medicine> inventory) {
    final Map<String, _Product> byId = <String, _Product>{};
    for (final Medicine m in inventory) {
      if (m.isDeleted) continue;
      final String id = m.productId.isEmpty ? m.id : m.productId;
      final _Product p = byId[id] ??= _Product.existing(id, m);
      p.batches[_batchKey(m.batchNo, m.expiryDate)] = _Batch.existing(m.id);
    }
    final Map<String, List<_Product>> out = <String, List<_Product>>{};
    for (final _Product p in byId.values) {
      (out[_norm(p.name)] ??= <_Product>[]).add(p);
    }
    return out;
  }

  /// The product a row belongs to among those with its name: the maker must
  /// match ([_maker]) unless one side has none, and the unit must match when
  /// [unit] is given. The closest maker wins.
  static _Product? _match(List<_Product>? candidates, String brand, String? unit) {
    if (candidates == null) return null;
    final String b = _maker(brand);
    _Product? best;
    int bestScore = -1;
    for (final _Product p in candidates) {
      final String pb = _maker(p.brand);
      final int score;
      if (b.isEmpty || pb.isEmpty) {
        score = b == pb ? 2 : 0;
      } else if (b == pb) {
        score = 2;
      } else if (b.length >= 4 && pb.length >= 4 &&
          (b.startsWith(pb) || pb.startsWith(b))) {
        score = 1; // "GLEN" for Glenmark
      } else {
        continue; // another maker's medicine of the same name
      }
      if (unit != null && p.unit.toLowerCase() != unit.toLowerCase()) continue;
      if (score > bestScore) {
        best = p;
        bestScore = score;
      }
    }
    return best;
  }

  /// Words dropped when comparing makers.
  static const Set<String> _makerNoise = <String>{
    'ltd', 'limited', 'pvt', 'private', 'p', 'inc', 'corp', 'corporation',
    'co', 'company', 'the', 'and', 'pharma', 'pharmaceutical',
    'pharmaceuticals', 'labs', 'lab', 'laboratories', 'laboratory',
    'healthcare', 'health', 'care', 'india', 'industries', 'lifesciences',
    'life', 'sciences', 'remedies', 'formulations', 'llp', 'intl',
    'international',
  };

  /// A maker's name for comparison: "MICRO LABS LTD." and "Micro Labs" are
  /// both "micro".
  static String _maker(String brand) {
    final List<String> words = brand
        .toLowerCase()
        .split(_notAlnum)
        .where((String w) => w.isNotEmpty)
        .toList();
    final List<String> kept =
        words.where((String w) => !_makerNoise.contains(w)).toList();
    return (kept.isEmpty ? words : kept).join(' ');
  }

  /// Same batch: same batch number (ignoring case), or with no batch number
  /// the same expiry date.
  static String _batchKey(String batchNo, DateTime expiry) {
    final String b = batchNo.trim().toLowerCase();
    return b.isNotEmpty
        ? 'b:$b'
        : 'e:${expiry.year}-${expiry.month}-${expiry.day}';
  }

  /// Same as DatabaseHelper.normName.
  static String _norm(String name) =>
      name.trim().toLowerCase().replaceAll(_space, ' ');

  static bool _sameAsHeader(List<Object?> cells, List<Object?> header) {
    int named = 0;
    int same = 0;
    for (int i = 0; i < header.length; i++) {
      final String h = ImportValues.text(header[i]).toLowerCase();
      if (h.isEmpty) continue;
      named++;
      if (i < cells.length && ImportValues.text(cells[i]).toLowerCase() == h) {
        same++;
      }
    }
    return named >= 2 && same >= (named * 0.6).ceil();
  }
}

class _Draft {
  String name = '';
  String brand = '';
  String category = 'Uncategorised';
  String batchNo = '';
  String barcode = '';
  int? quantity;
  String? unit;
  int? lowStock;
  double? purchase;
  double? mrp;
  DateTime? mfg;
  DateTime? expiry;
  String notes = '';
  final List<String> errors = <String>[];
  final List<String> warnings = <String>[];

  ImportRow toRow(int rowNumber, RowAction action,
          {String? unit, String? detail, List<String>? errors}) =>
      ImportRow(
        rowNumber: rowNumber,
        name: name,
        brand: brand,
        batchNo: batchNo,
        quantity: quantity,
        unit: unit ?? this.unit ?? '',
        expiry: expiry,
        action: action,
        detail: detail,
        errors: errors ?? List<String>.unmodifiable(this.errors),
        warnings: List<String>.unmodifiable(warnings),
      );
}

/// A medicine in stock, or a new one this import creates.
class _Product {
  _Product.existing(String this.existingId, Medicine m)
      : key = 'p:$existingId',
        name = m.name,
        brand = m.brand,
        unit = m.unit,
        row = null,
        blocked = false,
        category = m.category,
        barcode = m.barcode,
        notes = m.notes,
        lowStock = m.lowStockThreshold;

  _Product.planned(this.key, this.name, this.brand, this.unit, int this.row,
      {required this.blocked})
      : existingId = null;

  final String? existingId;
  final String key;
  final String name;
  final String brand;
  final String unit;

  /// The row that creates a new medicine.
  final int? row;

  /// A new medicine the free plan has no room for.
  final bool blocked;

  String category = 'Uncategorised';
  String barcode = '';
  String notes = '';
  int lowStock = AppConstants.defaultLowStockThreshold;
  bool _lowStockSet = false;

  /// Batch key → batch.
  final Map<String, _Batch> batches = <String, _Batch>{};

  /// A new medicine takes each detail from the first of its rows that has it.
  void absorb(_Draft d) {
    if (existingId != null) return;
    if (category == 'Uncategorised') category = d.category;
    if (barcode.isEmpty) barcode = d.barcode;
    if (notes.isEmpty) notes = d.notes;
    if (!_lowStockSet && d.lowStock != null) {
      lowStock = d.lowStock!;
      _lowStockSet = true;
    }
  }
}

class _Batch {
  _Batch.existing(String this.existingId)
      : row = null,
        draft = null,
        quantity = 0;

  _Batch.planned(int this.row, _Draft this.draft, this.quantity)
      : existingId = null;

  final String? existingId;
  final int? row;
  final _Draft? draft;
  int quantity;
}
