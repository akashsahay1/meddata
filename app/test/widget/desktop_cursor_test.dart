// On desktop the mouse shows a hand over everything that can be clicked, and
// the plain arrow over things that can't (or are disabled).
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medikabiz/presentation/screens/auth/login_screen.dart';
import 'package:medikabiz/presentation/widgets/summary_tile.dart';
import 'package:medikabiz/theme/app_theme.dart';

import '../support/test_app.dart';

Future<MouseCursor?> _cursorOver(WidgetTester tester, Finder target) async {
  final TestGesture mouse =
      await tester.createGesture(kind: PointerDeviceKind.mouse, pointer: 1);
  await mouse.addPointer(location: tester.getCenter(target));
  addTearDown(mouse.removePointer);
  await tester.pump();
  return RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1);
}

Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: Center(child: SizedBox(width: 300, child: child))),
    );

void main() {
  final Map<String, (Widget, MouseCursor)> cases = <String, (Widget, MouseCursor)>{
    'tap target': (
      TapTarget(label: 'Go', onTap: () {}, child: const Text('Go')),
      SystemMouseCursors.click
    ),
    'disabled tap target': (
      const TapTarget(label: 'Go', onTap: null, child: Text('Go')),
      SystemMouseCursors.basic
    ),
    'section header action': (
      SectionHeader(title: 'Stock', actionLabel: 'Go', onAction: () {}),
      SystemMouseCursors.click
    ),
    'orange button': (
      ElevatedButton(onPressed: () {}, child: const Text('Go')),
      SystemMouseCursors.click
    ),
    'disabled button': (
      const ElevatedButton(onPressed: null, child: Text('Go')),
      SystemMouseCursors.basic
    ),
    'outlined button': (
      OutlinedButton(onPressed: () {}, child: const Text('Go')),
      SystemMouseCursors.click
    ),
    'text button': (
      TextButton(onPressed: () {}, child: const Text('Go')),
      SystemMouseCursors.click
    ),
    'icon button': (
      IconButton(onPressed: () {}, icon: const Text('Go')),
      SystemMouseCursors.click
    ),
    'add button': (
      FloatingActionButton.extended(onPressed: () {}, label: const Text('Go')),
      SystemMouseCursors.click
    ),
    'alert card': (
      AlertCard(
          icon: Icons.warning,
          count: 2,
          label: 'Go',
          color: AppColors.statusAmber,
          bg: AppColors.statusAmberBg,
          onTap: () {}),
      SystemMouseCursors.click
    ),
    'stat card': (
      StatCard(label: 'Sales', value: 'Go', onTap: () {}),
      SystemMouseCursors.click
    ),
    'stat card without a tap': (
      const StatCard(label: 'Sales', value: 'Go'),
      SystemMouseCursors.basic
    ),
    'summary tile': (
      SummaryTile(label: 'Low', value: 'Go', icon: Icons.warning, onTap: () {}),
      SystemMouseCursors.click
    ),
  };

  for (final MapEntry<String, (Widget, MouseCursor)> c in cases.entries) {
    testWidgets('${c.key} shows the ${c.value.$2 == SystemMouseCursors.click ? 'hand' : 'arrow'}',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(c.value.$1));
      expect(await _cursorOver(tester, find.text('Go')), c.value.$2);
    });
  }

  testWidgets('login screen: the "Start free trial" link shows the hand',
      (WidgetTester tester) async {
    final TestApp app = await TestApp.create();
    addTearDown(app.dispose);
    await tester.pumpWidget(app.wrap(const LoginScreen()));
    await tester.pumpAndSettle();
    expect(await _cursorOver(tester, find.text('Start free trial')),
        SystemMouseCursors.click);
  });
}
