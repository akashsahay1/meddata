import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:med_stock/data/models/subscription_plan.dart';
import 'package:med_stock/presentation/screens/subscribe_view.dart';
import 'package:med_stock/services/settings_service.dart';
import 'package:med_stock/services/subscription_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Two plans; WELCOME20 takes 20% off whichever plan it is checked against.
class _Sub extends SubscriptionService {
  _Sub(SettingsService s) : super(s, 'dev');

  final List<(String, int)> checked = <(String, int)>[];

  static const List<SubscriptionPlan> plans = <SubscriptionPlan>[
    SubscriptionPlan(id: 1, productId: 'premium_yearly', name: 'Yearly Plan', price: 999,
        currency: 'INR', period: 'yearly', isBestValue: true),
    SubscriptionPlan(id: 2, productId: 'premium_monthly', name: 'Monthly Plan', price: 99,
        currency: 'INR', period: 'monthly'),
  ];

  @override
  Future<List<SubscriptionPlan>> fetchPlans() async => plans;

  @override
  Future<Map<String, dynamic>?> validateCoupon(String code, int planId) async {
    checked.add((code, planId));
    final double price = plans.firstWhere((SubscriptionPlan p) => p.id == planId).price;
    return <String, dynamic>{
      'valid': true,
      'final_amount': price * 0.8,
      'message': 'Coupon applied.',
    };
  }
}

void main() {
  testWidgets('switching plan keeps the coupon and applies it to the new plan',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SettingsService settings = SettingsService();
    await settings.init();
    final _Sub sub = _Sub(settings);
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<SettingsService>.value(value: settings),
        ChangeNotifierProvider<SubscriptionService>.value(value: sub),
      ],
      child: const MaterialApp(home: Scaffold(body: SubscribeView())),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Have a coupon code?'), 'welcome20');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.textContaining('799.20'), findsWidgets);

    await tester.tap(find.text('Monthly Plan'));
    await tester.pumpAndSettle();
    expect(sub.checked, <(String, int)>[('welcome20', 1), ('welcome20', 2)],
        reason: 'the same code is checked again for the new plan');
    expect(find.text('Applied'), findsOneWidget);
    expect(find.textContaining('79.20'), findsWidgets, reason: '20% off ₹99');
  });
}
