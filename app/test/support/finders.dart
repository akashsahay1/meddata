// Finders and small actions shared by the widget tests.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:med_stock/presentation/widgets/ui_kit.dart';

/// The nearest Column around the label text [label] (the add screen puts
/// each label in a Column with its field).
Finder _labelled(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(Column)).first;

/// The text field labelled [label].
Finder fieldLabeled(String label) =>
    find.descendant(of: _labelled(label), matching: find.byType(TextFormField));

/// The current text of the field labelled [label].
String fieldText(WidgetTester tester, String label) =>
    tester.widget<TextFormField>(fieldLabeled(label)).controller!.text;

/// The tappable box of the date field labelled [label].
Finder dateField(String label) =>
    find.descendant(of: _labelled(label), matching: find.byType(InkWell)).first;

/// Taps [button] in the open dialog (screens have their own Cancel/OK too).
Future<void> answerDialog(WidgetTester tester, String button) async {
  await tester.tap(
      find.descendant(of: find.byType(Dialog), matching: find.text(button)));
  await tester.pumpAndSettle();
}

/// Names of the medicine rows on screen, top to bottom.
List<String> tileNames(WidgetTester tester) => tester
    .widgetList<MedicineTile>(find.byType(MedicineTile))
    .map((MedicineTile t) => t.name)
    .toList();

/// Status pill text of each medicine row, top to bottom.
List<String?> tileStatuses(WidgetTester tester) => tester
    .widgetList<MedicineTile>(find.byType(MedicineTile))
    .map((MedicineTile t) => t.status?.text)
    .toList();

/// [value] shown on the dashboard [card] (StatCard / AlertCard) labelled
/// [label].
Finder cardValue(Type card, String label, String value) => find.descendant(
      of: find.ancestor(of: find.text(label), matching: find.byType(card)),
      matching: find.text(value),
    );

/// Taps the Inventory filter chip [label]; the chip row scrolls sideways on
/// a phone, so it is scrolled into view first.
Future<void> tapChip(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}
