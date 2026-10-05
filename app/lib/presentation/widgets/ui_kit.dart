import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Shared UI kit for the Meddata redesign. Every screen composes these pieces
/// so spacing, radii, colors and weights stay consistent with the design
/// handoff. Nothing here holds state or talks to providers.

/// Gives a small control a touch area of at least 48x48dp (the Android and
/// Material minimum) without changing how it looks: [child] sits in a
/// transparent box that answers taps too. For screen readers the box is one
/// button named [label]; with [tooltip] the label also shows on long-press
/// or mouse hover (use it for icon-only controls).
class TapTarget extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Widget child;
  final bool tooltip;
  final bool? selected;

  /// Where [child] sits in the box when it is smaller than 48dp.
  final AlignmentGeometry alignment;

  const TapTarget({
    super.key,
    required this.label,
    required this.onTap,
    required this.child,
    this.tooltip = true,
    this.selected,
    this.alignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    Widget target = GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: kMinInteractiveDimension,
          minHeight: kMinInteractiveDimension,
        ),
        child: Align(
          alignment: alignment,
          widthFactor: 1,
          heightFactor: 1,
          child: child,
        ),
      ),
    );
    if (tooltip) {
      target =
          Tooltip(message: label, excludeFromSemantics: true, child: target);
    }
    return Semantics(
      container: true,
      button: true,
      enabled: onTap != null,
      selected: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: target,
    );
  }
}

/// A small rounded status label, e.g. "In stock" / "Low" / "Expiring".
/// Screen readers read [semanticsLabel] (default [text]), so a short label
/// can be spoken in full, e.g. "Low" as "Low stock".
class StatusPill extends StatelessWidget {
  final String text;
  final Color color;
  final Color bg;
  final String? semanticsLabel;

  const StatusPill({
    super.key,
    required this.text,
    required this.color,
    required this.bg,
    this.semanticsLabel,
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
    semanticsLabel: text == 'Low' ? 'Low stock' : null,
  );

  factory StatusPill.danger(String text, {String? semanticsLabel}) =>
      StatusPill(
        text: text,
        color: AppColors.statusRed,
        bg: AppColors.statusRedBg,
        semanticsLabel: semanticsLabel,
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
        semanticsLabel: semanticsLabel,
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

/// The Meddata logo as used on the website (images/meddata_logo.png),
/// cropped to its artwork.
class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 26});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/brand_mark.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
    );
  }
}

/// A square initials avatar (green glyph on a canvas tint), used on tiles.
/// Decorative: screen readers skip it (the name is read from the tile).
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
    return ExcludeSemantics(
      child: Container(
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
                        // Wraps the quantity under the status when large
                        // text leaves no room beside it.
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: <Widget>[
                            ?status,
                            if (qtyLabel != null)
                              Text(
                                qtyLabel!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.muted,
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
    // Soft, accent-tinted border (design: amber #F3D9C6 / red #F4CCCE), i.e. the
    // status hue blended lightly over the white card. No left stripe.
    final Color softBorder =
        Color.alphaBlend(color.withValues(alpha: 0.30), AppColors.card);
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
            border: Border.all(color: softBorder),
          ),
          padding: const EdgeInsets.all(15),
          // Read as "Low on stock: 3" rather than "3, Low on stock".
          child: Semantics(
            label: '$label: $count',
            excludeSemantics: true,
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
      ),
    );
  }
}

/// A section title row with an optional trailing action (e.g. "See all").
/// With an action the row is 48dp tall (the action's touch area), so place
/// it with ~14dp less space above and below than a plain title.
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
          TapTarget(
            label: actionLabel!,
            tooltip: false,
            onTap: onAction,
            alignment: Alignment.centerRight,
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
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final Color labelColor = isDark ? AppColors.onDarkMuted : AppColors.muted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 7, left: 2),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: labelColor,
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
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
          decoration: InputDecoration(hintText: hint, suffixIcon: suffixIcon),
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
    final ButtonStyle? style = expand
        ? null
        : ElevatedButton.styleFrom(minimumSize: const Size(0, 54));
    final Widget button = icon == null
        ? ElevatedButton(onPressed: onPressed, style: style, child: Text(label))
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
    final ButtonStyle? style = expand
        ? null
        : OutlinedButton.styleFrom(minimumSize: const Size(0, 54));
    final Widget button = icon == null
        ? OutlinedButton(onPressed: onPressed, style: style, child: Text(label))
        : OutlinedButton.icon(
            onPressed: onPressed,
            style: style,
            icon: Icon(icon, size: 20),
            label: Text(label),
          );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}
