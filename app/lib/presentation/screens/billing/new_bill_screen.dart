import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/inr.dart';
import '../../../core/platform.dart';
import '../../../data/models/bill.dart';
import '../../../data/models/medicine.dart';
import '../../../data/repositories/billing_repository.dart';
import '../../../domain/fefo.dart';
import '../../../domain/gst.dart';
import '../../../domain/pack_size.dart';
import '../../../domain/product_stock.dart';
import '../../../data/models/accounting.dart';
import '../../../services/accounting_api.dart';
import '../../../services/auth_service.dart';
import '../../../services/billing_api.dart';
import '../../../state/bill_cart.dart';
import '../../../state/medicine_provider.dart';
import '../../../sync/sync_engine.dart';
import '../../../theme/app_theme.dart';
import '../accounts/accounts_widgets.dart' show parseRupees, rupeeInput;
import '../accounts/party_picker.dart';
import '../barcode_lookup.dart';
import 'bill_detail_screen.dart';
import 'billing_widgets.dart';
import 'shop_settings_screen.dart';
import '../../widgets/adaptive_layout.dart';
import '../../widgets/ui_kit.dart' show TapTarget;

enum _Gate { checking, ready, offline, failed }

/// Counter sale. Search or scan medicines; each one takes stock from its
/// earliest-expiring batch first (FEFO), spilling into the next batch, and
/// never from an expired one. Billing is online-only: the server re-checks
/// every price and the stock, works out the GST and numbers the invoice.
class NewBillScreen extends StatefulWidget {
  const NewBillScreen({super.key, this.api, this.repository, this.accountingApi, this.edit});

  final BillingApi? api;

  /// A bill to edit in place (same invoice number); pops with the edited
  /// [Bill] once saved.
  final Bill? edit;
  final BillingRepository? repository;

  /// For choosing the customer's account (tests replace it).
  final AccountingApi? accountingApi;

  @override
  State<NewBillScreen> createState() => _NewBillScreenState();
}

class _NewBillScreenState extends State<NewBillScreen> {
  // A 401 (the server no longer accepts the login) signs out, as elsewhere.
  late final BillingApi _api = (widget.api ?? BillingApi())
    ..onUnauthorized = context.read<AuthService>().sessionRejected;
  late final BillingRepository _repo = widget.repository ?? BillingRepository();
  late final BillCart _cart = BillCart(loadBatches: _repo.batchesOf);

  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _gstin = TextEditingController();
  final TextEditingController _address = TextEditingController();
  final TextEditingController _received = TextEditingController();

  _Gate _gate = _Gate.checking;
  String? _gateMessage;
  bool _submitting = false;
  bool _showCustomer = false;

  /// Bumped to rebuild the customer fields empty after the bill is cleared.
  int _formSeed = 0;

  @override
  void initState() {
    super.initState();
    _cart.addListener(_onCart);
    _search.addListener(_onCart);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOnline());
  }

  @override
  void dispose() {
    _cart
      ..removeListener(_onCart)
      ..dispose();
    for (final TextEditingController c in <TextEditingController>[
      _search, _name, _phone, _gstin, _address, _received,
    ]) {
      c.dispose();
    }
    _searchFocus.dispose();
    super.dispose();
  }

  void _onCart() {
    if (mounted) setState(() {});
  }

  /// Empty the bill and the customer fields (a new bill id too).
  void _clearBill() {
    _cart.reset();
    for (final TextEditingController c in <TextEditingController>[
      _search, _name, _phone, _gstin, _address, _received,
    ]) {
      c.clear();
    }
    setState(() {
      _formSeed++;
      _showCustomer = false;
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ---- customer account -------------------------------------------------------

  /// Choose the customer's account (or add one from what was typed): it
  /// fills in the customer fields; a credit bill needs one.
  Future<void> _chooseParty() async {
    final Party? p = await pickParty(
      context,
      suppliers: false,
      api: widget.accountingApi,
      name: _name.text.trim().isEmpty ? null : _name.text.trim(),
      phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      gstin: Gstin.normalize(_gstin.text).isEmpty ? null : Gstin.normalize(_gstin.text),
    );
    if (p == null || !mounted) return;
    _cart.setParty(p);
    _name.text = _cart.customerName;
    _phone.text = _cart.customerPhone;
    _gstin.text = _cart.customerGstin;
    _address.text = _cart.customerAddress;
    setState(() {
      _formSeed++;
      _showCustomer = true;
    });
  }

  void _clearParty() {
    _cart.setParty(null);
    setState(() {});
  }

  // ---- online check -----------------------------------------------------------

  /// Billing needs the server; load the shop's invoice details on the way.
  Future<void> _checkOnline() async {
    setState(() => _gate = _Gate.checking);
    final String? token = context.read<AuthService>().token;
    if (token == null) {
      setState(() {
        _gate = _Gate.failed;
        _gateMessage = 'Please log in again.';
      });
      return;
    }
    final ApiOutcome<ShopProfile> shop = await _api.shop(token);
    if (!mounted) return;
    if (!shop.isOk) {
      setState(() {
        _gate = shop.isOffline ? _Gate.offline : _Gate.failed;
        _gateMessage = shop.message;
      });
      return;
    }
    _cart.shop = shop.value;
    final Bill? edit = widget.edit;
    if (edit != null && _cart.editing == null) {
      await _cart.loadBill(edit);
      if (!mounted) return;
      _name.text = _cart.customerName;
      _phone.text = _cart.customerPhone;
      _gstin.text = _cart.customerGstin;
      _address.text = _cart.customerAddress;
      _received.text = _cart.receivedPaise == null ? '' : (_cart.receivedPaise! / 100).toStringAsFixed(2);
      _formSeed++;
      _showCustomer = _cart.party != null || _cart.customerName.isNotEmpty;
    }
    setState(() => _gate = _Gate.ready);
    // Send this device's pending changes now, so the server has them by
    // the time the bill is made.
    final SyncEngine sync = context.read<SyncEngine>();
    if (sync.pending > 0) unawaited(sync.syncNow());
  }

  // ---- adding medicines --------------------------------------------------------

  List<ProductStock> _matches(MedicineProvider mp) {
    final String q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return const <ProductStock>[];
    return mp.products
        .where((ProductStock p) =>
            p.name.toLowerCase().contains(q) ||
            p.brand.toLowerCase().contains(q) ||
            p.first.barcode.toLowerCase() == q)
        .take(8)
        .toList();
  }

  Future<void> _add(ProductStock p) async {
    final AddOutcome outcome = await _cart.addProduct(p.productId);
    if (!mounted) return;
    _search.clear();
    switch (outcome) {
      case AddOutcome.added:
        break;
      case AddOutcome.outOfStock:
        _toast('${p.name} is out of stock.');
      case AddOutcome.onlyExpired:
        _toast("Only expired stock of ${p.name} is left - it can't be sold.");
      case AddOutcome.notFound:
        _toast('${p.name} is no longer in your inventory.');
    }
    // Ready for the next scan / search.
    if (AppPlatform.isDesktop) _searchFocus.requestFocus();
  }

  /// Enter in the search field: a barcode (USB scanners end with Enter),
  /// else the only matching medicine.
  void _onSubmitted(String text) {
    final String code = text.trim();
    if (code.isEmpty) return;
    final MedicineProvider mp = context.read<MedicineProvider>();
    final ProductStock? byCode = mp.productByBarcode(code);
    if (byCode != null) {
      _add(byCode);
      return;
    }
    final List<ProductStock> found = _matches(mp);
    if (found.length == 1) {
      _add(found.first);
    } else if (found.isEmpty) {
      _toast('No medicine matches "$code".');
    }
  }

  Future<void> _scan() async {
    final String? code = await readBarcode(context);
    if (code == null || !mounted) return;
    final ProductStock? p = context.read<MedicineProvider>().productByBarcode(code);
    if (p == null) {
      _toast('No medicine with barcode $code in your inventory.');
      return;
    }
    await _add(p);
  }

  // ---- making the bill ----------------------------------------------------------

  Future<void> _submit() async {
    if (_received.text.trim().isNotEmpty && parseRupees(_received.text) == null) {
      _toast('Enter the amount received, or leave it empty if paid in full.');
      return;
    }
    final String? problem = _cart.problem();
    if (problem != null) {
      _toast(problem);
      return;
    }
    final AuthService auth = context.read<AuthService>();
    final String? token = auth.token;
    if (token == null) {
      _toast('Please log in again.');
      return;
    }
    setState(() => _submitting = true);
    final BillResult result;
    try {
      await _flushSync();
      if (!mounted) return;
      final Bill? editing = _cart.editing;
      result = editing == null
          ? await _api.create(token, _cart.requestBody(deviceId: auth.deviceId))
          : await _api.update(token, editing.id, _cart.requestBody(deviceId: auth.deviceId)..remove('id'));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
    if (!mounted) return;
    switch (result) {
      case BillCreated() when _cart.editing != null:
        await _edited(result);
      case BillCreated():
        await _created(result);
      // Refused: say why (the button is usable again behind the dialog).
      case BillPricesChanged():
        await _pricesChanged(result.lines);
      case BillStockShort():
        await _stockShort(result.lines);
      case BillBatchesUnavailable():
        await _unavailable(result.lines);
      case BillOffline():
        _toast("Couldn't reach the server, so the bill is not confirmed. "
            'Check the internet and tap Create bill again - it will not be made twice.');
      case BillFailed():
        _toast(result.message);
    }
  }

  /// Changes this device hasn't sent yet (e.g. a batch just added) go to
  /// the server first, so the bill can use them.
  Future<void> _flushSync() async {
    final SyncEngine sync = context.read<SyncEngine>();
    if (sync.pending == 0 && !_cart.hasUnsyncedBatches) return;
    await sync.syncNow();
    final DateTime until = DateTime.now().add(const Duration(seconds: 15));
    while (sync.status == SyncStatus.syncing && DateTime.now().isBefore(until)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    await _cart.refreshUnsynced();
  }

  Future<void> _created(BillCreated created) async {
    final MedicineProvider mp = context.read<MedicineProvider>();
    final SyncEngine sync = context.read<SyncEngine>();
    final NavigatorState nav = Navigator.of(context);
    // Empty at once (a new bill id), so the bill can't be sent twice.
    _clearBill();
    // Show the new stock now; the sync pull brings the sale movements.
    await _repo.applyServerStock(created.stock);
    await mp.load();
    unawaited(sync.syncNow());
    if (!mounted) return;
    final Object? next = await nav.push<Object>(AdaptiveLayout.route<Object>(context, 
      builder: (_) => BillDetailScreen(
          bill: created.bill, justCreated: true, alreadySaved: created.replayed),
    ));
    // Back from the bill returns to where billing started, unless the
    // user chose "New bill" (this screen, now empty).
    if (mounted && next != BillDetailScreen.newBill) nav.pop();
  }

  /// Saved an edit: the new stock now (the sync pull brings the
  /// movements), then back to the bill with its new contents.
  Future<void> _edited(BillCreated saved) async {
    final MedicineProvider mp = context.read<MedicineProvider>();
    final SyncEngine sync = context.read<SyncEngine>();
    final NavigatorState nav = Navigator.of(context);
    _cart.reset();
    await _repo.applyServerStock(saved.stock);
    await mp.load();
    unawaited(sync.syncNow());
    if (mounted) nav.pop(saved.bill);
  }

  Future<void> _pricesChanged(List<StalePrice> lines) async {
    unawaited(context.read<SyncEngine>().syncNow());
    final bool? accept = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Prices changed'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('The bill was not made. Since you added these, they '
                'were changed on another device:'),
            const SizedBox(height: 12),
            for (final StalePrice s in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  s.priceChanged
                      ? '${_batchName(s.name, s.batchNo)}: '
                          '${Inr.format(s.sentMrpPaise)} is now ${Inr.format(s.mrpPaise)}'
                      : '${_batchName(s.name, s.batchNo)}: batch details were updated '
                          '(price still ${Inr.format(s.mrpPaise)})',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Not now')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Use new prices')),
        ],
      ),
    );
    if (accept == true) {
      _cart.acceptPrices(lines);
      _toast('Prices updated. Check the total, then tap Create bill.');
    }
  }

  Future<void> _stockShort(List<StockShort> lines) async {
    unawaited(context.read<SyncEngine>().syncNow());
    _cart.applyStock(lines);
    await _info(
      'Not enough stock',
      'The bill was not made. Stock is lower than this device showed:',
      <String>[
        for (final StockShort s in lines)
          '${_batchName(s.name, s.batchNo)}: only ${s.available} left (bill needs ${s.requested})',
      ],
      footer: 'Quantities now use the stock that is left. Check the bill and try again.',
    );
  }

  Future<void> _unavailable(List<UnavailableBatch> lines) async {
    unawaited(context.read<SyncEngine>().syncNow());
    _cart.dropBatches(lines.map((UnavailableBatch u) => u.batchId));
    await _info(
      "Some batches can't be sold",
      'The bill was not made:',
      <String>[
        for (final UnavailableBatch u in lines)
          '${_batchName(u.name, u.batchNo)}: ${switch (u.reason) {
            'expired' => 'expired',
            'deleted' => 'deleted on another device',
            _ => 'no longer in your inventory',
          }}',
      ],
      footer: 'They were taken off this bill. Check it and try again.',
    );
  }

  Future<void> _info(String title, String intro, List<String> rows, {String? footer}) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(intro),
            const SizedBox(height: 12),
            for (final String r in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(r, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            if (footer != null) ...<Widget>[const SizedBox(height: 6), Text(footer)],
          ],
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
        ],
      ),
    );
  }

  static String _batchName(String name, String batchNo) =>
      batchNo.isEmpty ? name : '$name ($batchNo)';

  Future<void> _openShopSettings() async {
    await Navigator.of(context).push(
        AdaptiveLayout.route<void>(context, maxWidth: AdaptiveLayout.desktopFormMaxWidth,
builder: (_) => ShopSettingsScreen(api: _api)));
    if (mounted) await _reloadShop();
  }

  Future<void> _reloadShop() async {
    final String? token = context.read<AuthService>().token;
    if (token == null) return;
    final ApiOutcome<ShopProfile> shop = await _api.shop(token);
    if (shop.isOk && mounted) _cart.shop = shop.value;
  }

  Future<bool> _confirmDiscard() async =>
      await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: Text(widget.edit == null ? 'Discard this bill?' : 'Discard your changes?'),
          content: Text(widget.edit == null
              ? 'The medicines added to it will be removed.'
              : 'The bill stays as it was.'),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep')),
            TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Discard')),
          ],
        ),
      ) ??
      false;

  // ---- build ------------------------------------------------------------------------

  /// Wide windows (Windows PC, tablets): bill on the left, customer and
  /// totals on the right.
  bool get _wide => MediaQuery.sizeOf(context).width >= 900;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _cart.isEmpty || _gate != _Gate.ready,
      onPopInvokedWithResult: (bool didPop, Object? _) async {
        if (didPop || _submitting) return;
        final NavigatorState nav = Navigator.of(context);
        if (await _confirmDiscard()) {
          _clearBill();
          nav.pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: AppBar(
          title: Text(widget.edit == null ? 'New bill' : 'Edit ${widget.edit!.invoiceNo}',
              overflow: TextOverflow.ellipsis),
          actions: <Widget>[
            if (_gate == _Gate.ready && !_cart.isEmpty && widget.edit == null)
              IconButton(
                tooltip: 'Clear bill',
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: () async {
                  if (await _confirmDiscard()) _clearBill();
                },
              ),
            const SizedBox(width: 4),
          ],
        ),
        body: switch (_gate) {
          _Gate.checking => const Center(child: CircularProgressIndicator()),
          _Gate.offline => BillingOfflineNotice(onRetry: _checkOnline),
          _Gate.failed =>
            BillingOfflineNotice(onRetry: _checkOnline, offline: false, message: _gateMessage),
          _Gate.ready => _body(context),
        },
        // As the Scaffold's bar, snackbars float above it (not over the button).
        bottomNavigationBar: _gate == _Gate.ready && !_wide ? _bottomBar() : null,
      ),
    );
  }

  Widget _body(BuildContext context) {
    final MedicineProvider mp = context.watch<MedicineProvider>();
    final List<Widget> items = <Widget>[
      if (_cart.shop != null && !_cart.shop!.invoiceReady) _shopBanner(),
      _searchField(),
      ..._results(mp),
      const BillingSectionLabel('Medicines on this bill'),
      if (_cart.isEmpty) _emptyCart() else ..._cartCards(),
    ];
    final List<Widget> side = <Widget>[
      _customerSection(),
      _paymentSection(),
      const BillingSectionLabel('Total'),
      _totalsCard(),
    ];
    if (!_wide) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: <Widget>[...items, ...side],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 32),
            children: items,
          ),
        ),
        SizedBox(
          width: 380,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 20, 32),
            children: <Widget>[...side, const SizedBox(height: 16), _createButton()],
          ),
        ),
      ],
    );
  }

  Widget _shopBanner() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.statusAmberBg,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          borderRadius: BorderRadius.circular(AppRadii.card),
          onTap: _openShopSettings,
          child: const Padding(
            padding: EdgeInsets.all(14),
            child: Row(
              children: <Widget>[
                Icon(Icons.storefront_outlined, size: 20, color: AppColors.primaryDark),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Add your shop's GSTIN, state and address so bills print as tax invoices.",
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink),
                  ),
                ),
                SizedBox(width: 8),
                Icon(Icons.chevron_right, color: AppColors.primaryDark),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _search,
      focusNode: _searchFocus,
      autofocus: AppPlatform.isDesktop,
      textInputAction: TextInputAction.search,
      onSubmitted: _onSubmitted,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink),
      decoration: InputDecoration(
        hintText: AppPlatform.supportsCamera
            ? 'Search medicine or scan barcode'
            : 'Search medicine or scan with USB scanner',
        prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.muted),
        suffixIcon: _search.text.isNotEmpty
            ? IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close, size: 18),
                onPressed: _search.clear,
              )
            : AppPlatform.supportsCamera
                ? IconButton(
                    tooltip: 'Scan barcode',
                    icon: const Icon(Icons.qr_code_scanner, size: 20, color: AppColors.muted),
                    onPressed: _scan,
                  )
                : null,
      ),
    );
  }

  List<Widget> _results(MedicineProvider mp) {
    if (_search.text.trim().isEmpty) return const <Widget>[];
    final List<ProductStock> found = _matches(mp);
    if (found.isEmpty) {
      return const <Widget>[
        Padding(
          padding: EdgeInsets.fromLTRB(4, 12, 4, 0),
          child: Text('No medicine matches.', style: TextStyle(color: AppColors.muted)),
        ),
      ];
    }
    final DateTime today = DateTime.now();
    return <Widget>[
      const SizedBox(height: 8),
      // ListTiles need a Material to paint their ink on.
      Material(
        color: AppColors.card,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: const BorderSide(color: AppColors.border),
        ),
        child: Column(
          children: <Widget>[
            for (final ProductStock p in found) _resultTile(p, today),
          ],
        ),
      ),
    ];
  }

  Widget _resultTile(ProductStock p, DateTime today) {
    final List<Medicine> sellable = p.batches
        .where((Medicine m) =>
            m.quantity > 0 &&
            !DateTime(m.expiryDate.year, m.expiryDate.month, m.expiryDate.day)
                .isBefore(DateTime(today.year, today.month, today.day)))
        .toList();
    final int qty = sellable.fold(0, (int s, Medicine m) => s + m.quantity);
    final bool canSell = qty > 0;
    final int mrp = canSell ? (sellable.first.sellingPrice * 100).round() : 0;
    // With a pack size the MRP is the strip's, as printed on it.
    final String per = PackSize.applies(p.unit, p.packSize)
        ? '/${PackSize.packNoun(p.unit)}'
        : '';
    final String stock = canSell
        ? '${PackSize.stock(qty, p.unit, p.packSize)} · MRP ${Inr.format(mrp)}$per'
        : (p.totalQty > 0 ? 'Only expired stock' : 'Out of stock');
    return ListTile(
      enabled: canSell,
      onTap: () => _add(p),
      title: Text(p.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      subtitle: Text(
        <String>[if (p.brand.isNotEmpty) p.brand, stock].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: canSell ? AppColors.muted : AppColors.statusRed),
      ),
      trailing: Icon(Icons.add_circle_outline,
          color: canSell ? AppColors.navy : AppColors.border),
    );
  }

  Widget _emptyCart() {
    return const BillingCard(
      child: Row(
        children: <Widget>[
          Icon(Icons.receipt_long_outlined, color: AppColors.muted),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Search or scan to add medicines. Stock is taken from the batch '
              'that expires first.',
              style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _cartCards() {
    final List<CartLine> lines = _cart.lines;
    return <Widget>[
      for (final CartItem item in _cart.items)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _CartItemCard(
            key: ObjectKey(item),
            cart: _cart,
            item: item,
            lines: lines.where((CartLine l) => identical(l.item, item)).toList(),
            onEditDiscount: () => _editDiscount(item),
            onChangeBatch: () => _changeBatch(item),
          ),
        ),
    ];
  }

  Future<void> _editDiscount(CartItem item) async {
    final String? v = await _numberDialog(
      title: 'Discount % on MRP',
      initial: item.discountBp == 0 ? '' : Inr.percent(item.discountBp).replaceAll('%', ''),
      decimal: true,
      validate: (String v) => Inr.parsePercent(v) == null ? 'Enter 0 to 100' : null,
    );
    final int? bp = v == null ? null : Inr.parsePercent(v);
    if (bp != null) _cart.setDiscount(item, bp);
  }

  Future<String?> _numberDialog({
    required String title,
    required String initial,
    required bool decimal,
    required String? Function(String) validate,
  }) =>
      showDialog<String>(
        context: context,
        builder: (_) => _NumberDialog(
          title: title,
          initial: initial,
          decimal: decimal,
          validate: validate,
        ),
      );

  Future<void> _changeBatch(CartItem item) async {
    final DateTime today = _cart.today;
    final List<SaleBatch> batches = _cart.batchesOf(item);
    final DateFormat df = DateFormat('dd MMM yyyy');
    final Object? picked = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Text('Sell ${item.name} from',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              ListTile(
                leading: Icon(item.pinnedBatchId == null ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: AppColors.navy),
                title: const Text('Earliest expiry first (automatic)'),
                onTap: () => Navigator.of(ctx).pop(''),
              ),
              for (final SaleBatch b in batches)
                Builder(builder: (BuildContext _) {
                  final bool expired = b.isExpiredOn(today);
                  final bool empty = b.qty <= 0;
                  final bool selectable = !expired && !empty;
                  return ListTile(
                    enabled: selectable,
                    leading: Icon(
                        item.pinnedBatchId == b.id ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: selectable ? AppColors.navy : AppColors.border),
                    title: Text(b.batchNo.isEmpty ? 'No batch no.' : 'Batch ${b.batchNo}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      expired
                          ? "Expired ${df.format(b.expiryDate)} - can't be sold"
                          : 'Exp ${df.format(b.expiryDate)} · MRP ${Inr.format(b.mrpPaise)} · '
                              '${empty ? 'no stock' : '${b.qty} in stock'}',
                      style: TextStyle(color: expired ? AppColors.statusRed : AppColors.muted),
                    ),
                    onTap: selectable ? () => Navigator.of(ctx).pop(b.id) : null,
                  );
                }),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (picked is String) _cart.pinBatch(item, picked.isEmpty ? null : picked);
  }

  Widget _customerSection() {
    final ShopProfile? shop = _cart.shop;
    final String gstin = Gstin.normalize(_gstin.text);
    final bool gstinBad = gstin.length == 15 && !Gstin.isValid(gstin);
    final String? pos = _cart.placeOfSupply;
    final bool hasAny = <String>[_name.text, _phone.text, _gstin.text, _address.text]
        .any((String v) => v.trim().isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const BillingSectionLabel('Customer'),
        BillingCard(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              InkWell(
                mouseCursor: WidgetStateMouseCursor.clickable,
                onTap: () => setState(() => _showCustomer = !_showCustomer),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.person_outline, size: 20, color: AppColors.navy),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          hasAny
                              ? <String>[_name.text.trim(), _phone.text.trim()]
                                  .where((String v) => v.isNotEmpty)
                                  .join(' · ')
                              : 'Walk-in customer (optional details)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
                        ),
                      ),
                      Icon(_showCustomer || hasAny ? Icons.expand_less : Icons.expand_more,
                          color: AppColors.muted),
                    ],
                  ),
                ),
              ),
              _partyRow(),
              if (_showCustomer || hasAny) ...<Widget>[
                const SizedBox(height: 6),
                TextField(
                  controller: _name,
                  maxLength: 100,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                      counterText: '',
                      labelText: 'Name'),
                  onChanged: (String v) => _cart.update(() => _cart.customerName = v),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _phone,
                  maxLength: 20,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                      counterText: '', labelText: 'Phone', helperText: 'To send the bill on WhatsApp'),
                  onChanged: (String v) => _cart.update(() => _cart.customerPhone = v),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _gstin,
                  maxLength: 15,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp('[0-9A-Za-z]')),
                    TextInputFormatter.withFunction((TextEditingValue _, TextEditingValue v) =>
                        v.copyWith(text: v.text.toUpperCase())),
                  ],
                  decoration: InputDecoration(
                    labelText: 'GSTIN (business customers)',
                    counterText: '',
                    errorText: gstinBad ? 'Not a valid GSTIN - check it' : null,
                  ),
                  onChanged: (String v) => _cart.update(() => _cart.customerGstin = v),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  mouseCursor: WidgetStateMouseCursor.clickable,
                  dropdownMenuItemMouseCursor: WidgetStateMouseCursor.clickable,
                  key: ValueKey<int>(_formSeed),
                  initialValue: _cart.customerStateCode,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Place of supply (state)'),
                  items: <DropdownMenuItem<String?>>[
                    DropdownMenuItem<String?>(
                      child: Text(Gstin.isValid(gstin)
                          ? "Customer's GSTIN state (${GstStates.label(gstin.substring(0, 2))})"
                          : shop?.stateCode != null
                              ? 'Same as shop (${GstStates.label(shop!.stateCode!)})'
                              : 'Same as shop'),
                    ),
                    for (final MapEntry<String, String> e in GstStates.all.entries)
                      DropdownMenuItem<String?>(value: e.key, child: Text('${e.key} - ${e.value}')),
                  ],
                  onChanged: (String? v) => _cart.update(() => _cart.customerStateCode = v),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _address,
                  minLines: 1,
                  maxLines: 3,
                  maxLength: 500,
                  decoration: const InputDecoration(labelText: 'Address', counterText: ''),
                  onChanged: (String v) => _cart.update(() => _cart.customerAddress = v),
                ),
                if (pos != null && shop?.stateCode != null) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(
                    _cart.isInterState
                        ? 'Inter-state sale to ${GstStates.label(pos)}: IGST'
                        : 'Sale within ${GstStates.label(pos)}: CGST + SGST',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.muted),
                  ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// The customer's account: chosen (with "Change" / clear) or a button to
  /// choose one; flagged when a credit bill still needs one.
  Widget _partyRow() {
    final Party? p = _cart.party;
    final bool needed = _cart.balance > 0 && p == null;
    if (p == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _chooseParty,
          style: TextButton.styleFrom(foregroundColor: needed ? AppColors.statusRed : null),
          icon: const Icon(Icons.badge_outlined, size: 18),
          label: Text(!needed
              ? 'Choose customer account'
              : _cart.paymentMode == PaymentMode.credit
                  ? 'Choose customer account (needed for credit)'
                  : 'Choose customer account (needed for the balance)'),
        ),
      );
    }
    return Row(
      children: <Widget>[
        const Icon(Icons.badge_outlined, size: 18, color: AppColors.navy),
        const SizedBox(width: 8),
        Expanded(
          child: Text('Account: ${p.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
        ),
        TextButton(onPressed: _chooseParty, child: const Text('Change')),
        IconButton(tooltip: 'Remove customer account', icon: const Icon(Icons.close, size: 18), onPressed: _clearParty),
      ],
    );
  }

  void _setPayment(PaymentMode m) => _cart.update(() {
        _cart.paymentMode = m;
        if (m == PaymentMode.credit) _showCustomer = true;
      });

  Widget _paymentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (_wide || _cart.paymentMode != PaymentMode.credit) const BillingSectionLabel('Payment'),
        // On a phone the payment choice sits in the bottom bar.
        if (_wide)
          Wrap(
            spacing: 8,
            // The pills' 48dp touch boxes already leave 8dp between rows.
            children: <Widget>[
              for (final PaymentMode m in PaymentMode.values)
                PillChoice(
                  label: m.label,
                  icon: paymentIcon(m),
                  selected: _cart.paymentMode == m,
                  onTap: () => _setPayment(m),
                ),
            ],
          ),
        if (_cart.paymentMode != PaymentMode.credit) ...<Widget>[
          if (_wide) const SizedBox(height: 12),
          TextField(
            controller: _received,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: rupeeInput,
            decoration: InputDecoration(
              labelText: 'Amount received (₹)',
              hintText: Inr.format(_cart.totals.totalPaise, symbol: false),
              helperText: _cart.balance > 0
                  ? '${Inr.format(_cart.balance)} goes on the customer’s account'
                  : 'Leave empty when paid in full',
              helperStyle: _cart.balance > 0
                  ? const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.ink)
                  : null,
            ),
            onChanged: (String v) {
              _cart.update(() => _cart.receivedPaise = v.trim().isEmpty ? null : parseRupees(v));
              if (_cart.balance > 0) setState(() => _showCustomer = true);
            },
          ),
        ],
      ],
    );
  }

  Widget _totalsCard() {
    final GstTotals t = _cart.totals;
    final bool registered = _cart.shop?.gstin != null;
    final int units = _cart.lines.fold(0, (int s, CartLine l) => s + l.qty);
    return BillingCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AmountRow('MRP value ($units ${units == 1 ? 'unit' : 'units'})', Inr.format(t.subtotalPaise)),
          if (t.discountPaise > 0) AmountRow('Discount', '-${Inr.format(t.discountPaise)}'),
          if (registered) ...<Widget>[
            AmountRow('Taxable value', Inr.format(t.taxablePaise)),
            if (_cart.isInterState)
              AmountRow('IGST', Inr.format(t.igstPaise))
            else ...<Widget>[
              AmountRow('CGST', Inr.format(t.cgstPaise)),
              AmountRow('SGST', Inr.format(t.sgstPaise)),
            ],
          ],
          if (t.roundOffPaise != 0) AmountRow('Round off', signedInr(t.roundOffPaise)),
          const Divider(height: 18),
          AmountRow('Total', Inr.format(t.totalPaise), strong: true, big: true),
          const SizedBox(height: 4),
          const Text(
            'Prices include GST. The server re-checks prices and stock when the bill is made.',
            style: TextStyle(fontSize: 11.5, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _createButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _submitting || _cart.isEmpty ? null : _submit,
        icon: _submitting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.ink),
              )
            : const Icon(Icons.receipt_long, size: 20),
        label: Text(widget.edit != null
            ? (_submitting ? 'Saving…' : 'Save changes')
            : (_submitting ? 'Creating bill…' : 'Create bill')),
      ),
    );
  }

  /// Phone: payment choice, the total with its GST, and Create bill, each
  /// on its own row so a lakh-rupee total never pushes the button off.
  Widget _bottomBar() {
    final GstTotals t = _cart.totals;
    final int n = _cart.items.length;
    const TextStyle small = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.muted);
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _PaySwitch(mode: _cart.paymentMode, onChanged: _setPayment),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Total', style: AppTheme.display(size: 15, weight: FontWeight.w700, color: AppColors.ink)),
                  Text('$n ${n == 1 ? 'medicine' : 'medicines'}', style: small),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(Inr.format(t.totalPaise),
                          style: AppTheme.display(size: 24, weight: FontWeight.w800, color: AppColors.ink)
                              .copyWith(fontFeatures: const <FontFeature>[FontFeature.tabularFigures()])),
                    ),
                    if (_cart.shop?.gstin != null)
                      Text('incl. GST ${Inr.format(t.cgstPaise + t.sgstPaise + t.igstPaise)}',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: small),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _createButton(),
        ],
      ),
    );
  }
}

/// Cash | UPI | Card | Credit as one full-width switch (phone bottom bar).
class _PaySwitch extends StatelessWidget {
  const _PaySwitch({required this.mode, required this.onChanged});

  final PaymentMode mode;
  final ValueChanged<PaymentMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: <Widget>[
          for (final PaymentMode m in PaymentMode.values)
            Expanded(
              child: TapTarget(
                label: m.label,
                tooltip: false,
                selected: m == mode,
                onTap: () => onChanged(m),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: m == mode ? AppColors.navy : null,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(m.label,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: m == mode ? Colors.white : AppColors.muted,
                      )),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One medicine on the bill: quantity, discount, and the batches it sells
/// from (FEFO) with their expiry and MRP.
class _CartItemCard extends StatefulWidget {
  const _CartItemCard({
    super.key,
    required this.cart,
    required this.item,
    required this.lines,
    required this.onEditDiscount,
    required this.onChangeBatch,
  });

  final BillCart cart;
  final CartItem item;
  final List<CartLine> lines;
  final VoidCallback onEditDiscount;
  final VoidCallback onChangeBatch;

  @override
  State<_CartItemCard> createState() => _CartItemCardState();
}

class _CartItemCardState extends State<_CartItemCard> {
  late final TextEditingController _qty = TextEditingController(text: '${item.qty}');
  final FocusNode _qtyFocus = FocusNode();

  BillCart get cart => widget.cart;
  CartItem get item => widget.item;
  List<CartLine> get lines => widget.lines;

  @override
  void initState() {
    super.initState();
    // Leaving the box empty (or 0) puts the bill's quantity back.
    _qtyFocus.addListener(() {
      if (!_qtyFocus.hasFocus) _showQty();
    });
  }

  @override
  void didUpdateWidget(_CartItemCard old) {
    super.didUpdateWidget(old);
    if (int.tryParse(_qty.text) != item.qty && !_qtyFocus.hasFocus) _showQty();
  }

  @override
  void dispose() {
    _qty.dispose();
    _qtyFocus.dispose();
    super.dispose();
  }

  void _showQty() => _qty.text = '${item.qty}';

  void _setQty(int qty) {
    _qty.text = '$qty';
    cart.setQty(item, qty);
  }

  @override
  Widget build(BuildContext context) {
    final FefoAllocation alloc = cart.allocation(item);
    final int amount = lines.fold(0, (int s, CartLine l) => s + l.gst.totalPaise);
    final int available = cart.available(item);
    final DateFormat exp = DateFormat('MM/yy');
    final int? rate = lines.isEmpty ? null : lines.first.gstRateBp;
    // The box takes tablets; − and + move a whole strip (to the next full
    // strip from a part strip). Without a pack size they move one.
    final bool packs = PackSize.applies(item.unit, item.packSize);
    final int step = PackSize.pricePack(item.unit, item.packSize);
    final int less = ((item.qty + step - 1) ~/ step - 1) * step;
    final int more = (item.qty ~/ step + 1) * step;
    final VoidCallback? onLess = less >= 1 ? () => _setQty(less) : null;
    final VoidCallback? onMore = more <= available ? () => _setQty(more) : null;
    final String noun = packs ? ' ${PackSize.packNoun(item.unit)}' : '';
    return BillingCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(item.name,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink)),
                    const SizedBox(height: 2),
                    Text(
                      <String>[
                        if (item.unit.isNotEmpty) item.unit,
                        if (rate != null) 'GST ${Inr.percent(rate)}',
                        if (item.discountBp > 0) '${Inr.percent(item.discountBp)} off',
                      ].join(' · '),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              Text(Inr.format(amount),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink)),
              IconButton(
                tooltip: 'Remove ${item.name}',
                icon: const Icon(Icons.close, size: 20, color: AppColors.muted),
                onPressed: () => cart.remove(item),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              _StepButton(icon: Icons.remove, tooltip: 'One$noun less', onPressed: onLess),
              const SizedBox(width: 6),
              SizedBox(
                width: 72,
                child: CallbackShortcuts(
                  bindings: <ShortcutActivator, VoidCallback>{
                    const SingleActivator(LogicalKeyboardKey.arrowUp): () => onMore?.call(),
                    const SingleActivator(LogicalKeyboardKey.arrowDown): () => onLess?.call(),
                  },
                  child: Semantics(
                    label: 'Quantity in ${item.unit.toLowerCase()}',
                    child: TextField(
                      controller: _qty,
                      focusNode: _qtyFocus,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(5),
                      ],
                      style: AppTheme.display(size: 17, weight: FontWeight.w800, color: AppColors.ink),
                      decoration: const InputDecoration(
                        isDense: true,
                        counterText: '',
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                      ),
                      onTap: () => _qty.selection = TextSelection(baseOffset: 0, extentOffset: _qty.text.length),
                      onChanged: (String v) {
                        final int? n = int.tryParse(v);
                        if (n != null && n >= 1) cart.setQty(item, n);
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _StepButton(icon: Icons.add, tooltip: 'One$noun more', onPressed: onMore),
              // On the right; shrinks (the label ellipsised) rather than
              // overflow a narrow phone or large text.
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: widget.onEditDiscount,
                    icon: const Icon(Icons.percent, size: 16),
                    label: Text(item.discountBp > 0 ? Inr.percent(item.discountBp) : 'Discount',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ),
            ],
          ),
          if (packs)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '= ${PackSize.breakdown(item.qty, item.unit, item.packSize)}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary),
              ),
            ),
          const SizedBox(height: 4),
          for (final CartLine l in lines)
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 6),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.inventory_2_outlined, size: 14, color: AppColors.muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${l.batch.batchNo.isEmpty ? 'No batch no.' : l.batch.batchNo}'
                      ' · Exp ${exp.format(l.batch.expiryDate)}'
                      ' · MRP ${Inr.format(l.batch.mrpPaise)}'
                      '${l.batch.pricePack > 1 ? '/${PackSize.packNoun(l.batch.unit)}' : ''}'
                      ' × ${l.qty}',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.ink),
                    ),
                  ),
                ],
              ),
            ),
          if (!alloc.isComplete)
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 6),
              child: Text(
                available == 0
                    ? 'No stock left that can be sold.'
                    : 'Only $available ${item.unit} in stock - reduce the quantity.',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.statusRed),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: widget.onChangeBatch,
              child: Text(item.pinnedBatchId == null ? 'Change batch' : 'Batch chosen · change'),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.outlined(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      style: IconButton.styleFrom(
        minimumSize: const Size(40, 40),
        side: const BorderSide(color: AppColors.border, width: 1.5),
        foregroundColor: AppColors.navy,
      ),
    );
  }
}

/// One-number dialog (discount %). A StatefulWidget so its controller is
/// disposed with the route, after the exit animation: disposing it at pop
/// left the fading dialog rebuilding its field on a dead controller.
class _NumberDialog extends StatefulWidget {
  const _NumberDialog({
    required this.title,
    required this.initial,
    required this.decimal,
    required this.validate,
  });

  final String title;
  final String initial;
  final bool decimal;
  final String? Function(String) validate;

  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _done() {
    final String? e = widget.validate(_ctrl.text.trim());
    if (e != null) {
      setState(() => _error = e);
      return;
    }
    Navigator.of(context).pop(_ctrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType: TextInputType.numberWithOptions(decimal: widget.decimal),
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.allow(RegExp(widget.decimal ? r'[0-9.]' : r'[0-9]')),
        ],
        onSubmitted: (_) => _done(),
        decoration: InputDecoration(errorText: _error),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(onPressed: _done, child: const Text('OK')),
      ],
    );
  }
}
