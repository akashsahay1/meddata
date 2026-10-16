import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Building blocks for the wide-window (Windows PC) layouts: a page header,
/// white panels and a data table with column headings. Phones keep the card
/// lists from ui_kit.dart; these are used only when
/// [AdaptiveLayout.isDesktop] is true.

/// Space around desktop page content.
const double kDeskGutter = 32;

/// Page title row: title (and a smaller line under it) on the left, the
/// page's main actions on the right.
class DeskPageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  /// Shown before the title, e.g. a Back button.
  final Widget? leading;

  const DeskPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const <Widget>[],
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        if (leading != null) ...<Widget>[leading!, const SizedBox(width: 8)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: AppColors.ink,
                ),
              ),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ],
          ),
        ),
        for (int i = 0; i < actions.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 12),
          actions[i],
        ],
      ],
    );
  }
}

/// A white rounded panel surface. A [Material], so row hover and click
/// highlights inside it show.
Widget deskSurface({required Widget child}) => Material(
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );

/// A white rounded panel with an optional title row.
class DeskPanel extends StatelessWidget {
  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const DeskPanel({
    super.key,
    this.title,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 16),
  });

  @override
  Widget build(BuildContext context) {
    return deskSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      title!,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  ?trailing,
                  if (trailing == null) const SizedBox(height: 48),
                ],
              ),
            ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

/// One column of a [DeskTable].
class DeskColumn {
  final String label;
  final int flex;
  final Alignment align;

  const DeskColumn(this.label, {this.flex = 1, this.align = Alignment.centerLeft});

  const DeskColumn.end(this.label, {this.flex = 1}) : align = Alignment.centerRight;
}

/// A table in a white panel: column headings, then one row per item. A row
/// highlights under the mouse and opens with a click. With [shrinkWrap] the
/// rows are laid out in place (inside another scroll view); otherwise the
/// table fills its height and scrolls its rows.
class DeskTable extends StatelessWidget {
  final List<DeskColumn> columns;
  final int rowCount;
  final List<Widget> Function(int index) cells;
  final void Function(int index)? onTap;

  /// Screen-reader name of a row (it is read as one button).
  final String Function(int index)? rowLabel;
  final ScrollController? controller;
  final bool shrinkWrap;

  /// Shown under the last row (e.g. a loading spinner).
  final Widget? footer;

  const DeskTable({
    super.key,
    required this.columns,
    required this.rowCount,
    required this.cells,
    this.onTap,
    this.rowLabel,
    this.controller,
    this.shrinkWrap = false,
    this.footer,
  });

  Widget _line(List<Widget> children) => Row(
        children: <Widget>[
          for (int c = 0; c < columns.length; c++) ...<Widget>[
            // A left-aligned column after a right-aligned one (an amount)
            // would sit right against it: give it more room.
            if (c > 0)
              SizedBox(
                width: columns[c - 1].align == Alignment.centerRight &&
                        columns[c].align != Alignment.centerRight
                    ? 40
                    : 16,
              ),
            Expanded(
              flex: columns[c].flex,
              child: Align(alignment: columns[c].align, child: children[c]),
            ),
          ],
        ],
      );

  Widget _row(int i) {
    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 36),
        child: _line(cells(i)),
      ),
    );
    final Widget row = onTap == null
        ? content
        : InkWell(
            onTap: () => onTap!(i),
            hoverColor: AppColors.canvas,
            child: content,
          );
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: rowLabel == null
          ? row
          : MergeSemantics(
              child: Semantics(button: onTap != null, label: rowLabel!(i), child: row),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget head = Container(
      color: const Color(0xFFF6F8F8),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: _line(<Widget>[
        for (final DeskColumn c in columns)
          Text(
            c.label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: AppColors.muted,
            ),
          ),
      ]),
    );
    final Widget body = shrinkWrap
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int i = 0; i < rowCount; i++) _row(i),
              ?footer,
            ],
          )
        : ListView.builder(
            controller: controller,
            padding: EdgeInsets.zero,
            itemCount: rowCount + (footer == null ? 0 : 1),
            itemBuilder: (BuildContext context, int i) =>
                i < rowCount ? _row(i) : footer!,
          );
    return deskSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
        children: <Widget>[
          head,
          const Divider(height: 1, thickness: 1, color: AppColors.border),
          if (shrinkWrap) body else Expanded(child: body),
        ],
      ),
    );
  }
}

/// Table cell text: [strong] for the main value of a row, otherwise muted.
class DeskCell extends StatelessWidget {
  final String text;
  final bool strong;
  final String? sub;
  final TextAlign align;

  const DeskCell(this.text, {super.key, this.strong = false, this.sub, this.align = TextAlign.start});

  @override
  Widget build(BuildContext context) {
    final Widget main = Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: align,
      style: TextStyle(
        fontSize: 14,
        fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
        color: strong ? AppColors.ink : AppColors.muted,
      ),
    );
    if (sub == null) return main;
    return Column(
      crossAxisAlignment: align == TextAlign.end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        main,
        const SizedBox(height: 2),
        Text(
          sub!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: align,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.muted),
        ),
      ],
    );
  }
}
