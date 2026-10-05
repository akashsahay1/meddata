import '../../core/constants.dart';
import 'sheet_table.dart';

/// Day first (31/12/2027, as written in India) or month first (12/31/2027).
enum DateOrder { dayFirst, monthFirst }

/// A quantity cell read as a whole number of units, or why it can't be.
class QuantityValue {
  final int? value;
  final String? error;

  /// Set when the value was read in a way worth telling the user about.
  final String? note;

  const QuantityValue.ok(int this.value, {this.note}) : error = null;
  const QuantityValue.bad(String this.error)
      : value = null,
        note = null;
}

/// Reads spreadsheet cells as the values a medicine row needs. Lenient about
/// the formats shops, billing software and distributors use.
class ImportValues {
  ImportValues._();

  /// A cell's text as the user sees it in the sheet.
  static String text(Object? v) {
    if (v == null) return '';
    if (v is String) return v.trim();
    if (v is int) return v.toString();
    if (v is double) {
      if (v.isFinite && v == v.truncateToDouble() && v.abs() < 1e15) {
        return v.toInt().toString();
      }
      return v.toString();
    }
    if (v is CellDate) {
      final DateTime d = v.date;
      final String mm = d.month.toString().padLeft(2, '0');
      return v.hasDay
          ? '${d.day.toString().padLeft(2, '0')}/$mm/${d.year}'
          : '$mm/${d.year}';
    }
    if (v is bool) return v ? 'TRUE' : 'FALSE';
    return v.toString().trim();
  }

  // ---- dates ---------------------------------------------------------------

  static final RegExp _ymd =
      RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?:[ t].*)?$');
  static final RegExp _ym = RegExp(r'^(\d{4})[-/.](\d{1,2})$');
  static final RegExp _dmy =
      RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4}|\d{2})(?:\s.*)?$');
  static final RegExp _my = RegExp(r'^(\d{1,2})\s*[-/.]\s*(\d{4}|\d{2})$');
  static final RegExp _dMonY = RegExp(
      r"^(\d{1,2})(?:st|nd|rd|th)?[-/ .,']*([a-z]{3,9})[-/ .,']*(\d{4}|\d{2})$");
  static final RegExp _monDY = RegExp(
      r"^([a-z]{3,9})[-/ .,']*(\d{1,2})(?:st|nd|rd|th)?[-/ .,']+(\d{4})$");
  static final RegExp _monY = RegExp(r"^([a-z]{3,9})[-/ .,']*(\d{4}|\d{2})$");
  static final RegExp _compact8 = RegExp(r'^\d{8}$');
  static final RegExp _serialText = RegExp(r'^\d{5}(\.\d+)?$');

  static const List<String> _monthNames = <String>[
    'january', 'february', 'march', 'april', 'may', 'june', 'july',
    'august', 'september', 'october', 'november', 'december',
  ];

  /// A date from a cell: a date cell, an Excel serial number, or text such
  /// as 31/12/2027, 31-12-27, 2027-12-31, 31-Dec-2027, 12/27, Dec-27 or
  /// December 2027. Two-digit years are 20xx. [order] settles 01/02/2027.
  static CellDate? parseDate(Object? v,
      {DateOrder order = DateOrder.dayFirst}) {
    if (v == null || v is bool) return null;
    if (v is CellDate) return v;
    if (v is DateTime) return CellDate(v);
    if (v is num) return _serial(v.toDouble());
    final String s = v.toString().trim().toLowerCase();
    if (s.isEmpty) return null;

    RegExpMatch? m = _ymd.firstMatch(s);
    if (m != null) return _make(_int(m[1]), _int(m[2]), _int(m[3]));
    m = _ym.firstMatch(s);
    if (m != null) return _make(_int(m[1]), _int(m[2]), null);
    m = _dmy.firstMatch(s);
    if (m != null) {
      final int a = _int(m[1]);
      final int b = _int(m[2]);
      int day = order == DateOrder.dayFirst ? a : b;
      int month = order == DateOrder.dayFirst ? b : a;
      if (month > 12 && day <= 12) {
        final int t = day;
        day = month;
        month = t;
      }
      return _make(_year(m[3]!), month, day);
    }
    m = _my.firstMatch(s);
    if (m != null) return _make(_year(m[2]!), _int(m[1]), null);
    m = _dMonY.firstMatch(s);
    if (m != null) {
      final int? month = _month(m[2]!);
      return month == null ? null : _make(_year(m[3]!), month, _int(m[1]));
    }
    m = _monDY.firstMatch(s);
    if (m != null) {
      final int? month = _month(m[1]!);
      return month == null ? null : _make(_year(m[3]!), month, _int(m[2]));
    }
    m = _monY.firstMatch(s);
    if (m != null) {
      final int? month = _month(m[1]!);
      return month == null ? null : _make(_year(m[2]!), month, null);
    }
    if (_compact8.hasMatch(s)) {
      // 20271231, or 31122027 / 12312027.
      final CellDate? ymd = _make(_int(s.substring(0, 4)),
          _int(s.substring(4, 6)), _int(s.substring(6, 8)));
      if (ymd != null) return ymd;
      final int a = _int(s.substring(0, 2));
      final int b = _int(s.substring(2, 4));
      final int y = _int(s.substring(4));
      return order == DateOrder.dayFirst
          ? (_make(y, b, a) ?? _make(y, a, b))
          : (_make(y, a, b) ?? _make(y, b, a));
    }
    if (_serialText.hasMatch(s)) return _serial(double.parse(s));
    return null;
  }

  /// The expiry a date stands for: a month and year means the end of that
  /// month (what "EXP 12/2027" on a strip means).
  static DateTime expiryOf(CellDate d) =>
      d.hasDay ? d.date : DateTime(d.date.year, d.date.month + 1, 0);

  /// Month first only when the file's dates show it (e.g. 12/31/2027) and
  /// nothing shows day first; otherwise day first.
  static DateOrder detectDateOrder(Iterable<Object?> values) {
    int dayFirst = 0;
    int monthFirst = 0;
    for (final Object? v in values) {
      if (v is! String) continue;
      final RegExpMatch? m = _dmy.firstMatch(v.trim().toLowerCase());
      if (m == null) continue;
      final int a = _int(m[1]);
      final int b = _int(m[2]);
      if (a > 12 && b <= 12) dayFirst++;
      if (b > 12 && a <= 12) monthFirst++;
    }
    return monthFirst > 0 && dayFirst == 0
        ? DateOrder.monthFirst
        : DateOrder.dayFirst;
  }

  static int _int(String? s) => int.parse(s!);

  static int _year(String s) => s.length == 2 ? 2000 + int.parse(s) : int.parse(s);

  static int? _month(String word) {
    if (word.length < 3) return null;
    for (int i = 0; i < _monthNames.length; i++) {
      if (_monthNames[i].startsWith(word)) return i + 1;
    }
    return null;
  }

  /// A valid date from 2000 to 2100 (the range the app's date pickers use).
  static CellDate? _make(int y, int m, int? d) {
    if (y < 2000 || y > 2100 || m < 1 || m > 12) return null;
    if (d == null) return CellDate(DateTime(y, m), hasDay: false);
    final DateTime date = DateTime(y, m, d);
    if (d < 1 || date.month != m) return null; // e.g. 31/02
    return CellDate(date);
  }

  /// Excel's day number (1 = 1 Jan 1900) — what a date cell holds when it
  /// isn't formatted as a date.
  static CellDate? _serial(double n) {
    // 36526 = 1 Jan 2000, 73051 = 1 Jan 2100.
    if (!n.isFinite || n < 36526 || n >= 73051) return null;
    final DateTime d =
        DateTime.utc(1899, 12, 30).add(Duration(days: n.floor()));
    return CellDate(DateTime(d.year, d.month, d.day));
  }

  // ---- numbers -------------------------------------------------------------

  static final RegExp _plainNumber = RegExp(r'^[+-]?(\d+\.?\d*|\.\d+)$');
  static final RegExp _currency = RegExp(r'^(₹|rs\.?|inr|\$)\s*');
  static final RegExp _slashDash = RegExp(r'\s*/-$'); // "45/-"
  static final RegExp _space = RegExp(r'\s+');
  static final RegExp _decimalComma = RegExp(r'^[+-]?\d+,\d{1,2}$');

  /// A number, allowing "₹1,234.50", "Rs. 45", "45/-", "1,00,000" and a
  /// decimal comma ("12,50"). Null when the cell isn't a number.
  static double? parseNumber(Object? v) {
    if (v == null || v is bool || v is CellDate) return null;
    if (v is num) return v.isFinite ? v.toDouble() : null;
    String s = v.toString().trim().toLowerCase();
    if (s.isEmpty) return null;
    s = s
        .replaceFirst(_currency, '')
        .replaceFirst(_slashDash, '')
        .replaceAll(_space, '');
    s = _decimalComma.hasMatch(s)
        ? s.replaceAll(',', '.')
        : s.replaceAll(',', '');
    if (!_plainNumber.hasMatch(s)) return null;
    return double.tryParse(s);
  }

  /// A price in rupees, rounded to paise; null when not a number or
  /// negative.
  static double? parseMoney(Object? v) {
    final double? n = parseNumber(v);
    if (n == null || n < 0 || n > 10000000) return null;
    return (n * 100).round() / 100;
  }

  /// A whole number ≥ 0 (e.g. a low-stock level); null otherwise.
  static int? parseWhole(Object? v) {
    final double? n = parseNumber(v);
    if (n == null || n < 0 || n != n.roundToDouble() || n > 10000000) {
      return null;
    }
    return n.round();
  }

  static final RegExp _qtyPlus = RegExp(
      r'^(\d[\d,]*(?:\.\d+)?)\s*\+\s*(\d[\d,]*(?:\.\d+)?)$');
  static final RegExp _qtyWithUnit =
      RegExp(r"^([+-]?\d[\d,]*(?:\.\d+)?)\s*([a-z'][a-z'.]*)?$");

  /// Stock in units: "20", "20.0", "1,200", "20 TAB", or "10+2" (bought +
  /// free, counted as 12).
  static QuantityValue parseQuantity(Object? v) {
    final String raw = text(v);
    if (raw.isEmpty) return const QuantityValue.bad('Quantity is missing');
    if (v is CellDate || v is bool) {
      return QuantityValue.bad('Quantity "$raw" is not a number');
    }
    if (v is num) return _wholeQuantity(v.toDouble(), raw);
    final String s = raw.toLowerCase().replaceAll(_space, ' ');
    final RegExpMatch? plus = _qtyPlus.firstMatch(s);
    if (plus != null) {
      final double? a = parseNumber(plus[1]);
      final double? b = parseNumber(plus[2]);
      if (a != null && b != null) {
        final QuantityValue q = _wholeQuantity(a + b, raw);
        return q.value == null
            ? q
            : QuantityValue.ok(q.value!,
                note: 'Quantity "$raw" counted as ${q.value}');
      }
    }
    final RegExpMatch? m = _qtyWithUnit.firstMatch(s);
    if (m != null) {
      final double? n = parseNumber(m[1]);
      if (n != null) return _wholeQuantity(n, raw);
    }
    return QuantityValue.bad('Quantity "$raw" is not a number');
  }

  static QuantityValue _wholeQuantity(double n, String raw) {
    if (n < 0) return QuantityValue.bad('Quantity "$raw" is negative');
    if (n != n.roundToDouble()) {
      return QuantityValue.bad('Quantity "$raw" is not a whole number');
    }
    if (n > 10000000) return QuantityValue.bad('Quantity "$raw" is too large');
    return QuantityValue.ok(n.round());
  }

  // ---- units and categories -----------------------------------------------

  /// Words that settle the unit, most specific first.
  static const List<(String, Set<String>)> _unitWords = <(String, Set<String>)>[
    ('Injections', <String>{
      'inj', 'injection', 'injections', 'vial', 'vials', 'amp', 'amps',
      'ampoule', 'ampoules', 'ampule',
    }),
    ('Sachets', <String>{'sachet', 'sachets', 'sach', 'sac', 'pouch', 'satchet'}),
    ('Tubes', <String>{'tube', 'tubes', 'cream', 'crm', 'gel', 'oint', 'ointment'}),
    ('Bottles', <String>{
      'bottle', 'bottles', 'btl', 'bott', 'syp', 'syrup', 'susp',
      'suspension', 'liquid', 'liq', 'drop', 'drops', 'solution', 'sol',
      'lotion', 'spray', 'tonic', 'jar',
    }),
    ('Strips', <String>{'strip', 'strips', 'stp', 'str'}),
    ('Boxes', <String>{'box', 'boxes', 'bx', 'carton', 'ctn'}),
    ('Capsules', <String>{'cap', 'caps', 'capsule', 'capsules'}),
    ('Tablets', <String>{'tab', 'tabs', 'tablet', 'tablets', 'tb'}),
    ('Pieces', <String>{
      'pc', 'pcs', 'piece', 'pieces', 'nos', 'no', 'each', 'ea', 'unit',
      'units', 'kit', 'pair', 'roll', 'pack', 'packs', 'pkt', 'packet',
      'inhaler', 'respule', 'respules',
    }),
  ];

  static final RegExp _digit = RegExp(r'\d');
  static final RegExp _number = RegExp(r'\d+');
  static final RegExp _letters = RegExp(r'[a-z]+');
  static final RegExp _packOf = RegExp(r'^\d+\s*[x*×]\s*\d+'); // 1x10
  static final RegExp _packS = RegExp(r"^\d+\s*'?\s*s$"); // 10's

  /// The app's unit for a unit or pack column value: "TAB" → Tablets,
  /// "10's" or "1x10" (a strip of 10; stock is counted in strips) → Strips,
  /// "100 ML" (a bottle) → Bottles, "15 GM" → Tubes, "INJ" → Injections.
  /// Null when it isn't recognised.
  static String? unitFrom(String raw) {
    final String s = raw.trim().toLowerCase();
    if (s.isEmpty) return null;
    for (final String u in AppConstants.units) {
      if (u.toLowerCase() == s) return u;
    }
    final bool hasNumber = _digit.hasMatch(s);
    final List<String> words = _letters
        .allMatches(s)
        .map((RegExpMatch m) => m[0]!)
        .toList();
    String? byWord(int from, int to) {
      for (int i = from; i < to; i++) {
        final (String unit, Set<String> keys) = _unitWords[i];
        if (words.any(keys.contains)) return unit;
      }
      return null;
    }

    // Injections, sachets, tubes and bottles win over a pack size.
    final String? form = byWord(0, 4);
    if (form != null) return form;
    if (_packOf.hasMatch(s) || _packS.hasMatch(s)) {
      return 'Strips';
    }
    final String? other = byWord(4, _unitWords.length);
    if (other == 'Tablets' || other == 'Capsules') {
      // "10 TAB" is a strip of 10.
      return hasNumber ? 'Strips' : other;
    }
    if (other != null) return other;
    if (words.length == 1) {
      final String w = words.single;
      if (w == 'ml' || w == 'mls') return hasNumber ? 'Bottles' : 'ML';
      if (hasNumber && <String>{'l', 'ltr', 'litre', 'liter'}.contains(w)) {
        return 'Bottles';
      }
      if (hasNumber && <String>{'g', 'gm', 'gms', 'gram', 'grams'}.contains(w)) {
        final int grams =
            int.tryParse(_number.firstMatch(s)![0]!) ?? 0;
        return grams <= 50 ? 'Tubes' : 'Boxes';
      }
    }
    return null;
  }

  /// One of the app's preset categories when the text names it ("antibiotics"
  /// → Antibiotic, "analgesic" → Pain Relief / Analgesic); otherwise the text
  /// as given. Blank → Uncategorised.
  static String categoryFrom(String raw) {
    final String s = raw.trim().replaceAll(_space, ' ');
    if (s.isEmpty) return 'Uncategorised';
    final String l = s.toLowerCase();
    for (final (String c, List<String> names) in _categoryNames) {
      for (final String n in names) {
        if (n == l || '${n}s' == l || n == '${l}s') return c;
      }
    }
    return s.length > 255 ? s.substring(0, 255) : s;
  }

  /// Each preset category with the names it goes by: "Pain Relief /
  /// Analgesic" → pain relief / analgesic, pain relief, analgesic.
  static final List<(String, List<String>)> _categoryNames =
      <(String, List<String>)>[
    for (final String c in AppConstants.categories)
      (c, <String>[
        c.toLowerCase(),
        ...c
            .toLowerCase()
            .split(RegExp(r'\s*[/()]\s*'))
            .where((String p) => p.isNotEmpty),
      ]),
  ];
}
