import 'package:intl/intl.dart';

/// Shared formatting helpers.
class Fmt {
  Fmt._();

  static final DateFormat _date = DateFormat('dd MMM yyyy');
  static final DateFormat _dateShort = DateFormat('dd/MM/yy');

  static String date(DateTime d) => _date.format(d);
  static String dateShort(DateTime d) => _dateShort.format(d);

  static String money(double v, {String symbol = '₹'}) {
    final NumberFormat f = NumberFormat.currency(
      symbol: symbol,
      decimalDigits: v == v.roundToDouble() ? 0 : 2,
    );
    return f.format(v);
  }
}
