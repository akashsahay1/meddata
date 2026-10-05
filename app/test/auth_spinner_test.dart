// While Log in / Send reset code waits for the server, the button is disabled
// (light grey) and shows a spinner, which must be dark to be seen.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:med_stock/presentation/screens/auth/forgot_password_screen.dart';
import 'package:med_stock/presentation/screens/auth/login_screen.dart';
import 'package:med_stock/services/api_client.dart';
import 'package:med_stock/services/auth_service.dart';
import 'package:med_stock/services/settings_service.dart';
import 'package:med_stock/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_app.dart';

typedef _Reply = ({int status, Map<String, dynamic>? body});

/// A server that has not answered yet.
class _SlowServer extends ApiClient {
  final Completer<_Reply> reply = Completer<_Reply>();

  @override
  Future<_Reply> login(
          {required String email, required String password, String? deviceId}) =>
      reply.future;

  @override
  Future<_Reply> forgotPassword(String email) => reply.future;
}

double _luminanceContrast(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

Future<void> _expectVisibleSpinner(
    WidgetTester tester, Widget screen, String field, String button) async {
  usePhoneScreen(tester);
  SharedPreferences.setMockInitialValues(<String, Object>{'onboarded': true});
  final SettingsService settings = SettingsService();
  await settings.init();
  final _SlowServer server = _SlowServer();
  final AuthService auth =
      AuthService(settings, 'phone-1', server, MemoryTokenStore());
  await auth.init();

  await tester.pumpWidget(MultiProvider(
    providers: <ChangeNotifierProvider<ChangeNotifier>>[
      ChangeNotifierProvider<SettingsService>.value(value: settings),
      ChangeNotifierProvider<AuthService>.value(value: auth),
    ],
    child: MaterialApp(theme: AppTheme.light, home: screen),
  ));
  await tester.enterText(
      find.widgetWithText(TextFormField, field).first, 'owner@example.com');
  final Finder password = find.byWidgetPredicate(
      (Widget w) => w is TextField && w.obscureText);
  if (password.evaluate().isNotEmpty) {
    await tester.enterText(password.first, 'secret123');
  }
  await tester.tap(find.widgetWithText(ElevatedButton, button));
  await tester.pump();

  final CircularProgressIndicator spinner =
      tester.widget(find.byType(CircularProgressIndicator));
  final ElevatedButton disabled = tester.widget(find.ancestor(
      of: find.byType(CircularProgressIndicator),
      matching: find.byType(ElevatedButton)));
  expect(disabled.onPressed, isNull);
  final BuildContext context =
      tester.element(find.byType(CircularProgressIndicator));
  final Color color = spinner.color ??
      spinner.valueColor?.value ??
      Theme.of(context).colorScheme.primary;
  expect(color, AppColors.ink);
  // The disabled button as drawn: a faint fill over the white card.
  final Material fill = tester.widget(find
      .descendant(
          of: find.byWidget(disabled), matching: find.byType(Material))
      .first);
  final Color background = Color.alphaBlend(fill.color!, Colors.white);
  expect(_luminanceContrast(color, background), greaterThanOrEqualTo(3),
      reason: 'the spinner stands out from the disabled button');

  server.reply.complete((status: 0, body: null));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Log in shows a visible spinner while waiting',
      (WidgetTester tester) async {
    await _expectVisibleSpinner(
        tester, const LoginScreen(), 'you@example.com', 'Log in');
  });

  testWidgets('Send reset code shows a visible spinner while waiting',
      (WidgetTester tester) async {
    await _expectVisibleSpinner(tester, const ForgotPasswordScreen(),
        'you@example.com', 'Send reset code');
  });
}
