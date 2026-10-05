import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml_events.dart';

import 'sheet_table.dart';

/// Reads the visible sheets of an Excel workbook (.xlsx: a zip of XML parts).
///
/// Only what an import needs: each cell's value, with shared and inline
/// strings resolved, date-formatted numbers as [CellDate]s (month-and-year
/// formats such as "mmm-yy" keep that), and formulas as their last
/// calculated value. Pure Dart, so it runs the same on phones and Windows.
class XlsxReader {
  XlsxReader._();

  /// Rows after this are ignored (a guard against sheets whose formatting
  /// runs to Excel's last row).
  static const int maxRows = 100000;
  static const int maxColumns = 500;

  static const String _notWorkbook =
      'This file is not an Excel workbook (.xlsx).';

  static List<SheetTable> read(Uint8List bytes) {
    final Archive zip;
    try {
      zip = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const ImportFileException(
          'This Excel file could not be opened. It may be damaged.');
    }
    try {
      return _read(zip);
    } on ImportFileException {
      rethrow;
    } catch (_) {
      throw const ImportFileException(
          'This Excel file could not be read. It may be damaged.');
    }
  }

  static List<SheetTable> _read(Archive zip) {
    final String workbookPath = _officeDocument(zip);
    final String? workbook = _text(zip, workbookPath);
    if (workbook == null) {
      if (zip.findFile('content.xml') != null) {
        throw const ImportFileException(
            'OpenDocument (.ods) files are not supported. Save the file as '
            'Excel (.xlsx) or CSV and import that.');
      }
      throw const ImportFileException(_notWorkbook);
    }
    final String dir = workbookPath.contains('/')
        ? workbookPath.substring(0, workbookPath.lastIndexOf('/'))
        : '';
    final String file = workbookPath.substring(workbookPath.lastIndexOf('/') + 1);
    final Map<String, _Rel> rels =
        _relationships(_text(zip, _join(dir, '_rels/$file.rels')));

    String partOfType(String type, String fallback) {
      for (final _Rel r in rels.values) {
        if (r.type.endsWith('/$type')) return _resolve(dir, r.target);
      }
      return _join(dir, fallback);
    }

    final List<String> shared =
        _sharedStrings(_text(zip, partOfType('sharedStrings', 'sharedStrings.xml')));
    final List<_DateKind> styles =
        _styles(_text(zip, partOfType('styles', 'styles.xml')));

    bool date1904 = false;
    final List<(String, String?, bool)> sheets = <(String, String?, bool)>[];
    for (final XmlEvent e in parseEvents(workbook)) {
      if (e is! XmlStartElementEvent) continue;
      if (e.localName == 'workbookPr') {
        final String v = (_attr(e, 'date1904') ?? '').toLowerCase();
        date1904 = v == '1' || v == 'true';
      } else if (e.localName == 'sheet') {
        final String state = _attr(e, 'state') ?? 'visible';
        sheets.add((_attr(e, 'name') ?? 'Sheet${sheets.length + 1}',
            _relId(e), state == 'visible'));
      }
    }

    final List<SheetTable> out = <SheetTable>[];
    final List<SheetTable> hidden = <SheetTable>[];
    for (int i = 0; i < sheets.length; i++) {
      final (String name, String? relId, bool visible) = sheets[i];
      final _Rel? rel = relId == null ? null : rels[relId];
      if (rel != null && !rel.type.endsWith('/worksheet')) continue; // charts
      final String path = rel != null
          ? _resolve(dir, rel.target)
          : _join(dir, 'worksheets/sheet${i + 1}.xml');
      final String? xml = _text(zip, path);
      final SheetTable table = SheetTable(name,
          xml == null ? <List<Object?>>[] : _rows(xml, shared, styles, date1904));
      (visible ? out : hidden).add(table);
    }
    if (out.isEmpty && hidden.isEmpty) {
      throw const ImportFileException('This workbook has no sheets.');
    }
    return out.isNotEmpty ? out : hidden;
  }

  // ---- package parts --------------------------------------------------------

  static String _officeDocument(Archive zip) {
    final Map<String, _Rel> root = _relationships(_text(zip, '_rels/.rels'));
    for (final _Rel r in root.values) {
      if (r.type.endsWith('/officeDocument')) return _resolve('', r.target);
    }
    return 'xl/workbook.xml';
  }

  static String? _text(Archive zip, String path) {
    final ArchiveFile? f = zip.findFile(path);
    if (f == null || !f.isFile) return null;
    String s = utf8.decode(f.content, allowMalformed: true);
    if (s.startsWith('﻿')) s = s.substring(1);
    return s;
  }

  static Map<String, _Rel> _relationships(String? xml) {
    final Map<String, _Rel> out = <String, _Rel>{};
    if (xml == null) return out;
    for (final XmlEvent e in parseEvents(xml)) {
      if (e is XmlStartElementEvent && e.localName == 'Relationship') {
        final String? id = _attr(e, 'Id');
        final String? target = _attr(e, 'Target');
        if (id == null || target == null) continue;
        if ((_attr(e, 'TargetMode') ?? '') == 'External') continue;
        out[id] = _Rel(_attr(e, 'Type') ?? '', target);
      }
    }
    return out;
  }

  static String _join(String dir, String path) =>
      dir.isEmpty ? path : '$dir/$path';

  /// A relationship target relative to [dir] ("/xl/x.xml" is absolute).
  static String _resolve(String dir, String target) {
    if (target.startsWith('/')) return target.substring(1);
    final List<String> parts =
        dir.isEmpty ? <String>[] : dir.split('/').toList();
    for (final String seg in target.split('/')) {
      if (seg == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else if (seg.isNotEmpty && seg != '.') {
        parts.add(seg);
      }
    }
    return parts.join('/');
  }

  // ---- shared strings and styles -------------------------------------------

  static List<String> _sharedStrings(String? xml) {
    final List<String> out = <String>[];
    if (xml == null) return out;
    StringBuffer? item;
    bool inText = false;
    int phonetic = 0;
    for (final XmlEvent e in parseEvents(xml)) {
      if (e is XmlStartElementEvent) {
        switch (e.localName) {
          case 'si':
            if (e.isSelfClosing) {
              out.add('');
            } else {
              item = StringBuffer();
            }
          case 't':
            inText = !e.isSelfClosing;
          case 'rPh':
            if (!e.isSelfClosing) phonetic++;
        }
      } else if (e is XmlEndElementEvent) {
        switch (e.localName) {
          case 'si':
            out.add(_unescape(item?.toString() ?? ''));
            item = null;
          case 't':
            inText = false;
          case 'rPh':
            phonetic--;
        }
      } else if (inText && phonetic == 0 && item != null) {
        if (e is XmlTextEvent) {
          item.write(e.value);
        } else if (e is XmlCDATAEvent) {
          item.write(e.value);
        }
      }
    }
    return out;
  }

  /// For each cell style (the cell's `s`), whether it shows a date.
  static List<_DateKind> _styles(String? xml) {
    if (xml == null) return const <_DateKind>[];
    final Map<int, String> custom = <int, String>{};
    final List<int> formats = <int>[];
    bool inCellXfs = false;
    for (final XmlEvent e in parseEvents(xml)) {
      if (e is XmlStartElementEvent) {
        switch (e.localName) {
          case 'numFmt':
            final int? id = int.tryParse(_attr(e, 'numFmtId') ?? '');
            if (id != null) custom[id] = _attr(e, 'formatCode') ?? '';
          case 'cellXfs':
            inCellXfs = !e.isSelfClosing;
          case 'xf':
            if (inCellXfs) {
              formats.add(int.tryParse(_attr(e, 'numFmtId') ?? '') ?? 0);
            }
        }
      } else if (e is XmlEndElementEvent && e.localName == 'cellXfs') {
        inCellXfs = false;
      }
    }
    return <_DateKind>[
      for (final int id in formats) _kindOf(id, custom[id]),
    ];
  }

  static _DateKind _kindOf(int id, String? code) {
    if (code != null) return _kindOfCode(code);
    if (id == 17) return _DateKind.month; // mmm-yy
    if ((id >= 14 && id <= 16) || id == 22) return _DateKind.day;
    return _DateKind.none;
  }

  /// Date or not from a number format code: quoted text, escapes and
  /// [colour/locale] parts are ignored; then d → a full date, y and m
  /// without d → month and year ("mmm-yy"), neither → not a date.
  static _DateKind _kindOfCode(String code) {
    final String c = code
        .replaceAll(RegExp(r'"[^"]*"'), '')
        .replaceAll(RegExp(r'\\.'), '')
        .replaceAll(RegExp(r'\[[^\]]*\]'), '')
        .split(';')
        .first
        .toLowerCase();
    if (c.contains('d')) return _DateKind.day;
    if (c.contains('y')) return c.contains('m') ? _DateKind.month : _DateKind.day;
    return _DateKind.none;
  }

  // ---- cells ----------------------------------------------------------------

  static List<List<Object?>> _rows(String xml, List<String> shared,
      List<_DateKind> styles, bool date1904) {
    final Map<int, List<Object?>> rows = <int, List<Object?>>{};
    int lastRow = -1;
    int row = -1;
    int nextRow = 0;
    int nextCol = 0;

    bool inCell = false;
    int col = 0;
    String? type;
    int style = -1;
    final StringBuffer value = StringBuffer();
    final StringBuffer inline = StringBuffer();
    bool inValue = false;
    bool inInline = false;
    bool inText = false;
    int phonetic = 0;

    for (final XmlEvent e in parseEvents(xml)) {
      if (e is XmlStartElementEvent) {
        switch (e.localName) {
          case 'row':
            final int? r = int.tryParse(_attr(e, 'r') ?? '');
            row = r != null ? r - 1 : nextRow;
            nextRow = row + 1;
            nextCol = 0;
          case 'c':
            final String? ref = _attr(e, 'r');
            col = (ref == null ? null : _columnOf(ref)) ?? nextCol;
            nextCol = col + 1;
            type = _attr(e, 't');
            style = int.tryParse(_attr(e, 's') ?? '') ?? -1;
            value.clear();
            inline.clear();
            inCell = !e.isSelfClosing;
          case 'v':
            inValue = inCell && !e.isSelfClosing;
          case 'is':
            inInline = inCell && !e.isSelfClosing;
          case 't':
            inText = inInline && !e.isSelfClosing;
          case 'rPh':
            if (!e.isSelfClosing) phonetic++;
        }
      } else if (e is XmlEndElementEvent) {
        switch (e.localName) {
          case 'v':
            inValue = false;
          case 'is':
            inInline = false;
          case 't':
            inText = false;
          case 'rPh':
            phonetic--;
          case 'c':
            if (inCell &&
                row >= 0 &&
                row < maxRows &&
                col >= 0 &&
                col < maxColumns) {
              final Object? v = _value(type, style, value.toString(),
                  inline.toString(), shared, styles, date1904);
              if (v != null && (v is! String || v.trim().isNotEmpty)) {
                final List<Object?> cells = rows[row] ??= <Object?>[];
                while (cells.length <= col) {
                  cells.add(null);
                }
                cells[col] = v;
                if (row > lastRow) lastRow = row;
              }
            }
            inCell = false;
        }
      } else if (inValue || (inText && phonetic == 0)) {
        final String? t = e is XmlTextEvent
            ? e.value
            : (e is XmlCDATAEvent ? e.value : null);
        if (t != null) (inValue ? value : inline).write(t);
      }
    }
    return <List<Object?>>[
      for (int r = 0; r <= lastRow; r++) rows[r] ?? <Object?>[],
    ];
  }

  static Object? _value(String? type, int style, String raw, String inline,
      List<String> shared, List<_DateKind> styles, bool date1904) {
    switch (type) {
      case 's':
        final int? i = int.tryParse(raw.trim());
        return i != null && i >= 0 && i < shared.length ? shared[i] : null;
      case 'inlineStr':
        return _unescape(inline);
      case 'str':
        return _unescape(raw);
      case 'b':
        return raw.trim() == '1' || raw.trim().toLowerCase() == 'true';
      case 'e':
        return raw.trim(); // e.g. #N/A
      case 'd':
        final DateTime? d = DateTime.tryParse(raw.trim());
        return d == null ? raw.trim() : CellDate(d);
    }
    final String t = raw.trim();
    if (t.isEmpty) return inline.isEmpty ? null : _unescape(inline);
    final double? n = double.tryParse(t);
    if (n == null) return t;
    final _DateKind kind =
        style >= 0 && style < styles.length ? styles[style] : _DateKind.none;
    if (kind != _DateKind.none) {
      final DateTime? d = _fromSerial(n, date1904);
      if (d != null) return CellDate(d, hasDay: kind == _DateKind.day);
    }
    if (n == n.truncateToDouble() && n.abs() < 9007199254740992) {
      return n.toInt();
    }
    return n;
  }

  /// Excel's day number → date (1 = 1 Jan 1900, or 1 Jan 1904 in the
  /// Mac date system). The time of day is dropped.
  static DateTime? _fromSerial(double serial, bool date1904) {
    if (!serial.isFinite || serial < 1 || serial > 2958465) return null;
    final int days = serial.floor();
    final DateTime base = date1904
        ? DateTime.utc(1904, 1, 1)
        // Excel counts a 29 Feb 1900 that never was.
        : (days < 60 ? DateTime.utc(1899, 12, 31) : DateTime.utc(1899, 12, 30));
    final DateTime d = base.add(Duration(days: days));
    return DateTime(d.year, d.month, d.day);
  }

  /// Column of a cell reference: "A1" → 0, "AB12" → 27.
  static int? _columnOf(String ref) {
    int col = 0;
    int i = 0;
    while (i < ref.length) {
      final int c = ref.codeUnitAt(i);
      if (c >= 65 && c <= 90) {
        col = col * 26 + (c - 64);
      } else if (c >= 97 && c <= 122) {
        col = col * 26 + (c - 96);
      } else {
        break;
      }
      i++;
    }
    return i == 0 ? null : col - 1;
  }

  static String? _attr(XmlStartElementEvent e, String name) {
    for (final XmlEventAttribute a in e.attributes) {
      if (a.name == name) return a.value;
    }
    return null;
  }

  /// The sheet's relationship id (`r:id`, whatever the prefix).
  static String? _relId(XmlStartElementEvent e) {
    for (final XmlEventAttribute a in e.attributes) {
      if (a.localName == 'id' && a.namespacePrefix != null) return a.value;
    }
    return null;
  }

  static final RegExp _escaped = RegExp(r'_x([0-9A-Fa-f]{4})_');

  /// Excel writes some characters as _xHHHH_ (e.g. _x000D_ for a return).
  static String _unescape(String s) => s.contains('_x')
      ? s.replaceAllMapped(_escaped,
          (Match m) => String.fromCharCode(int.parse(m[1]!, radix: 16)))
      : s;
}

enum _DateKind { none, day, month }

class _Rel {
  final String type;
  final String target;
  const _Rel(this.type, this.target);
}
