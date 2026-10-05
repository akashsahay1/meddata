import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/inr.dart';
import '../../../data/models/bill.dart';
import '../../../data/repositories/billing_repository.dart';
import '../../../services/auth_service.dart';
import '../../../services/billing_api.dart';
import '../../../services/invoice_pdf.dart';
import '../../../services/invoice_share.dart';
import '../../../state/medicine_provider.dart';
import '../../../sync/sync_engine.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/ui_kit.dart';
import 'billing_widgets.dart';

/// One bill as the server has it: items, GST, totals. Print or share the
/// invoice (A4 or 80 mm), send it on WhatsApp, or cancel the bill (its
/// stock goes back; the invoice number stays used).
class BillDetailScreen extends StatefulWidget {
  const BillDetailScreen({
    super.key,
    this.bill,
    this.billId,
    this.justCreated = false,
    this.alreadySaved = false,
    this.api,
  }) : assert(bill != null || billId != null);

  final Bill? bill;
  final String? billId;

  /// Opened right after the bill was made (shows "Bill saved").
  final bool justCreated;

  /// The server had already made this bill (a retried request).
  final bool alreadySaved;
  final BillingApi? api;

  /// Popped by "New bill" after a bill was made: the counter screen stays.
  static const String newBill = 'new-bill';

  @override
  State<BillDetailScreen> createState() => _BillDetailScreenState();
}

class _BillDetailScreenState extends State<BillDetailScreen> {
  late final BillingApi _api = widget.api ?? BillingApi();
  Bill? _bill;
  bool _loading = false;
  ApiOutcome<Bill>? _failure;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _bill = widget.bill;
    if (_bill == null) WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    if (widget.alreadySaved) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _toast(
          'This bill had already been saved - no second bill was made.'));
    }
  }

  Future<void> _load() async {
    final String? token = context.read<AuthService>().token;
    if (token == null) return;
    setState(() => _loading = true);
    final ApiOutcome<Bill> r = await _api.get(token, widget.billId ?? _bill!.id);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.isOk) {
        _bill = r.value;
        _failure = null;
      } else {
        _failure = r;
      }
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<InvoiceLayout?> _pickLayout(String action) {
    return showModalBottomSheet<InvoiceLayout>(
      context: context,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(action, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(InvoiceLayout.a4.label),
              subtitle: const Text('Full tax invoice'),
              onTap: () => Navigator.of(ctx).pop(InvoiceLayout.a4),
            ),
            ListTile(
              leading: const Icon(Icons.receipt_outlined),
              title: Text(InvoiceLayout.receipt80.label),
              subtitle: const Text('Thermal receipt printer'),
              onTap: () => Navigator.of(ctx).pop(InvoiceLayout.receipt80),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _run(Future<void> Function() action, String failure) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      debugPrint('[Invoice] $failure: $e');
      if (mounted) _toast(failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _print() async {
    final InvoiceLayout? layout = await _pickLayout('Print');
    if (layout == null || !mounted) return;
    await _run(() => InvoiceShare.printPdf(_bill!, layout), 'Could not open printing.');
  }

  Future<void> _share() async {
    final InvoiceLayout? layout = await _pickLayout('Share PDF');
    if (layout == null || !mounted) return;
    await _run(() => InvoiceShare.sharePdf(_bill!, layout), 'Could not share the invoice.');
  }

  Future<void> _whatsApp() async {
    final bool ok = await InvoiceShare.openWhatsApp(_bill!);
    if (!ok && mounted) _toast('Could not open WhatsApp.');
  }

  Future<void> _cancel() async {
    final TextEditingController reason = TextEditingController();
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Cancel this bill?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('${_bill!.invoiceNo} will be marked cancelled and its medicines '
                'go back into stock. Its number stays used.'),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              maxLength: 255,
              decoration: const InputDecoration(labelText: 'Reason (optional)', counterText: ''),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep bill')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.statusRed),
            child: const Text('Cancel bill'),
          ),
        ],
      ),
    );
    final String why = reason.text;
    reason.dispose();
    if (go != true || !mounted) return;

    final AuthService auth = context.read<AuthService>();
    final MedicineProvider mp = context.read<MedicineProvider>();
    final SyncEngine sync = context.read<SyncEngine>();
    if (auth.token == null) return;
    setState(() => _busy = true);
    final ApiOutcome<(Bill, Map<String, int>)> r =
        await _api.cancel(auth.token!, _bill!.id, reason: why, deviceId: auth.deviceId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.isOk) {
      _toast(r.isOffline
          ? 'No internet - the bill was not cancelled. Try again when online.'
          : (r.message ?? 'Could not cancel the bill.'));
      return;
    }
    final (Bill bill, Map<String, int> stock) = r.value!;
    setState(() => _bill = bill);
    await BillingRepository().applyServerStock(stock);
    await mp.load();
    unawaited(sync.syncNow());
    if (mounted) _toast('Bill cancelled. Its stock is back in inventory.');
  }

  @override
  Widget build(BuildContext context) {
    final Bill? bill = _bill;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(bill?.invoiceNo ?? 'Bill', overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          if (bill != null && !bill.isCancelled)
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (String v) {
                if (v == 'cancel') _cancel();
              },
              itemBuilder: (_) => const <PopupMenuEntry<String>>[
                PopupMenuItem<String>(value: 'cancel', child: Text('Cancel bill')),
              ],
            ),
        ],
      ),
      body: bill == null
          ? (_loading || _failure == null
              ? const Center(child: CircularProgressIndicator())
              : BillingOfflineNotice(
                  onRetry: _load,
                  offline: _failure!.isOffline,
                  message: _failure!.message,
                ))
          : Stack(
              children: <Widget>[
                _content(bill),
                if (_busy) const LinearProgressIndicator(),
              ],
            ),
    );
  }

  Widget _content(Bill bill) {
    final bool registered = bill.seller.gstin != null;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + MediaQuery.paddingOf(context).bottom),
          children: <Widget>[
            if (widget.justCreated) ...<Widget>[_savedBanner(), const SizedBox(height: 12)],
            _headerCard(bill),
            const SizedBox(height: 12),
            _actions(bill),
            if (bill.isCancelled) ...<Widget>[
              const SizedBox(height: 12),
              BillingCard(
                child: Text(
                  'Cancelled${bill.cancelledAt == null ? '' : ' on ${DateFormat('dd MMM yyyy, hh:mm a').format(bill.cancelledAt!)}'}'
                  '${bill.cancelReason == null ? '' : ' - ${bill.cancelReason}'}. '
                  'Its stock went back into inventory.',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.statusRed),
                ),
              ),
            ],
            if (bill.customerName != null || bill.customerPhone != null || bill.customerGstin != null) ...<Widget>[
              const BillingSectionLabel('Customer'),
              _customerCard(bill),
            ],
            BillingSectionLabel('Items (${bill.items.length})'),
            BillingCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: <Widget>[
                  for (int i = 0; i < bill.items.length; i++) ...<Widget>[
                    if (i > 0) const Divider(height: 1),
                    _itemRow(bill.items[i], registered),
                  ],
                ],
              ),
            ),
            const BillingSectionLabel('Totals'),
            _totalsCard(bill, registered),
          ],
        ),
      ),
    );
  }

  Widget _savedBanner() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.statusGreenBg,
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.check_circle, color: AppColors.statusGreen),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Bill saved. Stock updated on all devices.',
                style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
          ),
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(BillDetailScreen.newBill),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New bill'),
          ),
        ],
      ),
    );
  }

  Widget _headerCard(Bill bill) {
    return BillingCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(bill.invoiceNo,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.ink)),
                const SizedBox(height: 4),
                Text(
                  DateFormat('dd MMM yyyy, hh:mm a').format(bill.createdAt ?? bill.billDate),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.muted),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: <Widget>[
                    if (bill.isCancelled)
                      StatusPill.danger('Cancelled')
                    else if (bill.paymentMode == PaymentMode.credit)
                      StatusPill.low('Credit - to be paid')
                    else
                      StatusPill.inStock('Paid · ${bill.paymentMode.label}'),
                    if (bill.isInterState) StatusPill.low('IGST'),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              const Text('Total', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.muted)),
              Text(
                Inr.format(bill.totalPaise),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                  decoration: bill.isCancelled ? TextDecoration.lineThrough : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actions(Bill bill) {
    final bool hasPhone = InvoiceShare.whatsAppNumber(bill.customerPhone) != null;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: <Widget>[
        _ActionButton(icon: Icons.print_outlined, label: 'Print', onPressed: _busy ? null : _print),
        _ActionButton(icon: Icons.share_outlined, label: 'Share PDF', onPressed: _busy ? null : _share),
        if (hasPhone)
          _ActionButton(icon: Icons.chat_outlined, label: 'WhatsApp customer', onPressed: _busy ? null : _whatsApp),
      ],
    );
  }

  Widget _customerCard(Bill bill) {
    return BillingCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(bill.customerName ?? 'Customer',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink)),
          for (final String line in <String?>[
            bill.customerPhone,
            bill.customerGstin == null ? null : 'GSTIN ${bill.customerGstin}',
            bill.customerAddress,
            bill.placeOfSupplyLabel == null ? null : 'Place of supply: ${bill.placeOfSupplyLabel}',
          ].whereType<String>())
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(line, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
            ),
        ],
      ),
    );
  }

  Widget _itemRow(BillItem i, bool registered) {
    final String exp = i.expiryDate == null ? '' : ' · Exp ${DateFormat('MM/yy').format(i.expiryDate!)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(i.name, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                const SizedBox(height: 2),
                Text(
                  '${i.batchNo == null ? 'No batch no.' : 'Batch ${i.batchNo}'}$exp'
                  '${i.hsn == null || !registered ? '' : ' · HSN ${i.hsn}'}',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                Text(
                  '${i.qty} × ${Inr.format(i.mrpPaise)}'
                  '${i.discountBp > 0 ? ' · ${Inr.percent(i.discountBp)} off' : ''}'
                  '${registered ? ' · GST ${Inr.percent(i.gstRateBp)}' : ''}',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          Text(Inr.format(i.totalPaise),
              style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink)),
        ],
      ),
    );
  }

  Widget _totalsCard(Bill bill, bool registered) {
    return BillingCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AmountRow('MRP value', Inr.format(bill.subtotalPaise)),
          if (bill.discountPaise > 0) AmountRow('Discount', '-${Inr.format(bill.discountPaise)}'),
          if (registered) ...<Widget>[
            AmountRow('Taxable value', Inr.format(bill.taxablePaise)),
            if (bill.isInterState)
              AmountRow('IGST', Inr.format(bill.igstPaise))
            else ...<Widget>[
              AmountRow('CGST', Inr.format(bill.cgstPaise)),
              AmountRow('SGST', Inr.format(bill.sgstPaise)),
            ],
          ],
          if (bill.roundOffPaise != 0) AmountRow('Round off', signedInr(bill.roundOffPaise)),
          const Divider(height: 18),
          AmountRow('Total', Inr.format(bill.totalPaise), strong: true, big: true),
          const SizedBox(height: 6),
          Text(Inr.words(bill.totalPaise),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.muted)),
          if (registered && bill.taxSummary.isNotEmpty) ...<Widget>[
            const Divider(height: 22),
            const Text('GST by rate',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.muted)),
            const SizedBox(height: 4),
            for (final BillTaxRow t in bill.taxSummary)
              AmountRow(
                '${Inr.percent(t.gstRateBp)} on ${Inr.format(t.taxablePaise)}',
                Inr.format(t.taxPaise),
              ),
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label, required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
      icon: Icon(icon, size: 19),
      label: Text(label),
    );
  }
}
