import 'package:intl/intl.dart';

/// Shared formatting helpers.
class Fmt {
  Fmt._();

  static final DateFormat _date = DateFormat('dd MMM yyyy');
  static final DateFormat _dateShort = DateFormat('dd/MM/yy');

  static String date(DateTime d) => _date.format(d);
  static String dateShort(DateTime d) => _dateShort.format(d);

  /// Indian grouping (₹1,27,751), as on bills; the default locale grouped
  /// by thousands (₹127,751).
  static String money(double v, {String symbol = '₹'}) {
    final NumberFormat f = NumberFormat.currency(
      locale: 'en_IN',
      symbol: symbol,
      decimalDigits: v == v.roundToDouble() ? 0 : 2,
    );
    return f.format(v);
  }
}
