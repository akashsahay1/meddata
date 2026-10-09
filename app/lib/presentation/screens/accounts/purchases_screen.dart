import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/inr.dart';
import '../../../data/models/accounting.dart';
import '../../../services/accounting_api.dart';
import '../../../services/auth_service.dart';
import '../../../services/billing_api.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/ui_kit.dart';
import '../invoice_scan_screen.dart';
import 'accounts_widgets.dart';
import 'purchase_detail_screen.dart';

enum _Range { month, quarter, year, all }

/// Supplier bills entered (by scanning them on the Add medicine screen),
/// newest first, with the total for the period.
class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({super.key, this.api});

  final AccountingApi? api;

  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  late final AccountingApi _api = (widget.api ?? AccountingApi())
    ..onUnauthorized = context.read<AuthService>().sessionRejected;
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();
  Timer? _debounce;
  _Range _range = _Range.month;
  final List<PurchaseSummary> _rows = <PurchaseSummary>[];
  ApiPage<PurchaseSummary>? _page;
  ApiOutcome<ApiPage<PurchaseSummary>>? _failure;
  bool _loading = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final ApiPage<PurchaseSummary>? p = _page;
      if (p != null && p.hasMore && !_loading && _scroll.position.extentAfter < 400) _load(page: p.currentPage + 1);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  DateTime? get _from {
    final DateTime now = DateTime.now();
    return switch (_range) {
      _Range.month => DateTime(now.year, now.month),
      _Range.quarter => DateTime(now.year, now.month - 2),
      _Range.year => DateTime(now.month >= 4 ? now.year : now.year - 1, 4),
      _Range.all => null,
    };
  }

  Future<void> _load({int page = 1}) async {
    final String? token = context.read<AuthService>().token;
    if (token == null) {
      setState(() => _failure = const ApiOutcome<ApiPage<PurchaseSummary>>.failed(401, 'Please log in again.'));
      return;
    }
    final int request = ++_request;
    setState(() => _loading = true);
    final ApiOutcome<ApiPage<PurchaseSummary>> r =
        await _api.purchases(token, from: _from, query: _search.text, page: page);
    if (!mounted || request != _request) return;
    setState(() {
      _loading = false;
      if (!r.isOk) {
        if (page == 1) {
          _failure = r;
          _rows.clear();
          _page = null;
        }
        return;
      }
      _failure = null;
      _page = r.value;
      if (page == 1) _rows.clear();
      _rows.addAll(r.value!.items);
    });
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute<Object?>(builder: (_) => screen));
    if (mounted) _load();
  }

  /// Type the bill in, or scan a photo / PDF of it.
  Future<void> _addBill() async {
    final bool? manual = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.card,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.keyboard_outlined),
              title: const Text('Type the bill'),
              subtitle: const Text('Enter each medicine as printed on the bill'),
              onTap: () => Navigator.of(ctx).pop(true),
            ),
            ListTile(
              leading: const Icon(Icons.document_scanner_outlined),
              title: const Text('Scan a photo or PDF'),
              subtitle: const Text('Meddata reads it; you check every item'),
              onTap: () => Navigator.of(ctx).pop(false),
            ),
          ],
        ),
      ),
    );
    if (manual == null || !mounted) return;
    await _open(manual ? const InvoiceScanScreen.manual() : const InvoiceScanScreen());
  }

  @override
  Widget build(BuildContext context) {
    final ApiPage<PurchaseSummary>? p = _page;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('Purchases')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addBill,
        foregroundColor: AppColors.ink,
        icon: const Icon(Icons.add),
        label: const Text('Add supplier bill'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _search,
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 350), _load);
              },
              decoration: const InputDecoration(
                hintText: 'Search supplier or invoice no.',
                prefixIcon: Icon(Icons.search, size: 20, color: AppColors.muted),
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(
              children: <Widget>[
                for (final (_Range r, String label) in <(_Range, String)>[
                  (_Range.month, 'This month'),
                  (_Range.quarter, 'Last 3 months'),
                  (_Range.year, 'This financial year'),
                  (_Range.all, 'All'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: AccountsPill(
                      label: label,
                      selected: _range == r,
                      onTap: () {
                        setState(() => _range = r);
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _failure != null
                ? AccountsOfflineNotice(onRetry: _load, offline: _failure!.isOffline, message: _failure!.message)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      controller: _scroll,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 96 + MediaQuery.paddingOf(context).bottom),
                      children: <Widget>[
                        StatCard(
                          label: 'Purchases',
                          value: p == null ? '-' : Inr.format(p.totalPaise),
                          sub: p == null ? null : '${p.count} ${p.count == 1 ? 'bill' : 'bills'}',
                        ),
                        const SizedBox(height: 12),
                        if (p != null && _rows.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 32),
                            child: Text(
                              'No purchases here yet. Add a supplier bill - type it in or scan it - and choose the supplier to record it.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.muted),
                            ),
                          ),
                        for (final PurchaseSummary s in _rows)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Material(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(AppRadii.card),
                              child: ListTile(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppRadii.card),
                                  side: const BorderSide(color: AppColors.border),
                                ),
                                onTap: () => _open(PurchaseDetailScreen(purchaseId: s.id, api: _api)),
                                title: Text(s.supplierName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink)),
                                subtitle: Text(
                                  '${s.invoiceNo} · ${DateFormat('dd MMM yyyy').format(s.invoiceDate)} · '
                                  '${s.itemsCount} ${s.itemsCount == 1 ? 'item' : 'items'}',
                                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: <Widget>[
                                    Text(Inr.format(s.totalPaise),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: s.cancelled ? AppColors.muted : AppColors.ink,
                                          decoration: s.cancelled ? TextDecoration.lineThrough : null,
                                        )),
                                    if (s.cancelled) StatusPill.danger('Cancelled'),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        if (_loading)
                          const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
