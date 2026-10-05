import 'dart:math' as math;

import 'import_values.dart';
import 'sheet_table.dart';

/// The details a stock import fills in. Each is read from at most one column.
enum ImportField {
  name('Medicine name', required: true),
  manufacturer('Manufacturer / brand'),
  category('Category'),
  batchNo('Batch no.'),
  barcode('Barcode'),
  quantity('Quantity', required: true),
  unit('Unit / pack'),
  lowStock('Low-stock alert at'),
  purchaseRate('Purchase rate'),
  mrp('MRP / selling price'),
  mfgDate('Mfg date'),
  expiryDate('Expiry date', required: true),
  notes('Notes');

  const ImportField(this.label, {this.required = false});
  final String label;
  final bool required;
}

/// Finds the header row of a sheet and guesses which column holds which
/// [ImportField] from the column names (English, and what Indian billing
/// software and distributors use: "Item Name", "Batch", "Exp", "MRP",
/// "Qty", "Pack", "Rate", "Mfr"...), checked against the column's values.
class ColumnGuesser {
  ColumnGuesser._();

  /// Column names per field, best first.
  static const Map<ImportField, List<String>> synonyms = <ImportField, List<String>>{
    ImportField.name: <String>[
      'item name', 'product name', 'medicine name', 'name', 'item',
      'product', 'medicine', 'drug name', 'drug', 'item description',
      'product description', 'description', 'particulars', 'item desc',
      'name of item', 'name of product', 'name of medicine', 'sku name',
    ],
    ImportField.manufacturer: <String>[
      'manufacturer', 'manufacturer name', 'mfr', 'mfr name', 'mfg',
      'mfg name', 'company', 'company name', 'comp', 'co', 'brand',
      'brand name', 'make', 'marketed by', 'mkt by', 'mfd by', 'mfg by',
      'manufactured by', 'mfg co', 'marketer', 'mkt', 'mfg mkt', 'mfr mkt',
    ],
    ImportField.category: <String>[
      'category', 'cat', 'group', 'item group', 'product group',
      'group name', 'category name', 'type', 'item type', 'product type',
      'class', 'therapeutic class', 'therapeutic category', 'segment',
      'department', 'dept',
    ],
    ImportField.batchNo: <String>[
      'batch no', 'batch', 'batch number', 'b no', 'bno', 'batch code',
      'lot', 'lot no', 'lot number', 'btch', 'batch id', 'bt no',
    ],
    ImportField.barcode: <String>[
      'barcode', 'bar code', 'ean', 'ean code', 'ean no', 'upc', 'gtin',
      'barcode no', 'barcode number',
    ],
    ImportField.quantity: <String>[
      'qty', 'quantity', 'closing stock', 'closing qty', 'stock',
      'stock qty', 'cl stock', 'cl qty', 'closing', 'closing balance',
      'balance', 'balance qty', 'bal qty', 'available', 'available qty',
      'avl qty', 'avail qty', 'current stock', 'stock in hand',
      'qty in hand', 'on hand', 'qoh', 'physical stock', 'total qty',
      'units', 'nos', 'pcs', 'no of units', 'billed qty', 'bill qty',
      'purchase qty', 'pur qty', 'recd qty', 'received qty',
      'opening stock', 'opening qty',
    ],
    ImportField.unit: <String>[
      'unit', 'uom', 'unit of measure', 'pack', 'packing', 'pack size',
      'pack type', 'pkg', 'packaging', 'form', 'dosage form', 'unit type',
      'pk',
    ],
    ImportField.lowStock: <String>[
      'low stock', 'low stock at', 'low stock level', 'low stock alert',
      'reorder level', 'reorder', 're order level', 'reorder point',
      'reorder qty', 'rol', 'min', 'min qty', 'min stock', 'minimum',
      'minimum stock', 'minimum qty', 'min level', 'safety stock',
      'alert qty', 'alert level', 'threshold',
    ],
    ImportField.purchaseRate: <String>[
      'purchase rate', 'purchase price', 'pur rate', 'pur price', 'p rate',
      'rate', 'ptr', 'cost', 'cost price', 'cp', 'net rate',
      'landing cost', 'landing rate', 'landing price', 'buy price',
      'buying price', 'trade price', 'tp', 'pts', 'unit cost', 'purchase',
      'pur',
    ],
    ImportField.mrp: <String>[
      'mrp', 'mrp per unit', 'selling price', 'sale price', 'sales price',
      'sale rate', 'selling rate', 's rate', 'sp', 'retail price', 'price',
      'unit price', 'max retail price', 'maximum retail price', 'new mrp',
    ],
    ImportField.mfgDate: <String>[
      'mfg date', 'mfg', 'mfg dt', 'mfd', 'mfd date', 'manufacturing date',
      'manufacture date', 'date of manufacture', 'manufactured on',
      'mfg month', 'dom', 'production date', 'prod date', 'mfg on',
    ],
    ImportField.expiryDate: <String>[
      'expiry date', 'expiry', 'exp', 'exp date', 'exp dt', 'expiry dt',
      'expiration', 'expiration date', 'expires', 'expires on', 'exp on',
      'exp month', 'expiry month', 'date of expiry', 'doe', 'use before',
      'use by', 'best before', 'valid till', 'valid upto',
    ],
    ImportField.notes: <String>[
      'notes', 'note', 'remarks', 'remark', 'comments', 'comment',
      'composition', 'salt', 'generic name', 'generic', 'content',
      'contents', 'molecule',
    ],
  };

  /// Words that rule a field out for a column whose name only partly
  /// matches (e.g. "Stock Value" is not a quantity, "Company Name" not the
  /// medicine name).
  static const Map<ImportField, Set<String>> _notWords = <ImportField, Set<String>>{
    ImportField.name: <String>{
      'company', 'mfr', 'manufacturer', 'mfg', 'supplier', 'party',
      'customer', 'vendor', 'distributor', 'generic', 'salt', 'group',
      'category', 'brand', 'batch', 'code', 'no', 'number', 'id', 'sr', 'sl',
      'serial', 'shop', 'store', 'type',
    },
    ImportField.manufacturer: <String>{'date', 'dt', 'on', 'month'},
    ImportField.category: <String>{'tax', 'gst', 'payment', 'bill', 'party'},
    ImportField.batchNo: <String>{
      'date', 'dt', 'qty', 'quantity', 'exp', 'expiry', 'mfg', 'mrp',
      'rate', 'price',
    },
    ImportField.quantity: <String>{
      'free', 'sch', 'scheme', 'bonus', 'min', 'max', 'minimum', 'maximum',
      'reorder', 'rol', 'value', 'val', 'amount', 'amt', 'rate', 'price',
      'mrp', 'damaged', 'damage', 'short', 'return', 'returned', 'sale',
      'sales', 'sold', 'level', 'alert', 'safety',
    },
    ImportField.unit: <String>{
      'price', 'rate', 'cost', 'mrp', 'qty', 'quantity', 'value', 'amount',
    },
    ImportField.purchaseRate: <String>{
      'qty', 'quantity', 'value', 'amount', 'amt', 'total', 'disc',
      'discount', 'gst', 'tax', 'margin', 'percent', 'mrp', 'sale',
      'selling', 'sell', 'old',
    },
    ImportField.mrp: <String>{
      'qty', 'quantity', 'value', 'amount', 'amt', 'total', 'disc',
      'discount', 'gst', 'tax', 'margin', 'percent', 'purchase', 'pur',
      'cost', 'ptr', 'old',
    },
  };

  /// Header rows are looked for in the first rows only.
  static const int _headerSearchRows = 30;

  /// The row (index) holding the column names, or -1 when the sheet seems
  /// to start straight with data.
  static int guessHeaderRow(SheetTable sheet) {
    int best = -1;
    int bestScore = 0;
    final int limit = math.min(sheet.rows.length, _headerSearchRows);
    for (int r = 0; r < limit; r++) {
      final Set<ImportField> seen = <ImportField>{};
      for (final Object? cell in sheet.rows[r]) {
        if (cell is! String) continue;
        final ImportField? f = _bestField(cell);
        if (f != null) seen.add(f);
      }
      if (seen.length > bestScore) {
        bestScore = seen.length;
        best = r;
      }
    }
    if (bestScore >= 2) return best;
    final int first = sheet.rows.indexWhere(SheetTable.rowHasData);
    if (first < 0) return -1;
    // Nothing recognisable: the first filled row, unless it is clearly data.
    final int dataCells = sheet.rows[first]
        .where((Object? v) =>
            v is num || v is CellDate || ImportValues.parseDate(v) != null)
        .length;
    return dataCells >= 2 ? -1 : first;
  }

  /// Field → column index guesses for the sheet with its column names in
  /// [headerRow]. Each column is used once; the best matches win.
  static Map<ImportField, int> guessColumns(SheetTable sheet, int headerRow) {
    if (headerRow < 0 || headerRow >= sheet.rows.length) {
      return <ImportField, int>{};
    }
    final List<Object?> header = sheet.rows[headerRow];
    final List<(int, ImportField, int)> candidates = <(int, ImportField, int)>[];
    for (int c = 0; c < header.length; c++) {
      final String name = ImportValues.text(header[c]);
      if (name.isEmpty) continue;
      final List<Object?> samples = sampleValues(sheet, headerRow, c);
      for (final ImportField f in ImportField.values) {
        final int s = headerScore(f, name);
        if (s <= 0) continue;
        final int score = s - _contentPenalty(f, samples);
        if (score >= 50) candidates.add((score, f, c));
      }
    }
    candidates.sort(((int, ImportField, int) a, (int, ImportField, int) b) {
      if (a.$1 != b.$1) return b.$1.compareTo(a.$1);
      if (a.$3 != b.$3) return a.$3.compareTo(b.$3);
      return a.$2.index.compareTo(b.$2.index);
    });
    final Map<ImportField, int> out = <ImportField, int>{};
    final Set<int> used = <int>{};
    for (final (int _, ImportField f, int c) in candidates) {
      if (out.containsKey(f) || used.contains(c)) continue;
      out[f] = c;
      used.add(c);
    }
    return out;
  }

  /// How well a column name fits a field: 200 minus the synonym's rank for
  /// an exact match (ignoring case, spaces and punctuation: "Exp.Date",
  /// "EXP DATE", "ExpDate"), 50+ when the name contains a synonym's words
  /// ("Closing Stock Qty"), else 0.
  static int headerScore(ImportField f, String header) {
    final String compact = _compact(header);
    if (compact.isEmpty) return 0;
    final List<String> words = _words(header);
    final List<String> list = synonyms[f]!;
    int best = 0;
    for (int i = 0; i < list.length; i++) {
      final String syn = list[i];
      if (_compact(syn) == compact) return 200 - i;
      final List<String> sw = syn.split(' ');
      if (_containsRun(words, sw)) {
        best = math.max(best, math.min(149, 50 + 2 * _compact(syn).length));
      }
    }
    if (best > 0 && words.any((String w) => _notWords[f]?.contains(w) ?? false)) {
      return 0;
    }
    return best;
  }

  /// Up to 30 non-blank values under [headerRow] in column [col].
  static List<Object?> sampleValues(SheetTable sheet, int headerRow, int col,
      {int max = 30}) {
    final List<Object?> out = <Object?>[];
    for (int r = headerRow + 1; r < sheet.rows.length && out.length < max; r++) {
      final Object? v = sheet.cell(r, col);
      if (v == null || (v is String && v.trim().isEmpty)) continue;
      out.add(v);
    }
    return out;
  }

  /// Spreadsheet column letters: 0 → A, 26 → AA.
  static String columnLetter(int index) {
    String s = '';
    int n = index + 1;
    while (n > 0) {
      final int r = (n - 1) % 26;
      s = String.fromCharCode(65 + r) + s;
      n = (n - 1) ~/ 26;
    }
    return s;
  }

  static ImportField? _bestField(String header) {
    ImportField? best;
    int bestScore = 49;
    for (final ImportField f in ImportField.values) {
      final int s = headerScore(f, header);
      if (s > bestScore) {
        bestScore = s;
        best = f;
      }
    }
    return best;
  }

  /// Lowers a field's score when the column's values don't fit it, so e.g. a
  /// "Mfg" column of company names becomes the manufacturer, not a date.
  static int _contentPenalty(ImportField f, List<Object?> samples) {
    if (samples.isEmpty) return 0;
    double share(bool Function(Object?) test) =>
        samples.where(test).length / samples.length;
    int penalty(double fit) => fit < 0.2 ? 150 : (fit < 0.5 ? 60 : 0);
    switch (f) {
      case ImportField.mfgDate:
      case ImportField.expiryDate:
        return penalty(share((Object? v) => ImportValues.parseDate(v) != null));
      case ImportField.quantity:
        return penalty(
            share((Object? v) => ImportValues.parseQuantity(v).value != null));
      case ImportField.lowStock:
      case ImportField.purchaseRate:
      case ImportField.mrp:
        return penalty(share((Object? v) => ImportValues.parseNumber(v) != null));
      case ImportField.name:
      case ImportField.manufacturer:
      case ImportField.category:
      case ImportField.unit:
        final double notText = share((Object? v) =>
            ImportValues.parseNumber(v) != null ||
            ImportValues.parseDate(v) != null);
        return notText >= 0.8 ? 150 : (notText >= 0.5 ? 60 : 0);
      case ImportField.batchNo:
      case ImportField.barcode:
      case ImportField.notes:
        return 0;
    }
  }

  static final RegExp _notAlnum = RegExp(r'[^a-z0-9]+');
  static final RegExp _letter = RegExp(r'[a-z]');

  static String _compact(String s) =>
      s.toLowerCase().replaceAll(_notAlnum, '');

  /// Lower-case words; runs of single letters are joined ("M.R.P." → mrp).
  static List<String> _words(String s) {
    final List<String> raw = s
        .toLowerCase()
        .split(_notAlnum)
        .where((String w) => w.isNotEmpty)
        .toList();
    final List<String> out = <String>[];
    String run = '';
    for (final String w in raw) {
      if (w.length == 1 && _letter.hasMatch(w)) {
        run += w;
        continue;
      }
      if (run.isNotEmpty) out.add(run);
      run = '';
      out.add(w);
    }
    if (run.isNotEmpty) out.add(run);
    return out;
  }

  static bool _containsRun(List<String> words, List<String> run) {
    if (run.isEmpty || run.length > words.length) return false;
    for (int i = 0; i + run.length <= words.length; i++) {
      bool ok = true;
      for (int j = 0; j < run.length; j++) {
        if (words[i + j] != run[j]) {
          ok = false;
          break;
        }
      }
      if (ok) return true;
    }
    return false;
  }
}
