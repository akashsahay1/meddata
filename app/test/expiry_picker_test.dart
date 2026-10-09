import 'package:flutter_test/flutter_test.dart';
import 'package:med_stock/presentation/widgets/expiry_picker.dart';

void main() {
  test('expiry as printed: month and year, the last day of the month', () {
    expect(parseExpiryMonth('08/28'), DateTime(2028, 8, 31));
    expect(parseExpiryMonth('8/28'), DateTime(2028, 8, 31));
    expect(parseExpiryMonth('02/28'), DateTime(2028, 2, 29), reason: 'leap year');
    expect(parseExpiryMonth('12/2029'), DateTime(2029, 12, 31));
    expect(parseExpiryMonth('0827'), DateTime(2027, 8, 31));
    expect(parseExpiryMonth('13/28'), isNull);
    expect(parseExpiryMonth('00/28'), isNull);
    expect(parseExpiryMonth('Aug 28'), isNull);
    expect(parseExpiryMonth(''), isNull);
  });
}
