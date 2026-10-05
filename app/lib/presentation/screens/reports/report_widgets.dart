import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/report_export.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/ui_kit.dart';

/// Building blocks of the report sections. Charts are single-colour (brand
/// green on a pale track) and always print their numbers, so they read the
/// same in greyscale, on a monochrome printer and to a screen reader.

/// White rounded card, as the Reports overview uses.
class ReportCard extends StatelessWidget {
  const ReportCard({super.key, required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.border),
      ),
      padding: padding ?? const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: child,
    );
  }
}

/// Muted body text.
class ReportNote extends StatelessWidget {
  const ReportNote(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 12.5,
          height: 1.4,
          fontWeight: FontWeight.w500,
          color: AppColors.muted,
        ),
      );
}

/// Two [StatCard]s side by side.
class StatPair extends StatelessWidget {
  const StatPair(this.left, this.right, {super.key});
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(child: left),
          const SizedBox(width: 12),
          Expanded(child: right),
        ],
      );
}

/// A labelled horizontal bar with its value written out. A negative value
/// (a loss) draws as an outline instead of a fill.
class ValueBar extends StatelessWidget {
  const ValueBar({
    super.key,
    required this.label,
    required this.value,
    required this.fraction,
    this.detail,
    this.negative = false,
  });

  final String label;
  final String value;

  /// 0..1 of the bar's width.
  final double fraction;

  /// A second line under the label (e.g. "12 units · 23.4% margin").
  final String? detail;
  final bool negative;

  @override
  Widget build(BuildContext context) {
    final double f = fraction.isNaN ? 0 : fraction.clamp(0.0, 1.0);
    return Semantics(
      container: true,
      label: '$label: $value${detail == null ? '' : ', $detail'}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.green,
                  ),
                ),
              ],
            ),
            if (detail != null) ...<Widget>[
              const SizedBox(height: 2),
              Text(
                detail!,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted,
                ),
              ),
            ],
            const SizedBox(height: 7),
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints c) => Container(
                height: 10,
                decoration: BoxDecoration(
                  color: AppColors.canvas,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: c.maxWidth * f,
                    height: 10,
                    decoration: BoxDecoration(
                      color: negative ? null : AppColors.green,
                      border: negative
                          ? Border.all(color: AppColors.green, width: 1.5)
                          : null,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One column of [ColumnChart].
class ChartColumn {
  const ChartColumn(this.label, this.total, this.part);

  /// Under the column (e.g. the day of the month).
  final String label;

  /// Full height (e.g. revenue) and the dark part of it (e.g. profit).
  final int total;
  final int part;
}

/// Small column chart: each column's full height is [ChartColumn.total] on
/// a pale shade, with [ChartColumn.part] filled dark from the bottom. The
/// numbers are in the table below it; screen readers get [semanticLabel].
class ColumnChart extends StatelessWidget {
  const ColumnChart({
    super.key,
    required this.columns,
    required this.semanticLabel,
    this.height = 120,
  });

  final List<ChartColumn> columns;
  final String semanticLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final int max = columns.fold(
        0, (int m, ChartColumn c) => math.max(m, math.max(c.total, c.part)));
    // Label every column when there is room, else about every fifth one.
    final int every = columns.length <= 10 ? 1 : (columns.length / 6).ceil();
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: Column(
        children: <Widget>[
          SizedBox(
            height: height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                for (final ChartColumn c in columns)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: Stack(
                        alignment: Alignment.bottomCenter,
                        children: <Widget>[
                          _bar(max == 0 ? 0 : c.total / max, AppColors.page),
                          _bar(max == 0 ? 0 : math.max(0, c.part) / max,
                              AppColors.green),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              for (int i = 0; i < columns.length; i++)
                Expanded(
                  child: Text(
                    i % every == 0 ? columns[i].label : '',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    softWrap: false,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bar(double f, Color color) => FractionallySizedBox(
        heightFactor: f.clamp(0.0, 1.0),
        widthFactor: 1,
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
          ),
        ),
      );
}

/// A legend swatch + text, for [ColumnChart].
class LegendItem extends StatelessWidget {
  const LegendItem({super.key, required this.color, required this.text});
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(child: ReportNote(text)),
        ],
      );
}

/// A centred message: offline, nothing yet, or an error, with an optional
/// action button.
class ReportMessage extends StatelessWidget {
  const ReportMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: <Widget>[
          Icon(icon, size: 36, color: AppColors.muted),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              height: 1.45,
              fontWeight: FontWeight.w500,
              color: AppColors.muted,
            ),
          ),
          if (actionLabel != null) ...<Widget>[
            const SizedBox(height: 16),
            SecondaryButton(
              label: actionLabel!,
              icon: Icons.refresh,
              expand: false,
              onPressed: onAction,
            ),
          ],
        ],
      ),
    );
  }
}

/// "Export PDF" and "Export CSV" for a report section.
class ExportRow extends StatelessWidget {
  const ExportRow({super.key, required this.doc});

  /// Null while the report is loading (buttons disabled).
  final ReportDoc? doc;

  @override
  Widget build(BuildContext context) {
    final ReportDoc? d = doc;
    Future<void> run(Future<void> Function(ReportDoc) export) async {
      if (d == null) return;
      try {
        await export(d);
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not export the report.')));
      }
    }

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: <Widget>[
        SecondaryButton(
          label: 'Export PDF',
          icon: Icons.picture_as_pdf_outlined,
          expand: false,
          onPressed: d == null ? null : () => run(ReportExport.sharePdf),
        ),
        SecondaryButton(
          label: 'Export CSV',
          icon: Icons.table_chart_outlined,
          expand: false,
          onPressed: d == null ? null : () => run(ReportExport.shareCsv),
        ),
      ],
    );
  }
}

/// One batch line: name and batch on the left, figures on the right, and
/// an optional trailing action.
class BatchLine extends StatelessWidget {
  const BatchLine({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    this.valueDetail,
    this.action,
  });

  final String title;
  final String subtitle;
  final String value;
  final String? valueDetail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: MergeSemantics(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        ReportNote(subtitle),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Text(
                        value,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                      if (valueDetail != null) ReportNote(valueDetail!),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (action != null) ...<Widget>[
            const SizedBox(width: 4),
            action!,
          ],
        ],
      ),
    );
  }
}
