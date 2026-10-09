import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';

/// Asks for an expiry as it is printed on a strip: month and year, "08/28".
/// A month-only expiry means the last day of that month (as the import
/// wizard reads it). "Pick a day" opens a calendar for packs that print a
/// full date. Returns null when cancelled.
///
/// [after]: the expiry must fall after this day (the manufacture date).
Future<DateTime?> pickExpiry(
  BuildContext context, {
  DateTime? initial,
  DateTime? after,
}) =>
    showDialog<DateTime>(
      context: context,
      builder: (_) => _ExpiryDialog(initial: initial, after: after),
    );

/// The last day of [month] in [year].
DateTime endOfMonth(int year, int month) => DateTime(year, month + 1, 0);

/// "08/28", "8/28", "08/2028", "0828" -> the last day of that month; null
/// when it isn't a month and year.
DateTime? parseExpiryMonth(String text) {
  final String t = text.trim();
  final RegExpMatch? m =
      RegExp(r'^(\d{1,2})\s*[/\-. ]?\s*(\d{2}|\d{4})$').firstMatch(t);
  if (m == null) return null;
  final int month = int.parse(m[1]!);
  int year = int.parse(m[2]!);
  if (month < 1 || month > 12) return null;
  if (year < 100) year += 2000;
  if (year < 2000 || year > 2099) return null;
  return endOfMonth(year, month);
}

class _ExpiryDialog extends StatefulWidget {
  const _ExpiryDialog({this.initial, this.after});

  final DateTime? initial;
  final DateTime? after;

  @override
  State<_ExpiryDialog> createState() => _ExpiryDialogState();
}

class _ExpiryDialogState extends State<_ExpiryDialog> {
  late final TextEditingController _text = () {
    final String t = widget.initial == null
        ? ''
        : '${widget.initial!.month.toString().padLeft(2, '0')}/'
            '${(widget.initial!.year % 100).toString().padLeft(2, '0')}';
    // Selected, so typing a new expiry replaces it.
    return TextEditingController.fromValue(TextEditingValue(
        text: t, selection: TextSelection(baseOffset: 0, extentOffset: t.length)));
  }();
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool _isAfterMfg(DateTime d) {
    final DateTime? a = widget.after;
    return a == null ||
        DateTime(d.year, d.month, d.day).isAfter(DateTime(a.year, a.month, a.day));
  }

  void _done() {
    final DateTime? d = parseExpiryMonth(_text.text);
    if (d == null) {
      setState(() => _error = 'Type the month and year, e.g. 08/28');
      return;
    }
    if (!_isAfterMfg(d)) {
      setState(() => _error = 'Expiry must be after the manufacture date');
      return;
    }
    Navigator.of(context).pop(d);
  }

  Future<void> _pickDay() async {
    final DateTime? a = widget.after;
    final DateTime first = a == null
        ? DateTime(2000)
        : DateTime(a.year, a.month, a.day).add(const Duration(days: 1));
    DateTime initial = widget.initial ??
        DateTime(DateTime.now().year + 1, DateTime.now().month, DateTime.now().day);
    if (initial.isBefore(first)) initial = first;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: DateTime(2100),
      helpText: 'Expiry date',
    );
    if (picked != null && mounted) Navigator.of(context).pop(picked);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Expiry (month / year)'),
      content: TextField(
        controller: _text,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.allow(RegExp(r'[0-9/]')),
          LengthLimitingTextInputFormatter(7),
          _SlashAfterMonth(),
        ],
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _done(),
        decoration: InputDecoration(
          hintText: 'MM/YY',
          helperText: 'As printed on the strip, e.g. 08/28',
          errorText: _error,
        ),
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: _pickDay, child: const Text('Pick a day')),
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        TextButton(onPressed: _done, child: const Text('OK')),
      ],
    );
  }
}

/// Puts the "/" after a two-digit month: "082" -> "08/2".
class _SlashAfterMonth extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final String t = newValue.text;
    if (!t.contains('/') && t.length >= 3) {
      final String withSlash = '${t.substring(0, 2)}/${t.substring(2)}';
      return TextEditingValue(
        text: withSlash,
        selection: TextSelection.collapsed(offset: withSlash.length),
      );
    }
    return newValue;
  }
}
