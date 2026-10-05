/// One sheet of a spreadsheet file being imported: [rows] of cell values,
/// where row index 0 is spreadsheet row 1 (blank rows are kept so row
/// numbers match what the user sees in Excel). A cell is a [String], [num],
/// [bool], [CellDate] or null.
class SheetTable {
  final String name;
  final List<List<Object?>> rows;

  const SheetTable(this.name, this.rows);

  int get columnCount {
    int n = 0;
    for (final List<Object?> r in rows) {
      if (r.length > n) n = r.length;
    }
    return n;
  }

  Object? cell(int row, int col) {
    if (row < 0 || row >= rows.length) return null;
    final List<Object?> r = rows[row];
    return col >= 0 && col < r.length ? r[col] : null;
  }

  /// Rows with at least one non-blank cell.
  int get filledRowCount => rows.where(rowHasData).length;

  static bool rowHasData(List<Object?> row) => row.any((Object? v) =>
      v != null && (v is! String || v.trim().isNotEmpty));
}

/// A date cell. [hasDay] is false for a month and year only, such as "12/27"
/// or an Excel cell formatted "Dec-27" (how expiry dates are usually
/// written; Excel stores those as the 1st of the month).
class CellDate {
  final DateTime date;
  final bool hasDay;

  CellDate(DateTime d, {this.hasDay = true})
      : date = DateTime(d.year, d.month, hasDay ? d.day : 1);

  @override
  bool operator ==(Object other) =>
      other is CellDate && other.date == date && other.hasDay == hasDay;

  @override
  int get hashCode => Object.hash(date, hasDay);

  @override
  String toString() {
    String two(int v) => v.toString().padLeft(2, '0');
    return hasDay
        ? '${date.year}-${two(date.month)}-${two(date.day)}'
        : '${date.year}-${two(date.month)}';
  }
}

/// A file that can't be imported; [message] is shown to the user.
class ImportFileException implements Exception {
  final String message;
  const ImportFileException(this.message);

  @override
  String toString() => message;
}
