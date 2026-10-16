import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medikabiz/presentation/screens/billing/shop_settings_screen.dart';
import 'package:medikabiz/services/api_client.dart';
import 'package:medikabiz/services/auth_service.dart';
import 'package:medikabiz/services/billing_api.dart';
import 'package:medikabiz/services/settings_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Server extends ApiClient {
  Map<String, dynamic>? sent;
  static final Map<String, dynamic> shop = <String, dynamic>{
    'name': 'Sahay Medicals', 'state_code': '27', 'default_gst_rate_bp': 500,
    'pharmacist_name': 'Alok Sahay', 'pharmacist_reg_date': '2019-06-01',
  };

  @override
  Future<({int status, Map<String, dynamic>? body})> currentShop(String token) async =>
      (status: 200, body: <String, dynamic>{'shop': shop});

  @override
  Future<({int status, Map<String, dynamic>? body})> updateShop(String token, Map<String, dynamic> changes) async {
    sent = changes;
    return (status: 200, body: <String, dynamic>{'shop': <String, dynamic>{...shop, ...changes}});
  }
}

class _MemoryTokenStore implements TokenStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String token) async => value = token;
  @override
  Future<void> delete() async => value = null;
}

void main() {
  testWidgets('pharmacist, email and FSSAI details load, validate and save', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(<String, Object>{'auth_token': 'tok', 'auth_email': 'a@b.c'});
    final AuthService auth = AuthService(SettingsService(), 'phone-1', null, _MemoryTokenStore());
    await auth.init();
    final _Server server = _Server();
    await tester.pumpWidget(ChangeNotifierProvider<AuthService>.value(
      value: auth,
      child: MaterialApp(home: ShopSettingsScreen(api: BillingApi(server))),
    ));
    await tester.pumpAndSettle();

    // Loaded: the name in its field, the date shown as dd MMM yyyy.
    expect(find.text('01 Jun 2019'), findsOneWidget);
    TextField field(String label) => tester.widget<TextField>(find.widgetWithText(TextField, label));
    expect(field('Pharmacist name').controller!.text, 'Alok Sahay');

    await tester.enterText(find.widgetWithText(TextField, 'Email'), 'not-an-email');
    await tester.enterText(find.widgetWithText(TextField, 'FSSAI licence no.'), '1234');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Not a valid email - check it'), findsOneWidget);
    expect(find.text('Must be 14 digits'), findsOneWidget);
    expect(server.sent, isNull);

    await tester.enterText(find.widgetWithText(TextField, 'Email'), 'shop@sahay.in');
    await tester.enterText(find.widgetWithText(TextField, 'FSSAI licence no.'), '11521999000012');
    await tester.enterText(find.widgetWithText(TextField, 'Qualification'), 'B.Pharm');
    await tester.enterText(find.widgetWithText(TextField, 'Registration no.'), 'MH/12345');
    // Pick a new registration date with the date picker.
    await tester.tap(find.text('01 Jun 2019'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('15'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('15 Jun 2019'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(server.sent, containsPair('email', 'shop@sahay.in'));
    expect(server.sent, containsPair('fssai_no', '11521999000012'));
    expect(server.sent, containsPair('pharmacist_name', 'Alok Sahay'));
    expect(server.sent, containsPair('pharmacist_qualification', 'B.Pharm'));
    expect(server.sent, containsPair('pharmacist_reg_no', 'MH/12345'));
    expect(server.sent, containsPair('pharmacist_reg_date', '2019-06-15'));
  });
}
