import 'package:flutter_test/flutter_test.dart';
import 'package:med_stock/main.dart';

import 'support/test_app.dart';

void main() {
  testWidgets('app opens the Meddata login screen when signed out', (
    WidgetTester tester,
  ) async {
    final TestApp app = await TestApp.create();
    addTearDown(app.dispose);

    await tester.pumpWidget(
      MeddataApp(
        settings: app.settings,
        auth: app.auth,
        subscription: app.subscription,
        medicines: app.medicines,
        sync: app.sync,
      ),
    );
    await tester.pump();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
  });
}
