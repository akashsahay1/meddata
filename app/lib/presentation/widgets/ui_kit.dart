import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Shared UI kit for the Meddata redesign. Every screen composes these pieces
/// so spacing, radii, colors and weights stay consistent with the design
/// handoff. Nothing here holds state or talks to providers.

/// A small rounded status label, e.g. "In stock" / "Low" / "Expiring".
class StatusPill extends StatelessWidget {
  final String text;
  final Color color;
  final Color bg;

  const StatusPill({
    super.key,
    required this.text,
    required this.color,
    required this.bg,
  });

  /// Convenience constructors for the three canonical states.
  factory StatusPill.inStock([String text = 'In stock']) => StatusPill(
        text: text,
        color: AppColors.statusGreen,
        bg: AppColors.statusGreenBg,
      );

  factory StatusPill.low([String text = 'Low']) => StatusPill(
        text: text,
        color: AppColors.statusAmber,
        bg: AppColors.statusAmberBg,
      );

  factory StatusPill.danger(String text) => StatusPill(
        text: text,
        color: AppColors.statusRed,
        bg: AppColors.statusRedBg,
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          height: 1.1,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// The orange plus/cross inside a green rounded square: the Meddata brand mark.
class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 26});

  @override
  Widget build(BuildContext context) {
    // Proportions mirror the design: square radius ~30%, arm thickness ~23%,
    // arm length ~46% of the mark.
    final double radius = size * 0.30;
    final double arm = size * 0.46;
    final double thick = size * 0.23;
    final double barRadius = thick * 0.35;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.green,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Center(
        child: SizedBox(
          width: arm,
          height: arm,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Container(
                width: thick,
                height: arm,
                decoration: BoxDecoration(
                  color: AppColors.orange,
                  borderRadius: BorderRadius.circular(barRadius),
                ),
              ),
              Container(
                width: arm,
                height: thick,
                decoration: BoxDecoration(
                  color: AppColors.orange,
                  borderRadius: BorderRadius.circular(barRadius),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A square initials avatar (green glyph on a canvas tint), used on tiles.
class InitialsAvatar extends StatelessWidget {
  final String text;
  final double size;
  final Color color;
  final Color bg;

  const InitialsAvatar({
    super.key,
    required this.text,
    this.size = 44,
    this.color = AppColors.green,
    this.bg = AppColors.canvas,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: size * 0.36,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

/// Derive up to two initials from a medicine (or any) name.
String initialsOf(String name) {
  final List<String> parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((String p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    final String p = parts.first;
    return (p.length >= 2 ? p.substring(0, 2) : p).toUpperCase();
  }
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

/// A medicine row card matching the Inventory design: initials avatar, name,
/// a `brand · category` subline, an optional status pill + quantity, and a
/// right-aligned price + expiry. All secondary fields are optional so the tile
/// works on the dashboard, inventory and alerts screens.
class MedicineTile extends StatelessWidget {
  final String name;
  final String? subtitle;
  final String? initials;
  final StatusPill? status;
  final String? qtyLabel;
  final String? priceLabel;
  final String? expLabel;
  final Color avatarColor;
  final Color avatarBg;
  final Color borderColor;
  final VoidCallback? onTap;

  const MedicineTile({
    super.key,
    required this.name,
    this.subtitle,
    this.initials,
    this.status,
    this.qtyLabel,
    this.priceLabel,
    this.expLabel,
    this.avatarColor = AppColors.green,
    this.avatarBg = AppColors.canvas,
    this.borderColor = AppColors.border,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasStatusRow = status != null || qtyLabel != null;
    final bool hasTrailing = priceLabel != null || expLabel != null;

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(color: borderColor),
          ),
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              InitialsAvatar(
                text: initials ?? initialsOf(name),
                color: avatarColor,
                bg: avatarBg,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    if (hasStatusRow)
                      Padding(
                        padding: const EdgeInsets.only(top: 7),
                        child: Row(
                          children: <Widget>[
                            ?status,
                            if (status != null && qtyLabel != null)
                              const SizedBox(width: 10),
                            if (qtyLabel != null)
                              Flexible(
                                child: Text(
                                  qtyLabel!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (hasTrailing) ...<Widget>[
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    if (priceLabel != null)
                      Text(
                        priceLabel!,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                    if (expLabel != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          expLabel!,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A white rounded stat card for the dashboard (label, big value, small sub).
class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final Color subColor;
  final VoidCallback? onTap;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.sub,
    this.subColor = AppColors.muted,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Widget content = Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x140A302E),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: AppColors.ink,
            ),
          ),
          if (sub != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              sub!,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: subColor,
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: content,
    );
  }
}

/// A tappable alert card with a colored left border, an icon chip, a big count
/// and a label. Used for "Low on stock" / "Expiring soon".
class AlertCard extends StatelessWidget {
  final IconData icon;
  final int count;
  final String label;
  final Color color;
  final Color bg;
  final VoidCallback? onTap;

  const AlertCard({
    super.key,
    required this.icon,
    required this.count,
    required this.label,
    required this.color,
    required this.bg,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border(
              left: BorderSide(color: color, width: 3),
              top: BorderSide(color: AppColors.border),
              right: BorderSide(color: AppColors.border),
              bottom: BorderSide(color: AppColors.border),
            ),
          ),
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(icon, size: 18, color: color),
                  ),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A section title row with an optional trailing action (e.g. "See all").
class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
            color: AppColors.ink,
          ),
        ),
        if (actionLabel != null)
          GestureDetector(
            onTap: onAction,
            behavior: HitTestBehavior.opaque,
            child: Text(
              actionLabel!,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.green,
              ),
            ),
          ),
      ],
    );
  }
}

/// A muted 12px label above a themed text field.
class LabeledField extends StatelessWidget {
  final String label;
  final String? hint;
  final TextEditingController? controller;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final Widget? suffixIcon;

  const LabeledField({
    super.key,
    required this.label,
    this.hint,
    this.controller,
    this.keyboardType,
    this.validator,
    this.maxLines = 1,
    this.onChanged,
    this.enabled = true,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 7, left: 2),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.muted,
            ),
          ),
        ),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          maxLines: maxLines,
          onChanged: onChanged,
          enabled: enabled,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
          decoration: InputDecoration(
            hintText: hint,
            suffixIcon: suffixIcon,
          ),
        ),
      ],
    );
  }
}

/// Orange filled primary button (theme-styled), width-filling by default.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;

  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expand = true,
  });

  @override
  Widget build(BuildContext context) {
    final ButtonStyle? style =
        expand ? null : ElevatedButton.styleFrom(minimumSize: const Size(0, 54));
    final Widget button = icon == null
        ? ElevatedButton(
            onPressed: onPressed,
            style: style,
            child: Text(label),
          )
        : ElevatedButton.icon(
            onPressed: onPressed,
            style: style,
            icon: Icon(icon, size: 20),
            label: Text(label),
          );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Outlined secondary button (theme-styled), width-filling by default.
class SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;

  const SecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expand = true,
  });

  @override
  Widget build(BuildContext context) {
    final ButtonStyle? style =
        expand ? null : OutlinedButton.styleFrom(minimumSize: const Size(0, 54));
    final Widget button = icon == null
        ? OutlinedButton(
            onPressed: onPressed,
            style: style,
            child: Text(label),
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            style: style,
            icon: Icon(icon, size: 20),
            label: Text(label),
          );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}
