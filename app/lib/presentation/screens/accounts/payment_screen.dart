import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/inr.dart';
import '../../../data/models/accounting.dart';
import '../../../services/accounting_api.dart';
import '../../../services/auth_service.dart';
import '../../../services/billing_api.dart';
import '../../../theme/app_theme.dart';
import '../billing/billing_widgets.dart';
import 'accounts_widgets.dart';

/// Record money received from a party (in) or paid to one (out), cash /
/// UPI / card / bank / cheque, optionally against one credit bill or
/// purchase. Pops true when saved.
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({
    super.key,
    required this.party,
    this.received = true,
    this.openDocuments = const <OpenDocument>[],
    this.documentId,
    this.api,
  });

  final Party party;

  /// Money received (true) or paid (false).
  final bool received;
  final List<OpenDocument> openDocuments;

  /// A bill / purchase to put the payment against.
  final String? documentId;
  final AccountingApi? api;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  late final AccountingApi _api = widget.api ?? AccountingApi();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _reference = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  late bool _in = widget.received;
  MoneyMode _mode = MoneyMode.cash;
  DateTime _date = DateTime.now();
  late String? _docId = widget.documentId;
  bool _saving = false;
  String? _error;

  /// Kept until the server answers, so a retry never records it twice.
  final String _id = const Uuid().v4();

  @override
  void initState() {
    super.initState();
    final OpenDocument? doc = _doc;
    if (doc != null) _amount.text = (doc.outstandingPaise / 100).toStringAsFixed(2);
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// Bills take receipts, purchases take payments.
  List<OpenDocument> get _docs =>
      widget.openDocuments.where((OpenDocument d) => d.isBill == _in).toList();

  OpenDocument? get _doc {
    for (final OpenDocument d in _docs) {
      if (d.id == _docId) return d;
    }
    return null;
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? d = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDate: _date,
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _save() async {
    final int? amount = parseRupees(_amount.text);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter the amount');
      return;
    }
    final OpenDocument? doc = _doc;
    if (doc != null && amount > doc.outstandingPaise) {
      setState(() => _error = 'Only ${Inr.format(doc.outstandingPaise)} is due on ${doc.number}');
      return;
    }
    final AuthService auth = context.read<AuthService>();
    if (auth.token == null) return;
    setState(() {
      _error = null;
      _saving = true;
    });
    final DocResult<PartyPayment> r = await _api.recordPayment(auth.token!, <String, Object?>{
      'id': _id,
      'device_id': auth.deviceId,
      'party_id': widget.party.id,
      'direction': _in ? 'in' : 'out',
      'amount_paise': amount,
      'mode': _mode.name,
      if (_reference.text.trim().isNotEmpty) 'reference': _reference.text.trim(),
      'payment_date': BillingApi.ymd(_date),
      if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
      if (doc != null && doc.isBill) 'bill_id': doc.id,
      if (doc != null && !doc.isBill) 'purchase_id': doc.id,
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (r.isOk) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _error = r.isOffline
        ? "Couldn't reach the server, so the payment is not confirmed. Tap Save again - it won't be recorded twice."
        : r.message);
  }

  @override
  Widget build(BuildContext context) {
    final OpenDocument? doc = _doc;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(_in ? 'Payment received' : 'Payment made')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + MediaQuery.paddingOf(context).bottom),
        children: <Widget>[
          BillingCard(
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(widget.party.name,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
                ),
                BalanceLabel(widget.party.balancePaise),
              ],
            ),
          ),
          const BillingSectionLabel('Money'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              AccountsPill(
                label: 'Received from them',
                icon: Icons.call_received,
                selected: _in,
                onTap: () => setState(() {
                  _in = true;
                  _docId = null;
                }),
              ),
              AccountsPill(
                label: 'Paid to them',
                icon: Icons.call_made,
                selected: !_in,
                onTap: () => setState(() {
                  _in = false;
                  _docId = null;
                }),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            autofocus: doc == null,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: rupeeInput,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink),
            decoration: InputDecoration(labelText: 'Amount (₹)', errorText: _error),
          ),
          const BillingSectionLabel('Mode'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final MoneyMode m in MoneyMode.values)
                AccountsPill(label: m.label, selected: _mode == m, onTap: () => setState(() => _mode = m)),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reference,
            maxLength: 64,
            decoration: InputDecoration(
              counterText: '',
              labelText: switch (_mode) {
                MoneyMode.cheque => 'Cheque no. (optional)',
                MoneyMode.upi => 'UPI reference (optional)',
                MoneyMode.bank => 'Transaction reference (optional)',
                _ => 'Reference (optional)',
              },
            ),
          ),
          const SizedBox(height: 4),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined, color: AppColors.green),
            title: const Text('Date'),
            subtitle: Text(DateFormat('dd MMM yyyy').format(_date)),
            onTap: _pickDate,
          ),
          if (_docs.isNotEmpty) ...<Widget>[
            const BillingSectionLabel('Against'),
            DropdownButtonFormField<String?>(
              initialValue: _docId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Bill or purchase (optional)'),
              items: <DropdownMenuItem<String?>>[
                const DropdownMenuItem<String?>(child: Text('On account (no particular bill)')),
                for (final OpenDocument d in _docs)
                  DropdownMenuItem<String?>(
                    value: d.id,
                    child: Text('${d.number} · ${Inr.format(d.outstandingPaise)} due',
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (String? v) => setState(() {
                _docId = v;
                final OpenDocument? picked = _doc;
                if (picked != null) _amount.text = (picked.outstandingPaise / 100).toStringAsFixed(2);
              }),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLength: 500,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Notes (optional)', counterText: ''),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: inkOnOrange,
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save payment'),
            ),
          ),
        ],
      ),
    );
  }
}
