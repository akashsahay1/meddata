import 'package:flutter_test/flutter_test.dart';
import 'package:medikabiz/core/formatters.dart';

void main() {
  // Screen amounts (stock value, report totals) were grouped by thousands,
  // "₹127,751", while bills say "₹1,27,751".
  test('money uses Indian digit grouping', () {
    expect(Fmt.money(127751), '₹1,27,751');
    expect(Fmt.money(12345678.5), '₹1,23,45,678.50');
    expect(Fmt.money(999), '₹999');
  });
}
