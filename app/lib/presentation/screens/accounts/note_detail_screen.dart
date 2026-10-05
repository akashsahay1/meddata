import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/inr.dart';
import '../../../data/models/accounting.dart';
import '../../../domain/gst.dart';
import '../../../services/accounting_api.dart';
import '../../../services/accounting_pdf.dart';
import '../../../services/auth_service.dart';
import '../../../services/billing_api.dart';
import '../../../theme/app_theme.dart';
import '../billing/billing_widgets.dart';
import 'accounts_widgets.dart';

/// A credit note (sale return) or debit note (purchase return): items,
/// reversed GST and total, printable / shareable as a PDF.
class NoteDetailScreen extends StatefulWidget {
  const NoteDetailScreen({super.key, this.note, this.noteId, required this.sale, this.justCreated = false, this.api})
      : assert(note != null || noteId != null);

  final ReturnNote? note;
  final String? noteId;

  /// Credit note (true) or debit note.
  final bool sale;
  final bool justCreated;
  final AccountingApi? api;

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {
  late final AccountingApi _api = widget.api ?? AccountingApi();
  late ReturnNote? _note = widget.note;
  ApiOutcome<ReturnNote>? _failure;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (_note == null) WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final String? token = context.read<AuthService>().token;
    if (token == null) {
      setState(() => _failure = const ApiOutcome<ReturnNote>.failed(401, 'Please log in again.'));
      return;
    }
    final ApiOutcome<ReturnNote> r = await _api.note(token, widget.noteId!, sale: widget.sale);
    if (!mounted) return;
    setState(() {
      _note = r.value ?? _note;
      _failure = r.isOk ? null : r;
    });
  }

  Future<void> _pdf(bool print) async {
    setState(() => _busy = true);
    try {
      await (print ? AccountingShare.printNote(_note!) : AccountingShare.shareNote(_note!));
    } catch (e) {
      debugPrint('[Note PDF] $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(print ? 'Could not open printing.' : 'Could not share the note.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ReturnNote? n = _note;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(n?.noteNo ?? (widget.sale ? 'Credit note' : 'Debit note'))),
      body: n == null
          ? (_failure == null
              ? const Center(child: CircularProgressIndicator())
              : AccountsOfflineNotice(onRetry: _load, offline: _failure!.isOffline, message: _failure!.message))
          : Stack(children: <Widget>[_content(n), if (_busy) const LinearProgressIndicator()]),
    );
  }

  Widget _content(ReturnNote n) {
    final bool gst = n.seller['gstin'] != null;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + MediaQuery.paddingOf(context).bottom),
          children: <Widget>[
            if (widget.justCreated) ...<Widget>[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.statusGreenBg,
                  borderRadius: BorderRadius.circular(AppRadii.card),
                ),
                child: Text(
                  n.isCreditNote ? '${n.title} saved. The items are back in stock.' : '${n.title} saved. The items left stock.',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
                ),
              ),
              const SizedBox(height: 12),
            ],
            BillingCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('${n.title} ${n.noteNo}',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
                        InfoLine(DateFormat('dd MMM yyyy').format(n.date)),
                        if (n.partyName != null) InfoLine(n.partyName!),
                        if (n.againstNo != null) InfoLine('${n.isCreditNote ? 'Bill' : 'Supplier invoice'} ${n.againstNo}'),
                        if (n.placeOfSupply != null) InfoLine('Place of supply: ${GstStates.label(n.placeOfSupply!)}'),
                        if (n.isCreditNote && n.refundMode != null)
                          InfoLine(n.refundMode == 'credit'
                              ? 'Adjusted on the customer’s account'
                              : 'Refunded by ${n.refundMode!.toUpperCase()}'),
                        if (n.reason != null) InfoLine('Reason: ${n.reason}'),
                      ],
                    ),
                  ),
                  Text(Inr.format(n.totalPaise),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
                  onPressed: _busy ? null : () => _pdf(true),
                  icon: const Icon(Icons.print_outlined, size: 19),
                  label: const Text('Print'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
                  onPressed: _busy ? null : () => _pdf(false),
                  icon: const Icon(Icons.share_outlined, size: 19),
                  label: const Text('Share PDF'),
                ),
              ],
            ),
            BillingSectionLabel('Items (${n.items.length})'),
            BillingCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: <Widget>[
                  for (int i = 0; i < n.items.length; i++) ...<Widget>[
                    if (i > 0) const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(n.items[i].name,
                                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                                Text(
                                  '${n.items[i].qty} × ${Inr.format(n.items[i].ratePaise)}'
                                  '${n.items[i].batchNo == null ? '' : ' · Batch ${n.items[i].batchNo}'}'
                                  '${gst ? ' · GST ${Inr.percent(n.items[i].gstRateBp)}' : ''}',
                                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                                ),
                              ],
                            ),
                          ),
                          Text(Inr.format(n.items[i].totalPaise),
                              style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const BillingSectionLabel('Totals'),
            BillingCard(
              child: Column(
                children: <Widget>[
                  if (gst) ...<Widget>[
                    AmountRow('Taxable value', Inr.format(n.taxablePaise)),
                    if (n.isInterState)
                      AmountRow('IGST', Inr.format(n.igstPaise))
                    else ...<Widget>[
                      AmountRow('CGST', Inr.format(n.cgstPaise)),
                      AmountRow('SGST', Inr.format(n.sgstPaise)),
                    ],
                  ],
                  if (n.roundOffPaise != 0) AmountRow('Round off', signedInr(n.roundOffPaise)),
                  const Divider(height: 18),
                  AmountRow('Total', Inr.format(n.totalPaise), strong: true, big: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
