import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/inr.dart';
import '../../../data/models/accounting.dart';
import '../../../services/accounting_api.dart';
import '../../../services/auth_service.dart';
import '../../../services/billing_api.dart';
import '../../../sync/sync_engine.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/ui_kit.dart';
import '../billing/billing_widgets.dart';
import 'accounts_widgets.dart';
import 'payment_screen.dart';
import 'return_screen.dart';

/// One supplier bill: its items (batches received), input GST and what is
/// still to pay. Send goods back (debit note), pay it, or cancel it.
class PurchaseDetailScreen extends StatefulWidget {
  const PurchaseDetailScreen({super.key, required this.purchaseId, this.api});

  final String purchaseId;
  final AccountingApi? api;

  @override
  State<PurchaseDetailScreen> createState() => _PurchaseDetailScreenState();
}

class _PurchaseDetailScreenState extends State<PurchaseDetailScreen> {
  late final AccountingApi _api = widget.api ?? AccountingApi();
  Purchase? _purchase;
  ApiOutcome<Purchase>? _failure;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final String? token = context.read<AuthService>().token;
    if (token == null) {
      setState(() => _failure = const ApiOutcome<Purchase>.failed(401, 'Please log in again.'));
      return;
    }
    final ApiOutcome<Purchase> r = await _api.purchase(token, widget.purchaseId);
    if (!mounted) return;
    setState(() {
      _purchase = r.value ?? _purchase;
      _failure = r.isOk ? null : r;
    });
  }

  void _toast(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _return() async {
    await Navigator.of(context).push(MaterialPageRoute<Object?>(
        builder: (_) => ReturnScreen.purchase(purchase: _purchase!, api: _api)));
    if (mounted) _load();
  }

  Future<void> _pay() async {
    final String? token = context.read<AuthService>().token;
    if (token == null) return;
    setState(() => _busy = true);
    final ApiOutcome<PartyDetail> party = await _api.party(token, _purchase!.partyId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!party.isOk) {
      _toast(party.message ?? 'Could not load the supplier.');
      return;
    }
    final bool? saved = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
      builder: (_) => PaymentScreen(
        party: party.value!.party,
        received: false,
        openDocuments: party.value!.openDocuments,
        documentId: _purchase!.id,
        api: _api,
      ),
    ));
    if (saved == true && mounted) _load();
  }

  Future<void> _cancel() async {
    final TextEditingController reason = TextEditingController();
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Cancel this purchase?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('Its stock is taken back out of inventory and it leaves the supplier’s account. '
                'Use this for a bill entered by mistake; for goods sent back, use Return to supplier.'),
            TextField(
              controller: reason,
              maxLength: 255,
              decoration: const InputDecoration(labelText: 'Reason (optional)', counterText: ''),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.statusRed),
            child: const Text('Cancel purchase'),
          ),
        ],
      ),
    );
    final String why = reason.text;
    reason.dispose();
    if (go != true || !mounted) return;
    final AuthService auth = context.read<AuthService>();
    final SyncEngine sync = context.read<SyncEngine>();
    if (auth.token == null) return;
    setState(() => _busy = true);
    final DocResult<Purchase> r = await _api.cancelPurchase(auth.token!, _purchase!.id, reason: why, deviceId: auth.deviceId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.isOk) {
      _toast(r.isOffline ? 'No internet - the purchase was not cancelled.' : (r.message ?? 'Could not cancel.'));
      return;
    }
    unawaited(sync.syncNow());
    _toast('Purchase cancelled. Its stock was taken out of inventory.');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final Purchase? p = _purchase;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(p?.invoiceNo ?? 'Purchase', overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          if (p != null && !p.cancelled)
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (String v) {
                if (v == 'cancel') _cancel();
              },
              itemBuilder: (_) => const <PopupMenuEntry<String>>[
                PopupMenuItem<String>(value: 'cancel', child: Text('Cancel purchase')),
              ],
            ),
        ],
      ),
      body: p == null
          ? (_failure == null
              ? const Center(child: CircularProgressIndicator())
              : AccountsOfflineNotice(onRetry: _load, offline: _failure!.isOffline, message: _failure!.message))
          : Stack(children: <Widget>[_content(p), if (_busy) const LinearProgressIndicator()]),
    );
  }

  Widget _content(Purchase p) {
    final bool canReturn = !p.cancelled && p.items.any((PurchaseItem i) => i.qty - i.returnedQty > 0);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + MediaQuery.paddingOf(context).bottom),
          children: <Widget>[
            BillingCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(p.supplierName,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
                        InfoLine('Invoice ${p.invoiceNo} · ${DateFormat('dd MMM yyyy').format(p.invoiceDate)}'),
                        if (p.supplierGstin != null) InfoLine('GSTIN ${p.supplierGstin}'),
                        const SizedBox(height: 8),
                        if (p.cancelled)
                          StatusPill.danger('Cancelled')
                        else if (p.outstandingPaise > 0)
                          StatusPill.low('${Inr.format(p.outstandingPaise)} to pay')
                        else
                          StatusPill.inStock('Paid'),
                      ],
                    ),
                  ),
                  Text(Inr.format(p.totalPaise),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                        decoration: p.cancelled ? TextDecoration.lineThrough : null,
                      )),
                ],
              ),
            ),
            if (!p.cancelled) ...<Widget>[
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  if (p.outstandingPaise > 0)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
                      onPressed: _busy ? null : _pay,
                      icon: const Icon(Icons.call_made, size: 19),
                      label: const Text('Pay supplier'),
                    ),
                  if (canReturn)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
                      onPressed: _busy ? null : _return,
                      icon: const Icon(Icons.assignment_return_outlined, size: 19),
                      label: const Text('Return to supplier'),
                    ),
                ],
              ),
            ],
            if (p.cancelled && p.cancelReason != null) ...<Widget>[
              const SizedBox(height: 10),
              Text('Cancelled: ${p.cancelReason}', style: const TextStyle(color: AppColors.statusRed)),
            ],
            BillingSectionLabel('Items (${p.items.length})'),
            BillingCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: <Widget>[
                  for (int i = 0; i < p.items.length; i++) ...<Widget>[
                    if (i > 0) const Divider(height: 1),
                    _item(p.items[i]),
                  ],
                ],
              ),
            ),
            const BillingSectionLabel('Totals'),
            BillingCard(
              child: Column(
                children: <Widget>[
                  AmountRow('Amount before discount', Inr.format(p.subtotalPaise)),
                  if (p.discountPaise > 0) AmountRow('Discount', '-${Inr.format(p.discountPaise)}'),
                  AmountRow('Taxable value', Inr.format(p.taxablePaise)),
                  if (p.isInterState)
                    AmountRow('IGST (input)', Inr.format(p.igstPaise))
                  else ...<Widget>[
                    AmountRow('CGST (input)', Inr.format(p.cgstPaise)),
                    AmountRow('SGST (input)', Inr.format(p.sgstPaise)),
                  ],
                  if (p.roundOffPaise != 0) AmountRow('Round off', signedInr(p.roundOffPaise)),
                  const Divider(height: 18),
                  AmountRow('Total', Inr.format(p.totalPaise), strong: true, big: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(PurchaseItem i) {
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
                Text(
                  '${i.batchNo == null ? 'No batch no.' : 'Batch ${i.batchNo}'}'
                  '${i.expiryDate == null ? '' : ' · Exp ${DateFormat('MM/yy').format(i.expiryDate!)}'}'
                  '${i.hsn == null ? '' : ' · HSN ${i.hsn}'}',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                Text(
                  '${i.qty}${i.freeQty > 0 ? ' + ${i.freeQty} free' : ''} × ${Inr.format(i.ratePaise)}'
                  '${i.discountBp > 0 ? ' · ${Inr.percent(i.discountBp)} off' : ''} · GST ${Inr.percent(i.gstRateBp)}'
                  '${i.unitsPerPack > 1 ? ' · ${i.stockUnits} units' : ''}',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                if (i.returnedQty > 0)
                  Text('${i.returnedQty} returned',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.statusRed)),
              ],
            ),
          ),
          Text(Inr.format(i.totalPaise), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink)),
        ],
      ),
    );
  }
}
