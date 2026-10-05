import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../domain/medicine_status.dart';
import '../../domain/product_stock.dart';
import '../../state/medicine_provider.dart';
import '../../theme/app_theme.dart';
import '../widgets/status_chip.dart';
import '../widgets/sync_badge.dart';
import 'barcode_lookup.dart';
import 'product_detail_screen.dart';

/// The Inventory tab: a title, a search field and a scrollable list of
/// medicines rendered as [MedicineTile]. Reads from the shared
/// [MedicineProvider] (same query/filter as the rest of the app).
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Keep the field in sync with any existing provider query.
    final MedicineProvider mp = context.read<MedicineProvider>();
    _search.text = mp.query;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _openProduct(ProductStock p) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProductDetailScreen(productId: p.productId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final MedicineProvider mp = context.watch<MedicineProvider>();
    final List<ProductStock> items = mp.visibleProducts;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            // The title row and the chips are 48dp tall (touch areas of the
            // sync badge and the chips); the gaps around them are trimmed to
            // match, so everything sits where the design puts it.
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 1.5, 18, 4.5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Inventory',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      SyncBadge(),
                    ],
                  ),
                  const SizedBox(height: 5.5),
                  TextField(
                    controller: _search,
                    onChanged: mp.setQuery,
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.ink,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search medicines',
                      prefixIcon: const Icon(Icons.search,
                          size: 20, color: AppColors.muted),
                      suffixIcon: mp.query.isEmpty
                          ? IconButton(
                              tooltip: 'Scan barcode',
                              icon: const Icon(Icons.qr_code_scanner,
                                  size: 20, color: AppColors.muted),
                              onPressed: () => scanAndOpen(context),
                            )
                          : IconButton(
                              tooltip: 'Clear search',
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () {
                                _search.clear();
                                mp.setQuery('');
                              },
                            ),
                    ),
                  ),
                  const SizedBox(height: 6.5),
                  _FilterChips(mp: mp),
                ],
              ),
            ),
            Expanded(
              child: mp.loading
                  ? const Center(child: CircularProgressIndicator())
                  : items.isEmpty
                      ? _EmptyInventory(
                          hasAny: mp.productCount > 0,
                          filtered: mp.filter != MedicineFilter.all,
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(18, 6, 18, 120),
                          itemCount: items.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (BuildContext context, int i) {
                            final ProductStock p = items[i];
                            final MedicineStatus s = MedicineStatus(
                              expiryState: p.worstExpiry(mp.warningDays),
                              daysToExpiry: 0,
                              isLowStock: p.isLowStock,
                            );
                            final List<String> subParts = <String>[
                              if (p.brand.isNotEmpty) p.brand,
                              if (p.category.isNotEmpty) p.category,
                              if (p.batches.length > 1) '${p.batches.length} batches',
                            ];
                            return MedicineTile(
                              name: p.name,
                              subtitle: subParts.join(' · '),
                              status: medicineStatusPill(s, p.totalQty),
                              qtyLabel: '${p.totalQty} ${p.unit}',
                              priceLabel: p.currentMrp > 0
                                  ? Fmt.money(p.currentMrp)
                                  : null,
                              expLabel: 'Exp ${Fmt.dateShort(p.nearestExpiry)}',
                              onTap: () => _openProduct(p),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Quick status filters (All / Low stock / Expiring soon / Expired) with
/// counts; combines with the search query via [MedicineProvider.setFilter].
class _FilterChips extends StatelessWidget {
  final MedicineProvider mp;
  const _FilterChips({required this.mp});

  @override
  Widget build(BuildContext context) {
    final List<(MedicineFilter, String, int, Color)> options =
        <(MedicineFilter, String, int, Color)>[
      (MedicineFilter.all, 'All', mp.productCount, AppColors.green),
      (MedicineFilter.lowStock, 'Low stock', mp.lowStockCount,
          AppColors.statusAmber),
      (MedicineFilter.expiring, 'Expiring soon', mp.productsExpiringCount,
          AppColors.statusRed),
      (MedicineFilter.expired, 'Expired', mp.productsExpiredCount,
          AppColors.statusRed),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (final (MedicineFilter f, String label, int count, Color c)
              in options)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _chip(f, label, count, c),
            ),
        ],
      ),
    );
  }

  Widget _chip(MedicineFilter f, String label, int count, Color accent) {
    final bool selected = mp.filter == f;
    void select() => mp.setFilter(f);
    // Read as "Low stock, 3"; the chip is 48dp tall to touch.
    return TapTarget(
      label: '$label, $count',
      tooltip: false,
      selected: selected,
      onTap: select,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: select,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? accent : AppColors.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? accent : AppColors.border),
          ),
          child: Text(
            '$label · $count',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : AppColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyInventory extends StatelessWidget {
  final bool hasAny;
  final bool filtered;
  const _EmptyInventory({required this.hasAny, this.filtered = false});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              hasAny ? Icons.search_off : Icons.inventory_2_outlined,
              size: 56,
              color: AppColors.muted,
            ),
            const SizedBox(height: 16),
            Text(
              hasAny ? 'No medicines match' : 'No medicines yet',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasAny
                  ? (filtered
                      ? 'Try a different search or filter.'
                      : 'Try a different search.')
                  : 'Tap the + button to add your first item.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
