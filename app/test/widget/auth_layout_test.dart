import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medikabiz/presentation/screens/auth/login_screen.dart';
import 'package:medikabiz/presentation/screens/auth/signup_screen.dart';

import '../support/test_app.dart';

void main() {
  Future<void> show(WidgetTester tester, Size size, Widget screen) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final TestApp app = await TestApp.create();
    addTearDown(app.dispose);
    await tester.pumpWidget(app.wrap(screen));
    await tester.pumpAndSettle();
  }

  for (final (String name, Widget screen) in <(String, Widget)>[
    ('log in', const LoginScreen()),
    ('sign up', const SignupScreen()),
  ]) {
    testWidgets('$name on a computer: navy panel says what the app is', (WidgetTester tester) async {
      await show(tester, const Size(1280, 800), screen);
      expect(find.text('Your medical shop,\nin order.'), findsOneWidget);
      expect(find.text('Works without internet, syncs later'), findsOneWidget);
      expect(find.text('Medikabiz'), findsOneWidget, reason: 'the panel has the logo; no second one over the form');
    });

    testWidgets('$name on a phone: just the form, under the logo', (WidgetTester tester) async {
      await show(tester, const Size(390, 844), screen);
      expect(find.text('Your medical shop,\nin order.'), findsNothing);
      expect(find.text('Medikabiz'), findsOneWidget);
    });
  }
}
