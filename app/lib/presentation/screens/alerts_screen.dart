import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../data/models/medicine.dart';
import '../../domain/medicine_status.dart';
import '../../domain/product_stock.dart';
import '../../state/medicine_provider.dart';
import '../../theme/app_theme.dart';
import '../widgets/status_chip.dart';
import 'medicine_detail_screen.dart';
import 'product_detail_screen.dart';

import '../widgets/adaptive_layout.dart';
import '../widgets/desktop_kit.dart';

/// Soft border tints from the design handoff (not part of the core palette:
/// a low-alpha version of each status hue used only for the alert tile edges).
const Color _redBorder = Color(0xFFF4CCCE);
const Color _amberBorder = Color(0xFFF3D9C6);

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final MedicineProvider mp = context.watch<MedicineProvider>();

    // Expiry alerts: batches that still have stock. Low stock: one entry
    // per medicine (its total across batches), shown via its next batch.
    final List<Medicine> expired = mp.expiredBatches;
    final List<Medicine> expiring = mp.expiringBatches;
    final List<Medicine> low = <Medicine>[
      for (final ProductStock p in mp.lowStockProducts)
        p.inStock.isNotEmpty ? p.inStock.first : p.first,
    ];

    final bool empty = expired.isEmpty && expiring.isEmpty && low.isEmpty;

    if (AdaptiveLayout.isDesktop(context) && !empty) {
      // Wide window: the three kinds of alert side by side, each scrolling
      // on its own.
      Widget column(String title, Color dot, Color chip, List<Medicine> items, _AlertKind kind) =>
          Expanded(
            child: deskSurface(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                children: <Widget>[
                  _AlertSection(
                    title: title,
                    dotColor: dot,
                    chipBg: chip,
                    items: items,
                    mp: mp,
                    kind: kind,
                  ),
                ],
              ),
            ),
          );
      return Scaffold(
        backgroundColor: AppColors.canvas,
        body: Padding(
          padding: const EdgeInsets.fromLTRB(kDeskGutter, 28, kDeskGutter, kDeskGutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const _Header(),
              const SizedBox(height: 20),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    column('Expired', AppColors.statusRed, AppColors.statusRedBg, expired,
                        _AlertKind.expiry),
                    const SizedBox(width: 16),
                    column('Expiring soon', AppColors.statusRed, AppColors.statusRedBg,
                        expiring, _AlertKind.expiry),
                    const SizedBox(width: 16),
                    column('Low on stock', AppColors.statusAmber, AppColors.statusAmberBg, low,
                        _AlertKind.lowStock),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: empty
            ? const Column(
                children: <Widget>[
                  Padding(
                    padding: EdgeInsets.fromLTRB(18, 8, 18, 0),
                    child: _Header(),
                  ),
                  Expanded(child: _EmptyState()),
                ],
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 120),
                children: <Widget>[
                  const _Header(),
                  const SizedBox(height: 16),
                  if (expired.isNotEmpty)
                    _AlertSection(
                      title: 'Expired',
                      dotColor: AppColors.statusRed,
                      chipBg: AppColors.statusRedBg,
                      items: expired,
                      mp: mp,
                      kind: _AlertKind.expiry,
                    ),
                  if (expiring.isNotEmpty)
                    _AlertSection(
                      title: 'Expiring soon',
                      dotColor: AppColors.statusRed,
                      chipBg: AppColors.statusRedBg,
                      items: expiring,
                      mp: mp,
                      kind: _AlertKind.expiry,
                    ),
                  if (low.isNotEmpty)
                    _AlertSection(
                      title: 'Low on stock',
                      dotColor: AppColors.statusAmber,
                      chipBg: AppColors.statusAmberBg,
                      items: low,
                      mp: mp,
                      kind: _AlertKind.lowStock,
                    ),
                ],
              ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final Widget title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Alerts',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          'Items that need restocking or attention',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.muted,
          ),
        ),
      ],
    );
    // Opened from Home (a page or a desktop window over it): a way back.
    // As a tab of the main shell there is nothing to go back to.
    if (!Navigator.of(context).canPop()) return title;
    return Row(
      children: <Widget>[
        IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back, color: AppColors.ink),
        ),
        const SizedBox(width: 4),
        Expanded(child: title),
      ],
    );
  }
}

enum _AlertKind { expiry, lowStock }

class _AlertSection extends StatelessWidget {
  final String title;
  final Color dotColor;
  final Color chipBg;
  final List<Medicine> items;
  final MedicineProvider mp;
  final _AlertKind kind;

  const _AlertSection({
    required this.title,
    required this.dotColor,
    required this.chipBg,
    required this.items,
    required this.mp,
    required this.kind,
  });

  @override
  Widget build(BuildContext context) {
    final bool isExpiry = kind == _AlertKind.expiry;
    final Color accent = dotColor;
    final Color borderColor = isExpiry ? _redBorder : _amberBorder;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Section header: colored dot, title, count pill.
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 12),
          child: Row(
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: chipBg,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Text(
                  '${items.length}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Nothing here right now.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.muted,
              ),
            ),
          ),
        for (int i = 0; i < items.length; i++) ...<Widget>[
          _alertTile(context, items[i], accent, borderColor),
          if (i != items.length - 1) const SizedBox(height: 10),
        ],
        const SizedBox(height: 22),
      ],
    );
  }

  Widget _alertTile(
    BuildContext context,
    Medicine m,
    Color accent,
    Color borderColor,
  ) {
    final MedicineStatus s = mp.statusOf(m);
    final String? subtitle;
    final String priceLabel;
    final String expLabel;

    if (kind == _AlertKind.expiry) {
      subtitle = m.batchNo.isNotEmpty
          ? '${m.quantity} ${m.unit} · Batch ${m.batchNo}'
          : '${m.quantity} ${m.unit}';
      priceLabel = 'Exp ${Fmt.dateShort(m.expiryDate)}';
      expLabel = _daysLabel(s);
    } else {
      subtitle = m.brand.isNotEmpty
          ? m.brand
          : (m.category.isNotEmpty ? m.category : null);
      final int total = mp.productById(m.productId)?.totalQty ?? m.quantity;
      priceLabel = '$total left';
      expLabel = 'min ${m.lowStockThreshold}';
    }

    return MedicineTile(
      name: m.name,
      subtitle: subtitle,
      avatarColor: accent,
      avatarBg: accent.withValues(alpha: 0.12),
      borderColor: borderColor,
      priceLabel: priceLabel,
      expLabel: expLabel,
      onTap: () => Navigator.of(context).push(
        AdaptiveLayout.route<void>(context, 
          builder: (_) => kind == _AlertKind.lowStock
              ? ProductDetailScreen(productId: m.productId)
              : MedicineDetailScreen(medicineId: m.id),
        ),
      ),
    );
  }

  String _daysLabel(MedicineStatus s) {
    if (s.isExpired) {
      final int d = -s.daysToExpiry;
      if (d <= 0) return 'Today';
      return d == 1 ? '1 day ago' : '$d days ago';
    }
    if (s.daysToExpiry <= 0) return 'Today';
    return s.daysToExpiry == 1 ? '1 day left' : '${s.daysToExpiry} days left';
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.statusGreenBg,
                borderRadius: BorderRadius.circular(AppRadii.cardLg),
              ),
              child: const Icon(
                Icons.check_circle_outline,
                size: 36,
                color: AppColors.statusGreen,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'All good',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Nothing is expiring, expired or low on stock right now.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
