import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/inr.dart';
import '../../../domain/accounting.dart';
import '../../../theme/app_theme.dart';

/// Orange buttons carry ink text: white on the brand orange is below the
/// 4.5:1 contrast needed for normal text.
final ButtonStyle inkOnOrange = ElevatedButton.styleFrom(foregroundColor: AppColors.ink);

/// Shown instead of an accounts screen when the server can't be reached
/// (accounts are kept on the server, like bills; inventory works offline).
class AccountsOfflineNotice extends StatelessWidget {
  const AccountsOfflineNotice({super.key, required this.onRetry, this.offline = true, this.message});

  final VoidCallback onRetry;
  final bool offline;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(offline ? Icons.cloud_off : Icons.sync_problem, size: 40, color: AppColors.statusAmber),
              const SizedBox(height: 14),
              Text(
                offline ? 'Accounts need internet' : "Couldn't reach Meddata",
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.ink),
              ),
              const SizedBox(height: 8),
              Text(
                offline
                    ? 'Parties, purchases, payments and GST reports are kept on the '
                        'server, so they need a connection. Inventory keeps working offline.'
                    : (message ?? 'Please try again in a moment.'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, height: 1.45, color: AppColors.muted),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: inkOnOrange,
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 20),
                  label: const Text('Try again'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A pill-shaped choice, 48dp tall (the touch-target minimum).
class AccountsPill extends StatelessWidget {
  const AccountsPill({super.key, required this.label, required this.selected, required this.onTap, this.icon});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.green : AppColors.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: selected ? AppColors.green : AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 16, color: selected ? Colors.white : AppColors.muted),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A balance in words, coloured: to collect (amber), to pay (red), settled (green).
class BalanceLabel extends StatelessWidget {
  const BalanceLabel(this.paise, {super.key, this.big = false});

  final int paise;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final Color color = paise == 0
        ? AppColors.statusGreen
        : paise > 0
            ? const Color(0xFF9A5A0B)
            : const Color(0xFFB4262B);
    if (!big) {
      return Text(BalanceText.of(paise),
          textAlign: TextAlign.end,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: paise == 0 ? AppColors.muted : color));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(Inr.format(paise.abs()),
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: AppColors.ink)),
        Text(
          paise == 0 ? 'Settled' : (paise > 0 ? 'To collect from them' : 'To pay them'),
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: paise == 0 ? AppColors.muted : color),
        ),
      ],
    );
  }
}

/// "1,234.50" -> 123450 paise; null when not a positive amount.
int? parseRupees(String text) {
  final String t = text.trim().replaceAll(',', '').replaceAll('₹', '');
  if (t.isEmpty) return null;
  final double? v = double.tryParse(t);
  if (v == null || v < 0 || v > 1e9) return null;
  return (v * 100).round();
}

/// Digits and one decimal point.
final List<TextInputFormatter> rupeeInput = <TextInputFormatter>[
  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
];

final DateFormat dayFormat = DateFormat('dd MMM yyyy');

/// A label / value line in a details card.
class InfoLine extends StatelessWidget {
  const InfoLine(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(text, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
      );
}
