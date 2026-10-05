import 'package:flutter/material.dart';

import '../../../core/inr.dart';
import '../../../data/models/bill.dart';
import '../../../theme/app_theme.dart';

/// Billing needs the server: shown instead of a billing screen when the
/// device is offline (inventory keeps working offline).
class BillingOfflineNotice extends StatelessWidget {
  const BillingOfflineNotice({
    super.key,
    required this.onRetry,
    this.offline = true,
    this.message,
  });

  final VoidCallback onRetry;

  /// False: the server answered with an error ([message]) rather than the
  /// device being offline.
  final bool offline;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(AppRadii.cardLg),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: AppColors.statusAmberBg,
                    borderRadius: BorderRadius.circular(AppRadii.card),
                  ),
                  child: Icon(offline ? Icons.cloud_off : Icons.sync_problem,
                      size: 28, color: AppColors.statusAmber),
                ),
                const SizedBox(height: 18),
                Text(
                  offline ? 'Billing needs internet' : "Couldn't reach Meddata",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  offline
                      ? 'Bills are numbered and checked on the server, so they '
                          'can only be made online. Inventory keeps working '
                          'offline.'
                      : (message ?? 'Please try again in a moment.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh, size: 20),
                    label: const Text('Try again'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A label / amount row in a totals breakdown.
class AmountRow extends StatelessWidget {
  const AmountRow(this.label, this.value, {super.key, this.strong = false, this.big = false});

  final String label;
  final String value;
  final bool strong;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final TextStyle style = TextStyle(
      fontSize: big ? 20 : 13.5,
      fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
      color: strong ? AppColors.ink : AppColors.muted,
      letterSpacing: big ? -0.3 : 0,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: style)),
          Text(value, style: style.copyWith(color: AppColors.ink)),
        ],
      ),
    );
  }
}

/// "-₹1.25" / "+₹0.50" for discounts and round-off.
String signedInr(int paise) =>
    '${paise < 0 ? '-' : '+'}${Inr.format(paise.abs())}';

/// A white rounded card used by the billing screens.
class BillingCard extends StatelessWidget {
  const BillingCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

/// Small uppercase section label.
class BillingSectionLabel extends StatelessWidget {
  const BillingSectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: AppColors.muted,
          ),
        ),
      );
}

/// Pill-shaped choice chip matching the Inventory filters.
class PillChoice extends StatelessWidget {
  const PillChoice({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

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
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? AppColors.green : AppColors.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? AppColors.green : AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 16, color: selected ? Colors.white : AppColors.muted),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData paymentIcon(PaymentMode m) => switch (m) {
      PaymentMode.cash => Icons.payments_outlined,
      PaymentMode.upi => Icons.qr_code_2,
      PaymentMode.card => Icons.credit_card,
      PaymentMode.credit => Icons.menu_book_outlined,
    };
