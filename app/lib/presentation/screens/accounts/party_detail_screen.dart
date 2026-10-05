import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/inr.dart';
import '../../../data/models/accounting.dart';
import '../../../domain/accounting.dart';
import '../../../services/accounting_api.dart';
import '../../../services/accounting_pdf.dart';
import '../../../services/auth_service.dart';
import '../../../services/billing_api.dart';
import '../../../theme/app_theme.dart';
import '../billing/bill_detail_screen.dart';
import '../billing/billing_widgets.dart';
import 'accounts_widgets.dart';
import 'note_detail_screen.dart';
import 'party_form_screen.dart';
import 'payment_screen.dart';
import 'purchase_detail_screen.dart';

enum _Range { all, month, quarter, custom }

/// One party: what they owe (or are owed), their ledger with a running
/// balance, payments in / out, and the ledger as a PDF to print or share.
class PartyDetailScreen extends StatefulWidget {
  const PartyDetailScreen({super.key, required this.partyId, this.api});

  final String partyId;
  final AccountingApi? api;

  @override
  State<PartyDetailScreen> createState() => _PartyDetailScreenState();
}

class _PartyDetailScreenState extends State<PartyDetailScreen> {
  late final AccountingApi _api = widget.api ?? AccountingApi();
  PartyDetail? _detail;
  Ledger? _ledger;
  String? _failure;
  bool _offline = false;
  bool _loading = true;
  bool _busy = false;
  _Range _range = _Range.all;
  DateTimeRange? _custom;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  DateTimeRange? _dates() {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    return switch (_range) {
      _Range.all => null,
      _Range.month => DateTimeRange(start: DateTime(today.year, today.month), end: today),
      _Range.quarter => DateTimeRange(start: DateTime(today.year, today.month - 2), end: today),
      _Range.custom => _custom,
    };
  }

  Future<void> _load() async {
    final String? token = context.read<AuthService>().token;
    if (token == null) {
      setState(() {
        _loading = false;
        _failure = 'Please log in again.';
        _offline = false;
      });
      return;
    }
    setState(() => _loading = true);
    final DateTimeRange? d = _dates();
    final List<Object> r = await Future.wait(<Future<Object>>[
      _api.party(token, widget.partyId),
      _api.ledger(token, widget.partyId, from: d?.start, to: d?.end),
    ]);
    if (!mounted) return;
    final ApiOutcome<PartyDetail> detail = r[0] as ApiOutcome<PartyDetail>;
    final ApiOutcome<Ledger> ledger = r[1] as ApiOutcome<Ledger>;
    setState(() {
      _loading = false;
      if (detail.isOk && ledger.isOk) {
        _detail = detail.value;
        _ledger = ledger.value;
        _failure = null;
      } else {
        final ApiOutcome<Object?> bad = detail.isOk ? ledger : detail;
        _failure = bad.message;
        _offline = bad.isOffline;
      }
    });
  }

  void _toast(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _open(Widget screen) async {
    final Object? changed = await Navigator.of(context).push<Object?>(MaterialPageRoute<Object?>(builder: (_) => screen));
    if (mounted && changed != null) _load();
  }

  Future<void> _openAndReload(Widget screen) async {
    await Navigator.of(context).push<Object?>(MaterialPageRoute<Object?>(builder: (_) => screen));
    if (mounted) _load();
  }

  Future<void> _pay(bool received) => _open(PaymentScreen(
        party: _detail!.party,
        received: received,
        openDocuments: _detail!.openDocuments,
        api: _api,
      ));

  Future<void> _pdf(bool print) async {
    final Ledger? l = _ledger;
    if (l == null) return;
    setState(() => _busy = true);
    try {
      await (print ? AccountingShare.printLedger(l) : AccountingShare.shareLedger(l));
    } catch (e) {
      debugPrint('[Ledger PDF] $e');
      if (mounted) _toast(print ? 'Could not open printing.' : 'Could not share the ledger.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Delete this party?'),
        content: const Text('Bills and purchases keep their name. A party with money due can’t be deleted.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.statusRed),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    final String? token = context.read<AuthService>().token;
    if (token == null) return;
    final DocResult<bool> r = await _api.deleteParty(token, widget.partyId);
    if (!mounted) return;
    if (r.isOk) {
      Navigator.of(context).pop(true);
    } else {
      _toast(r.message ?? 'Could not delete.');
    }
  }

  Future<void> _entryTapped(LedgerEntry e) async {
    switch (e.type) {
      case 'sale':
        await _openAndReload(BillDetailScreen(billId: e.id));
      case 'purchase':
        await _openAndReload(PurchaseDetailScreen(purchaseId: e.id, api: _api));
      case 'sale_return':
      case 'purchase_return':
        await _openAndReload(NoteDetailScreen(noteId: e.id, sale: e.type == 'sale_return', api: _api));
      default:
        await _cancelPayment(e);
    }
  }

  Future<void> _cancelPayment(LedgerEntry e) async {
    final TextEditingController reason = TextEditingController();
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Cancel this payment?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('${e.description}, ${Inr.format(e.debitPaise + e.creditPaise)} on '
                '${DateFormat('dd MMM yyyy').format(e.date)} will be taken out of the account. '
                'Record it again if the amount was wrong.'),
            const SizedBox(height: 10),
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
            child: const Text('Cancel payment'),
          ),
        ],
      ),
    );
    final String why = reason.text;
    reason.dispose();
    if (go != true || !mounted) return;
    final String? token = context.read<AuthService>().token;
    if (token == null) return;
    final DocResult<PartyPayment> r = await _api.cancelPayment(token, e.id, reason: why);
    if (!mounted) return;
    if (r.isOk) {
      _toast('Payment cancelled.');
      _load();
    } else {
      _toast(r.message ?? 'Could not cancel.');
    }
  }

  Future<void> _pickDates() async {
    final DateTime now = DateTime.now();
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year, now.month, now.day),
    );
    if (picked == null) return;
    setState(() {
      _custom = picked;
      _range = _Range.custom;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final Party? party = _detail?.party;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(party?.name ?? 'Party', overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          if (party != null)
            IconButton(
              tooltip: 'Edit party',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _open(PartyFormScreen(party: party, api: _api)),
            ),
          if (party != null)
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (String v) {
                if (v == 'delete') _delete();
              },
              itemBuilder: (_) => const <PopupMenuEntry<String>>[
                PopupMenuItem<String>(value: 'delete', child: Text('Delete party')),
              ],
            ),
        ],
      ),
      body: _detail == null
          ? (_failure != null
              ? AccountsOfflineNotice(onRetry: _load, offline: _offline, message: _failure)
              : const Center(child: CircularProgressIndicator()))
          : Stack(
              children: <Widget>[
                _content(),
                if (_busy || _loading) const LinearProgressIndicator(),
              ],
            ),
    );
  }

  Widget _content() {
    final Party party = _detail!.party;
    final Ledger? l = _ledger;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + MediaQuery.paddingOf(context).bottom),
          children: <Widget>[
            BillingCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  BalanceLabel(party.balancePaise, big: true),
                  const SizedBox(height: 8),
                  Text(party.type.label,
                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                  for (final String line in <String?>[
                    party.phone,
                    party.gstin == null ? null : 'GSTIN ${party.gstin}',
                    party.stateLabel,
                    party.address,
                    party.notes,
                  ].whereType<String>())
                    InfoLine(line),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                if (party.type.isCustomer)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
                    onPressed: () => _pay(true),
                    icon: const Icon(Icons.call_received, size: 19),
                    label: const Text('Payment received'),
                  ),
                if (party.type.isSupplier || party.balancePaise < 0)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
                    onPressed: () => _pay(false),
                    icon: const Icon(Icons.call_made, size: 19),
                    label: const Text('Payment made'),
                  ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
                  onPressed: l == null || _busy ? null : () => _pdf(false),
                  icon: const Icon(Icons.share_outlined, size: 19),
                  label: const Text('Share ledger'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
                  onPressed: l == null || _busy ? null : () => _pdf(true),
                  icon: const Icon(Icons.print_outlined, size: 19),
                  label: const Text('Print'),
                ),
              ],
            ),
            if (_detail!.openDocuments.isNotEmpty) ...<Widget>[
              const BillingSectionLabel('Still due'),
              BillingCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Column(
                  children: <Widget>[
                    for (final OpenDocument d in _detail!.openDocuments)
                      AmountRow('${d.isBill ? 'Bill' : 'Purchase'} ${d.number} · ${dayFormat.format(d.date)}',
                          Inr.format(d.outstandingPaise)),
                  ],
                ),
              ),
            ],
            const BillingSectionLabel('Ledger'),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  for (final (_Range r, String label) in <(_Range, String)>[
                    (_Range.all, 'All'),
                    (_Range.month, 'This month'),
                    (_Range.quarter, 'Last 3 months'),
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
                  AccountsPill(
                    label: _range == _Range.custom && _custom != null
                        ? '${DateFormat('dd MMM').format(_custom!.start)} - ${DateFormat('dd MMM').format(_custom!.end)}'
                        : 'Pick dates',
                    icon: Icons.date_range,
                    selected: _range == _Range.custom,
                    onTap: _pickDates,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (l != null) _ledgerCard(l),
          ],
        ),
      ),
    );
  }

  Widget _ledgerCard(Ledger l) {
    return BillingCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _row(l.from == null ? 'Opening balance' : 'Brought forward', null, null, l.openingPaise),
          for (final LedgerEntry e in l.entries) ...<Widget>[
            const Divider(height: 1),
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () => _entryTapped(e),
                child: _row(
                  e.description,
                  '${DateFormat('dd MMM yyyy').format(e.date)}${e.number == null ? '' : ' · ${e.number}'}',
                  e.debitPaise > 0 ? '+${Inr.format(e.debitPaise)}' : '-${Inr.format(e.creditPaise)}',
                  e.balancePaise,
                ),
              ),
            ),
          ],
          const Divider(height: 1),
          _row('Closing balance', null, null, l.closingPaise, strong: true),
          if (l.entries.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Text('Nothing in this period.', style: TextStyle(color: AppColors.muted)),
            ),
        ],
      ),
    );
  }

  Widget _row(String title, String? sub, String? amount, int balance, {bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title,
                    style: TextStyle(fontWeight: strong ? FontWeight.w800 : FontWeight.w700, color: AppColors.ink)),
                if (sub != null) Text(sub, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              if (amount != null)
                Text(amount, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink)),
              Text(BalanceText.drCr(balance), style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ],
          ),
        ],
      ),
    );
  }
}
