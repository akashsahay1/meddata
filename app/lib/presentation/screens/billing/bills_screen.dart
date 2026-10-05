import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/inr.dart';
import '../../../data/models/bill.dart';
import '../../../services/auth_service.dart';
import '../../../services/billing_api.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/ui_kit.dart';
import 'bill_detail_screen.dart';
import 'billing_widgets.dart';
import 'new_bill_screen.dart';

enum _Range { today, yesterday, week, month, custom }

/// The Bills tab: bills of a day or date range from the server (newest
/// first) with their total, a search, and "New bill". Opening a bill gives
/// reprint / share / cancel.
class BillsScreen extends StatefulWidget {
  const BillsScreen({super.key, this.active = true, this.api});

  /// Whether the tab is showing; it refreshes each time it becomes active.
  final bool active;
  final BillingApi? api;

  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> {
  // A 401 (the server no longer accepts the login) signs out, as elsewhere.
  late final BillingApi _api = (widget.api ?? BillingApi())
    ..onUnauthorized = context.read<AuthService>().sessionRejected;
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();
  Timer? _debounce;

  _Range _range = _Range.today;
  DateTimeRange? _custom;
  final List<BillSummary> _bills = <BillSummary>[];
  BillPage? _page;
  bool _loading = false;
  ApiOutcome<BillPage>? _failure;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
    if (widget.active) WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void didUpdateWidget(BillsScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _refresh();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  DateTimeRange _dates() {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    return switch (_range) {
      _Range.today => DateTimeRange(start: today, end: today),
      _Range.yesterday => DateTimeRange(
          start: today.subtract(const Duration(days: 1)), end: today.subtract(const Duration(days: 1))),
      _Range.week => DateTimeRange(start: today.subtract(const Duration(days: 6)), end: today),
      _Range.month => DateTimeRange(start: DateTime(today.year, today.month), end: today),
      _Range.custom => _custom ?? DateTimeRange(start: today, end: today),
    };
  }

  Future<void> _refresh() => _load(page: 1);

  Future<void> _load({required int page}) async {
    final String? token = context.read<AuthService>().token;
    if (token == null) return;
    final int request = ++_request;
    setState(() {
      _loading = true;
      if (page == 1) _failure = null;
    });
    final DateTimeRange d = _dates();
    final ApiOutcome<BillPage> r =
        await _api.list(token, from: d.start, to: d.end, query: _search.text, page: page);
    if (!mounted || request != _request) return;
    setState(() {
      _loading = false;
      if (!r.isOk) {
        if (page == 1) {
          _failure = r;
          _bills.clear();
          _page = null;
        }
        return;
      }
      _failure = null;
      _page = r.value;
      if (page == 1) _bills.clear();
      _bills.addAll(r.value!.bills);
    });
  }

  void _maybeLoadMore() {
    final BillPage? p = _page;
    if (p == null || !p.hasMore || _loading) return;
    if (_scroll.position.extentAfter < 400) _load(page: p.currentPage + 1);
  }

  void _setRange(_Range r) {
    setState(() => _range = r);
    _refresh();
  }

  Future<void> _pickDates() async {
    final DateTime now = DateTime.now();
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: _custom ?? _dates(),
    );
    if (picked == null) return;
    setState(() {
      _custom = picked;
      _range = _Range.custom;
    });
    _refresh();
  }

  void _onSearch(String _) {
    setState(() {}); // the clear button
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _refresh);
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) _refresh();
  }

  String _rangeLabel() {
    final DateTimeRange d = _dates();
    final DateFormat f = DateFormat('dd MMM');
    return d.start == d.end ? DateFormat('dd MMM yyyy').format(d.start) : '${f.format(d.start)} - ${f.format(d.end)}';
  }

  @override
  Widget build(BuildContext context) {
    final double bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 4),
              child: Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      'Bills',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _open(const NewBillScreen()),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    icon: const Icon(Icons.add, size: 20),
                    label: const Text('New bill'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
              child: TextField(
                controller: _search,
                onChanged: _onSearch,
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.ink),
                decoration: InputDecoration(
                  hintText: 'Search invoice no., customer or phone',
                  prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.muted),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _search.clear();
                            _refresh();
                          },
                        ),
                ),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
              child: Row(
                children: <Widget>[
                  for (final (_Range r, String label) in <(_Range, String)>[
                    (_Range.today, 'Today'),
                    (_Range.yesterday, 'Yesterday'),
                    (_Range.week, 'Last 7 days'),
                    (_Range.month, 'This month'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: PillChoice(label: label, selected: _range == r, onTap: () => _setRange(r)),
                    ),
                  PillChoice(
                    label: _range == _Range.custom ? _rangeLabel() : 'Pick dates',
                    icon: Icons.date_range,
                    selected: _range == _Range.custom,
                    onTap: _pickDates,
                  ),
                ],
              ),
            ),
            Expanded(
              child: _failure != null
                  ? BillingOfflineNotice(
                      onRetry: _refresh,
                      offline: _failure!.isOffline,
                      message: _failure!.message,
                    )
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      child: ListView(
                        controller: _scroll,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(18, 8, 18, 32 + bottom),
                        children: <Widget>[
                          _summary(),
                          const SizedBox(height: 12),
                          if (_page != null && _bills.isEmpty) _empty(),
                          for (final BillSummary b in _bills)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _BillTile(
                                bill: b,
                                onTap: () => _open(BillDetailScreen(billId: b.id)),
                              ),
                            ),
                          if (_loading)
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(child: CircularProgressIndicator()),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summary() {
    final BillPage? p = _page;
    return Row(
      children: <Widget>[
        Expanded(
          child: StatCard(
            label: _rangeLabel(),
            value: p == null ? '-' : Inr.format(p.finalTotalPaise),
            sub: p == null
                ? null
                : '${p.finalCount} ${p.finalCount == 1 ? 'bill' : 'bills'}'
                    '${p.cancelledCount > 0 ? ' · ${p.cancelledCount} cancelled' : ''}',
            subColor: AppColors.statusGreen,
          ),
        ),
      ],
    );
  }

  Widget _empty() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: <Widget>[
          Icon(Icons.receipt_long_outlined, size: 52, color: AppColors.muted),
          SizedBox(height: 12),
          Text('No bills here yet',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.ink)),
          SizedBox(height: 6),
          Text('Tap New bill to make one.', style: TextStyle(color: AppColors.muted)),
        ],
      ),
    );
  }
}

class _BillTile extends StatelessWidget {
  const _BillTile({required this.bill, required this.onTap});

  final BillSummary bill;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String when = bill.createdAt == null
        ? DateFormat('dd MMM').format(bill.billDate)
        : DateFormat('dd MMM, hh:mm a').format(bill.createdAt!);
    final String who = bill.customerName ?? bill.customerPhone ?? 'Walk-in';
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(bill.invoiceNo,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.ink)),
                    const SizedBox(height: 2),
                    Text(
                      '$when · $who · ${bill.itemsCount} ${bill.itemsCount == 1 ? 'item' : 'items'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    Inr.format(bill.totalPaise),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: bill.isCancelled ? AppColors.muted : AppColors.ink,
                      decoration: bill.isCancelled ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (bill.isCancelled)
                    StatusPill.danger('Cancelled')
                  else if (bill.paymentMode == PaymentMode.credit)
                    StatusPill.low('Credit')
                  else
                    Text(bill.paymentMode.label,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.muted)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
