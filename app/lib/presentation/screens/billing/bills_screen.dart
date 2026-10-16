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

import '../../widgets/adaptive_layout.dart';
import '../../widgets/desktop_kit.dart';

/// [pending]: every bill with money still to be paid, whatever its date.
enum _Range { today, yesterday, week, month, custom, pending }

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
      _Range.custom || _Range.pending => _custom ?? DateTimeRange(start: today, end: today),
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
    final bool pending = _range == _Range.pending;
    final ApiOutcome<BillPage> r = await _api.list(token,
        from: pending ? null : d.start,
        to: pending ? null : d.end,
        due: pending,
        query: _search.text,
        page: page);
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
    await Navigator.of(context).push(AdaptiveLayout.route<void>(context,
      maxWidth: screen is NewBillScreen
          ? AdaptiveLayout.contentMaxWidth
          : AdaptiveLayout.desktopPageMaxWidth,
      builder: (_) => screen,
    ));
    if (mounted) _refresh();
  }

  String _rangeLabel() {
    if (_range == _Range.pending) return 'All bills with money due';
    final DateTimeRange d = _dates();
    final DateFormat f = DateFormat('dd MMM');
    return d.start == d.end ? DateFormat('dd MMM yyyy').format(d.start) : '${f.format(d.start)} - ${f.format(d.end)}';
  }

  Widget _searchField() => TextField(
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
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _search.clear();
                    _refresh();
                  },
                ),
        ),
      );

  Widget _rangeChips() => Row(
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
          const SizedBox(width: 8),
          PillChoice(
            label: 'Pending',
            icon: Icons.hourglass_bottom,
            selected: _range == _Range.pending,
            onTap: () => _setRange(_Range.pending),
          ),
        ],
      );

  Widget _newBillButton() => ElevatedButton.icon(
        onPressed: () => _open(const NewBillScreen()),
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        icon: const Icon(Icons.add, size: 20),
        label: const Text('New bill'),
      );

  /// Wide window: the period's totals as three cards, then the bills as a
  /// table (more load as it scrolls).
  Widget _desktop() {
    final BillPage? p = _page;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(kDeskGutter, 28, kDeskGutter, kDeskGutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            DeskPageHeader(
              title: 'Bills',
              subtitle: _rangeLabel(),
              actions: <Widget>[_newBillButton()],
            ),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                SizedBox(width: 420, child: _searchField()),
                const SizedBox(width: 16),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: _rangeChips(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_failure != null)
              Expanded(
                child: BillingOfflineNotice(
                  onRetry: _refresh,
                  offline: _failure!.isOffline,
                  message: _failure!.message,
                ),
              )
            else ...<Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: StatCard(
                      label: 'Sales',
                      value: p == null ? '-' : Inr.format(p.finalTotalPaise),
                      sub: _range == _Range.pending ? 'all dates' : _rangeLabel(),
                      subColor: AppColors.statusGreen,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: StatCard(
                      label: 'Bills',
                      value: p == null ? '-' : '${p.finalCount}',
                      sub: 'not counting cancelled',
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: StatCard(
                      label: 'Cancelled',
                      value: p == null ? '-' : '${p.cancelledCount}',
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: StatCard(
                      label: 'Balance due',
                      value: p == null ? '-' : Inr.format(p.duePaise),
                      sub: p == null ? null : _dueSub(p),
                      subColor: p != null && p.dueCount > 0 ? AppColors.statusRed : AppColors.muted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _page != null && _bills.isEmpty
                    ? _empty()
                    : DeskTable(
                        controller: _scroll,
                        columns: const <DeskColumn>[
                          DeskColumn('Invoice no.', flex: 3),
                          DeskColumn('Date & time', flex: 3),
                          DeskColumn('Customer', flex: 3),
                          DeskColumn.end('Items', flex: 1),
                          DeskColumn('Payment', flex: 2),
                          DeskColumn.end('Amount', flex: 2),
                        ],
                        rowCount: _bills.length,
                        onTap: (int i) => _open(BillDetailScreen(billId: _bills[i].id)),
                        cells: (int i) => _BillTile.cells(_bills[i]),
                        footer: _loading
                            ? const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(child: CircularProgressIndicator()),
                              )
                            : null,
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (AdaptiveLayout.isDesktop(context)) return _desktop();
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
                  _newBillButton(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
              child: _searchField(),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
              child: _rangeChips(),
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
    if (_range == _Range.pending) {
      return StatCard(
        label: 'Balance due',
        value: p == null ? '-' : Inr.format(p.duePaise),
        sub: p == null ? null : _dueSub(p),
        subColor: AppColors.statusRed,
      );
    }
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
        if (p != null && p.dueCount > 0) ...<Widget>[
          const SizedBox(width: 10),
          Expanded(
            child: StatCard(
              label: 'Balance due',
              value: Inr.format(p.duePaise),
              sub: _dueSub(p),
              subColor: AppColors.statusRed,
            ),
          ),
        ],
      ],
    );
  }

  String _dueSub(BillPage p) => '${p.dueCount} ${p.dueCount == 1 ? 'bill' : 'bills'} to be paid';

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

  static String _when(BillSummary bill) => bill.createdAt == null
      ? DateFormat('dd MMM').format(bill.billDate)
      : DateFormat('dd MMM, hh:mm a').format(bill.createdAt!);

  static String _who(BillSummary bill) =>
      bill.customerName ?? bill.customerPhone ?? 'Walk-in';

  static Widget _payment(BillSummary bill) {
    if (bill.isCancelled) return StatusPill.danger('Cancelled');
    if (bill.hasBalance) return StatusPill.low('Due ${Inr.format(bill.balancePaise)}');
    if (bill.paymentMode == PaymentMode.credit) return StatusPill.inStock('Paid');
    return Text(bill.paymentMode.label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.muted));
  }

  /// One desktop table row: invoice, date, customer, items, payment, amount.
  static List<Widget> cells(BillSummary bill) => <Widget>[
        DeskCell(bill.invoiceNo, strong: true),
        DeskCell(_when(bill)),
        DeskCell(_who(bill),
            sub: bill.customerName != null && bill.customerPhone != null
                ? bill.customerPhone
                : null),
        DeskCell('${bill.itemsCount}', align: TextAlign.end),
        _payment(bill),
        Text(
          Inr.format(bill.totalPaise),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: bill.isCancelled ? AppColors.muted : AppColors.ink,
            decoration: bill.isCancelled ? TextDecoration.lineThrough : null,
          ),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final String when = _when(bill);
    final String who = _who(bill);
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
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
                  if (bill.isCancelled || bill.paymentMode == PaymentMode.credit)
                    _payment(bill)
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
