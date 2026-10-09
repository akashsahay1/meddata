import 'package:flutter_test/flutter_test.dart';
import 'package:med_stock/presentation/screens/auth/auth_widgets.dart';

void main() {
  test('passwords need 8 characters, like the server', () {
    expect(AuthValidators.password(''), isNotNull);
    expect(AuthValidators.password('rajesh7'), 'At least 8 characters');
    expect(AuthValidators.password('rajesh78'), isNull);
  });
}
