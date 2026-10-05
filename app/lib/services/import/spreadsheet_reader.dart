import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:csv/csv.dart';

import 'sheet_table.dart';
import 'xlsx_reader.dart';

/// Turns a picked file into [SheetTable]s. The format is recognised from the
/// content, not the name: phones don't always keep the extension (a CSV
/// shared over WhatsApp can arrive named .txt or .xls).
class SpreadsheetReader {
  SpreadsheetReader._();

  static const int maxBytes = 25 * 1024 * 1024;

  /// Throws [ImportFileException] with a message for the user when the
  /// file can't be imported.
  static List<SheetTable> read(Uint8List bytes, {String fileName = ''}) {
    if (bytes.isEmpty) throw const ImportFileException('The file is empty.');
    if (bytes.length > maxBytes) {
      throw const ImportFileException(
          'The file is too large (over 25 MB). Split it into smaller files.');
    }
    if (_startsWith(bytes, const <int>[0x50, 0x4B])) {
      return XlsxReader.read(bytes); // a zip: .xlsx
    }
    if (_startsWith(bytes,
        const <int>[0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])) {
      throw const ImportFileException(
          'This is an old Excel file (.xls) or a password-protected one. '
          'Open it in Excel and save it as .xlsx or CSV, then import that.');
    }
    if (_startsWith(bytes, ascii.encode('%PDF'))) {
      throw const ImportFileException(
          'PDF files can\'t be imported. Export the stock list from your '
          'software as Excel or CSV.');
    }
    final String text = decodeText(bytes);
    if (text.substring(0, math.min(4096, text.length)).contains('\u0000')) {
      throw const ImportFileException(
          'This file is not a CSV or Excel (.xlsx) file.');
    }
    if (RegExp(r'^\s*<(!doctype html|html|table)', caseSensitive: false)
        .hasMatch(text.substring(0, math.min(200, text.length)))) {
      throw const ImportFileException(
          'This file is a web page (HTML) saved with a spreadsheet name. '
          'Open it in Excel and save it as .xlsx or CSV, then import that.');
    }
    return <SheetTable>[SheetTable(_baseName(fileName), parseCsv(text))];
  }

  /// UTF-8 (with or without a BOM), UTF-16 with a BOM (Excel's "Unicode
  /// text"), else Windows/Latin-1 text from older software.
  static String decodeText(Uint8List b) {
    if (_startsWith(b, const <int>[0xEF, 0xBB, 0xBF])) {
      return utf8.decode(b.sublist(3), allowMalformed: true);
    }
    if (_startsWith(b, const <int>[0xFF, 0xFE])) return _utf16(b, little: true);
    if (_startsWith(b, const <int>[0xFE, 0xFF])) return _utf16(b, little: false);
    try {
      return utf8.decode(b);
    } on FormatException {
      return latin1.decode(b);
    }
  }

  /// Rows of a CSV text (comma, semicolon, tab or | separated — detected),
  /// every cell as text so batch numbers and barcodes keep leading zeros.
  /// Blank lines are kept so row numbers match the file.
  static List<List<Object?>> parseCsv(String text) {
    final List<List<dynamic>> rows = Csv(skipEmptyLines: false).decode(text);
    return <List<Object?>>[
      for (final List<dynamic> r in rows)
        <Object?>[for (final dynamic v in r) v?.toString()],
    ];
  }

  static String _utf16(Uint8List b, {required bool little}) {
    final List<int> units = <int>[];
    for (int i = 2; i + 1 < b.length; i += 2) {
      units.add(little ? b[i] | (b[i + 1] << 8) : (b[i] << 8) | b[i + 1]);
    }
    return String.fromCharCodes(units);
  }

  static bool _startsWith(Uint8List b, List<int> prefix) {
    if (b.length < prefix.length) return false;
    for (int i = 0; i < prefix.length; i++) {
      if (b[i] != prefix[i]) return false;
    }
    return true;
  }

  static String _baseName(String fileName) {
    final String name = fileName.split(RegExp(r'[/\\]')).last;
    final int dot = name.lastIndexOf('.');
    final String base = dot > 0 ? name.substring(0, dot) : name;
    return base.isEmpty ? 'Sheet 1' : base;
  }
}
