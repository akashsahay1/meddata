/// Rupee amounts held as integer paise: Indian digit grouping (1,23,456.00),
/// amounts in words (lakh / crore) and GST percentages from basis points.
class Inr {
  Inr._();

  /// "₹1,23,456.78" (or "-₹0.49"); [symbol] false gives "1,23,456.78".
  static String format(int paise, {bool symbol = true}) {
    final String sign = paise < 0 ? '-' : '';
    final int abs = paise.abs();
    final String rupees = group(abs ~/ 100);
    final String p = (abs % 100).toString().padLeft(2, '0');
    return '$sign${symbol ? '₹' : ''}$rupees.$p';
  }

  /// Indian grouping of a whole number: 1234567 -> "12,34,567".
  static String group(int n) {
    final String s = n.abs().toString();
    if (s.length <= 3) return n < 0 ? '-$s' : s;
    final String last3 = s.substring(s.length - 3);
    String rest = s.substring(0, s.length - 3);
    final List<String> parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    return '${n < 0 ? '-' : ''}${parts.join(',')},$last3';
  }

  /// GST / discount rate from basis points: 500 -> "5%", 1250 -> "12.5%".
  static String percent(int bp) {
    final String whole = (bp ~/ 100).toString();
    final int frac = bp % 100;
    if (frac == 0) return '$whole%';
    final String f = frac.toString().padLeft(2, '0').replaceAll(RegExp(r'0+$'), '');
    return '$whole.$f%';
  }

  /// "12.5" -> 1250 basis points; null if not a number in 0..100.
  static int? parsePercent(String text) {
    final String t = text.trim().replaceAll('%', '');
    if (t.isEmpty) return 0;
    final double? v = double.tryParse(t);
    if (v == null || v < 0 || v > 100) return null;
    return (v * 100).round();
  }

  /// "Rupees One Lakh Twenty Three Thousand Four Hundred Fifty Six and
  /// Seventy Eight Paise Only".
  static String words(int paise) {
    final int abs = paise.abs();
    final int rupees = abs ~/ 100;
    final int p = abs % 100;
    final StringBuffer b = StringBuffer(paise < 0 ? 'Minus Rupees ' : 'Rupees ')
      ..write(_number(rupees));
    if (p > 0) b.write(' and ${_twoDigits(p)} Paise');
    b.write(' Only');
    return b.toString();
  }

  static const List<String> _ones = <String>[
    '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine',
    'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen',
    'Seventeen', 'Eighteen', 'Nineteen',
  ];
  static const List<String> _tens = <String>[
    '', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy',
    'Eighty', 'Ninety',
  ];

  static String _number(int n) {
    if (n == 0) return 'Zero';
    final List<String> parts = <String>[];
    final int crore = n ~/ 10000000;
    final int lakh = (n ~/ 100000) % 100;
    final int thousand = (n ~/ 1000) % 100;
    final int rest = n % 1000;
    if (crore > 0) parts.add('${_number(crore)} Crore');
    if (lakh > 0) parts.add('${_twoDigits(lakh)} Lakh');
    if (thousand > 0) parts.add('${_twoDigits(thousand)} Thousand');
    if (rest > 0) parts.add(_threeDigits(rest));
    return parts.join(' ');
  }

  static String _threeDigits(int n) {
    final int hundreds = n ~/ 100;
    final int rest = n % 100;
    if (hundreds == 0) return _twoDigits(rest);
    return rest == 0
        ? '${_ones[hundreds]} Hundred'
        : '${_ones[hundreds]} Hundred ${_twoDigits(rest)}';
  }

  static String _twoDigits(int n) {
    if (n < 20) return _ones[n];
    final int unit = n % 10;
    return unit == 0 ? _tens[n ~/ 10] : '${_tens[n ~/ 10]} ${_ones[unit]}';
  }
}
