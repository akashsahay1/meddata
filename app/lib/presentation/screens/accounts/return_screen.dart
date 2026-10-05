import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/inr.dart';
import '../../../data/models/accounting.dart';
import '../../../data/models/bill.dart';
import '../../../domain/accounting.dart';
import '../../../domain/gst.dart';
import '../../../services/accounting_api.dart';
import '../../../services/auth_service.dart';
import '../../../state/medicine_provider.dart';
import '../../../sync/sync_engine.dart';
import '../../../theme/app_theme.dart';
import '../billing/billing_widgets.dart';
import 'accounts_widgets.dart';
import 'note_detail_screen.dart';

/// Goods coming back: a customer returning items of a bill (credit note,
/// stock back) or goods going back to a supplier from a purchase (debit
/// note, stock out). Choose how many of each line; at most what was sold /
/// bought less earlier returns.
class ReturnScreen extends StatefulWidget {
  const ReturnScreen.sale({super.key, required Bill this.bill, this.api}) : purchase = null;
  const ReturnScreen.purchase({super.key, required Purchase this.purchase, this.api}) : bill = null;

  final Bill? bill;
  final Purchase? purchase;
  final AccountingApi? api;

  @override
  State<ReturnScreen> createState() => _ReturnScreenState();
}

class _ReturnScreenState extends State<ReturnScreen> {
  late final AccountingApi _api = widget.api ?? AccountingApi();
  late final ReturnDraft _draft =
      widget.bill != null ? ReturnDraft.forBill(widget.bill!) : ReturnDraft.forPurchase(widget.purchase!);
  final TextEditingController _reason = TextEditingController();

  /// Sale returns: refunded how (credit = adjusted on the customer's account).
  late String _refund = _defaultRefund();
  bool _saving = false;
  final String _id = const Uuid().v4();

  bool get _sale => _draft.isSale;

  String _defaultRefund() {
    final Bill? b = widget.bill;
    if (b == null) return 'credit';
    if (b.paymentMode == PaymentMode.credit) return 'credit';
    return b.paymentMode.name;
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _toast(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _submit() async {
    if (_draft.isEmpty) {
      _toast('Choose how many of each item come back.');
      return;
    }
    final AuthService auth = context.read<AuthService>();
    final SyncEngine sync = context.read<SyncEngine>();
    final MedicineProvider meds = context.read<MedicineProvider>();
    final NavigatorState nav = Navigator.of(context);
    if (auth.token == null) return;
    setState(() => _saving = true);
    final DocResult<ReturnNote> r = await _api.createReturn(
      auth.token!,
      _draft.body(id: _id, deviceId: auth.deviceId, reason: _reason.text, refundMode: _sale ? _refund : null),
      sale: _sale,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!r.isOk) {
      _toast(r.isOffline
          ? "Couldn't reach the server, so the return is not confirmed. Tap the button again - it won't be made twice."
          : (r.message ?? 'Could not make the return.'));
      return;
    }
    // The stock movements reach this device with the next sync.
    unawaited(sync.syncNow().then((_) => meds.load()));
    await nav.pushReplacement(MaterialPageRoute<void>(
      builder: (_) => NoteDetailScreen(note: r.value, sale: _sale, justCreated: true, api: _api),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final GstTotals t = _draft.totals;
    final Bill? bill = widget.bill;
    final String noun = _sale ? 'Credit note' : 'Debit note';
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(_sale ? 'Sale return' : 'Return to supplier')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + MediaQuery.paddingOf(context).bottom),
        children: <Widget>[
          BillingCard(
            child: Text(
              _sale
                  ? 'Items returned against ${bill!.invoiceNo}${bill.customerName == null ? '' : ' (${bill.customerName})'}. '
                      'They go back into stock and a credit note reverses the GST.'
                  : 'Goods sent back to ${widget.purchase!.supplierName} from invoice ${widget.purchase!.invoiceNo}. '
                      'They leave stock and a debit note reverses the input GST. Free goods are not returned here.',
              style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600),
            ),
          ),
          Row(
            children: <Widget>[
              const Expanded(child: BillingSectionLabel('Items')),
              TextButton(
                onPressed: () => setState(_draft.all),
                child: const Text('Return all'),
              ),
            ],
          ),
          if (_draft.lines.isEmpty)
            const Text('Everything on it has already been returned.', style: TextStyle(color: AppColors.muted)),
          for (final ReturnLine l in _draft.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: BillingCard(
                padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(l.name, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink)),
                          Text(
                            '${l.batchNo == null ? '' : 'Batch ${l.batchNo} · '}up to ${l.maxQty} · '
                            '${Inr.format(l.ratePaise)} ${_sale ? 'MRP' : 'rate'}',
                            style: const TextStyle(fontSize: 12, color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'One less ${l.name}',
                      onPressed: l.qty > 0 ? () => setState(() => _draft.setQty(l, l.qty - 1)) : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    SizedBox(
                      width: 32,
                      child: Text('${l.qty}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
                    ),
                    IconButton(
                      tooltip: 'One more ${l.name}',
                      onPressed: l.qty < l.maxQty ? () => setState(() => _draft.setQty(l, l.qty + 1)) : null,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
              ),
            ),
          if (_sale) ...<Widget>[
            const BillingSectionLabel('Money back'),
            if (bill!.paymentMode == PaymentMode.credit)
              const Text('A credit bill: the amount comes off the customer’s account.',
                  style: TextStyle(color: AppColors.muted))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final (String mode, String label) in <(String, String)>[
                    ('cash', 'Cash refund'),
                    ('upi', 'UPI refund'),
                    ('card', 'Card refund'),
                    ('bank', 'Bank refund'),
                    if (bill.partyId != null) ('credit', 'Adjust in account'),
                  ])
                    AccountsPill(label: label, selected: _refund == mode, onTap: () => setState(() => _refund = mode)),
                ],
              ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            maxLength: 255,
            decoration: const InputDecoration(labelText: 'Reason (optional)', counterText: ''),
          ),
          const BillingSectionLabel('Total'),
          BillingCard(
            child: Column(
              children: <Widget>[
                AmountRow('Taxable value', Inr.format(t.taxablePaise)),
                AmountRow('GST reversed', Inr.format(t.taxPaise)),
                if (t.roundOffPaise != 0) AmountRow('Round off', signedInr(t.roundOffPaise)),
                const Divider(height: 18),
                AmountRow('$noun total', Inr.format(t.totalPaise), strong: true, big: true),
                const SizedBox(height: 4),
                const Text('The server works out the final amounts.',
                    style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: inkOnOrange,
              onPressed: _saving || _draft.isEmpty ? null : _submit,
              child: Text(_saving ? 'Saving…' : 'Make ${noun.toLowerCase()}'),
            ),
          ),
        ],
      ),
    );
  }
}
