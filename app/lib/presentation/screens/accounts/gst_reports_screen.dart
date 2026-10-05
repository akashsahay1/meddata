import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/inr.dart';
import '../../../domain/accounting.dart';
import '../../../domain/gst.dart';
import '../../../services/accounting_api.dart';
import '../../../services/accounting_pdf.dart';
import '../../../services/auth_service.dart';
import '../../../services/billing_api.dart';
import '../../../theme/app_theme.dart';
import '../billing/billing_widgets.dart';
import 'accounts_widgets.dart';

/// GSTR-1 and GSTR-3B style summaries of a month, worked out on the server
/// from bills, credit notes, purchases and debit notes. A starting point
/// for the shop's CA, not a filing: exported as CSV / JSON for them.
class GstReportsScreen extends StatefulWidget {
  const GstReportsScreen({super.key, this.api, this.now});

  final AccountingApi? api;

  /// Today (tests).
  final DateTime? now;

  @override
  State<GstReportsScreen> createState() => _GstReportsScreenState();
}

class _GstReportsScreenState extends State<GstReportsScreen> {
  late final AccountingApi _api = widget.api ?? AccountingApi();
  late final List<DateTime> _months = recentMonths(widget.now ?? DateTime.now());
  late DateTime _month = _months.first;
  bool _gstr1 = true;
  Map<String, dynamic>? _report;
  ApiOutcome<Map<String, dynamic>>? _failure;
  bool _loading = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final String? token = context.read<AuthService>().token;
    if (token == null) {
      setState(() => _failure = const ApiOutcome<Map<String, dynamic>>.failed(401, 'Please log in again.'));
      return;
    }
    final int request = ++_request;
    setState(() => _loading = true);
    final ApiOutcome<Map<String, dynamic>> r = await _api.gstReport(token, monthKey(_month), gstr1: _gstr1);
    if (!mounted || request != _request) return;
    setState(() {
      _loading = false;
      _report = r.value;
      _failure = r.isOk ? null : r;
    });
  }

  Future<void> _export(bool csv) async {
    final Map<String, dynamic>? r = _report;
    if (r == null) return;
    final String name = '${_gstr1 ? 'GSTR-1' : 'GSTR-3B'}-${monthKey(_month)}';
    try {
      await AccountingShare.shareText(
        csv
            ? (_gstr1 ? GstrCsv.gstr1(r) : GstrCsv.gstr3b(r))
            : const JsonEncoder.withIndent('  ').convert(r),
        '$name.${csv ? 'csv' : 'json'}',
        csv ? 'text/csv' : 'application/json',
        '$name (for review by your CA)',
      );
    } catch (e) {
      debugPrint('[GST export] $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not share the file.')));
      }
    }
  }

  static int _i(Object? v) => (v as num?)?.toInt() ?? 0;
  static Map<String, dynamic> _m(Object? v) => Map<String, dynamic>.from((v as Map?) ?? <String, dynamic>{});
  static List<Map<String, dynamic>> _l(Object? v) => <Map<String, dynamic>>[
        for (final Object? o in (v as List<dynamic>?) ?? <dynamic>[])
          if (o is Map) Map<String, dynamic>.from(o),
      ];

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic>? r = _report;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('GST returns')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + MediaQuery.paddingOf(context).bottom),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.statusAmberBg,
              borderRadius: BorderRadius.circular(AppRadii.card),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.info_outline, color: AppColors.ink),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'For review by your CA. These summaries are worked out from your bills and '
                    'purchases in Meddata; they are not filed with the GST portal. Share the CSV '
                    'with your CA before filing.',
                    style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<DateTime>(
            initialValue: _month,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Month'),
            items: <DropdownMenuItem<DateTime>>[
              for (final DateTime m in _months)
                DropdownMenuItem<DateTime>(value: m, child: Text(DateFormat('MMMM yyyy').format(m))),
            ],
            onChanged: (DateTime? m) {
              if (m == null) return;
              setState(() => _month = m);
              _load();
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: <Widget>[
              for (final (bool one, String label) in <(bool, String)>[(true, 'GSTR-1'), (false, 'GSTR-3B')])
                AccountsPill(
                  label: label,
                  selected: _gstr1 == one,
                  onTap: () {
                    setState(() {
                      _gstr1 = one;
                      _report = null;
                    });
                    _load();
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_failure != null)
            SizedBox(
              height: 360,
              child: AccountsOfflineNotice(onRetry: _load, offline: _failure!.isOffline, message: _failure!.message),
            )
          else if (r == null || _loading)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          else ...<Widget>[
            if (r['registered'] != true)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Your shop has no GSTIN in Shop & invoice details.',
                    style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.statusRed)),
              ),
            ...(_gstr1 ? _gstr1View(r) : _gstr3bView(r)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                ElevatedButton.icon(
                  style: inkOnOrange.merge(ElevatedButton.styleFrom(minimumSize: const Size(0, 48))),
                  onPressed: () => _export(true),
                  icon: const Icon(Icons.table_view_outlined, size: 20),
                  label: const Text('Share CSV'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: () => _export(false),
                  icon: const Icon(Icons.data_object, size: 20),
                  label: const Text('Share JSON'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _card(String title, List<Widget> rows) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            BillingSectionLabel(title),
            BillingCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows)),
          ],
        ),
      );

  List<Widget> _taxRows(Map<String, dynamic> v, {bool taxable = true}) => <Widget>[
        if (taxable) AmountRow('Taxable value', Inr.format(_i(v['taxable_paise']))),
        AmountRow('IGST', Inr.format(_i(v['igst_paise']))),
        AmountRow('CGST', Inr.format(_i(v['cgst_paise']))),
        AmountRow('SGST', Inr.format(_i(v['sgst_paise']))),
      ];

  Map<String, int> _sumRates(Iterable<Map<String, dynamic>> rows) {
    final Map<String, int> s = <String, int>{'taxable_paise': 0, 'igst_paise': 0, 'cgst_paise': 0, 'sgst_paise': 0};
    for (final Map<String, dynamic> r in rows) {
      for (final String k in s.keys.toList()) {
        s[k] = s[k]! + _i(r[k]);
      }
    }
    return s;
  }

  List<Widget> _gstr1View(Map<String, dynamic> r) {
    final List<Map<String, dynamic>> b2b = _l(r['b2b']);
    final List<Map<String, dynamic>> b2cl = _l(r['b2cl']);
    final List<Map<String, dynamic>> notes = <Map<String, dynamic>>[..._l(r['cdnr']), ..._l(r['cdnur'])];
    final Map<String, dynamic> net = _m(_m(r['summary'])['net']);
    final List<Map<String, dynamic>> hsn = <Map<String, dynamic>>[..._l(_m(r['hsn'])['b2b']), ..._l(_m(r['hsn'])['b2c'])];
    return <Widget>[
      _card('Net for the month', <Widget>[
        AmountRow('Bills', '${_i(_m(_m(r['summary'])['bills'])['count'])}'),
        AmountRow('Credit notes', '${_i(_m(_m(r['summary'])['credit_notes'])['count'])}'),
        ..._taxRows(net),
      ]),
      _card('B2B - to GST-registered customers', <Widget>[
        if (b2b.isEmpty) const Text('None', style: TextStyle(color: AppColors.muted)),
        for (final Map<String, dynamic> g in b2b)
          AmountRow('${g['name'] ?? g['gstin']} · ${_i(g['invoice_count'])} inv.', Inr.format(_i(g['taxable_paise']))),
      ]),
      _card('B2C large - inter-state above ₹1 lakh', <Widget>[
        if (b2cl.isEmpty) const Text('None', style: TextStyle(color: AppColors.muted)),
        for (final Map<String, dynamic> inv in b2cl)
          AmountRow('${inv['invoice_no']} · ${GstStates.label('${inv['place_of_supply']}')}',
              Inr.format(_i(inv['invoice_value_paise']))),
      ]),
      _card('B2C small', <Widget>[
        for (final Map<String, dynamic> b in _l(r['b2cs']))
          AmountRow('${GstStates.label('${b['place_of_supply']}')} · ${Inr.percent(_i(b['gst_rate_bp']))}',
              Inr.format(_i(b['taxable_paise']))),
        if (_l(r['b2cs']).isEmpty) const Text('None', style: TextStyle(color: AppColors.muted)),
      ]),
      _card('Credit notes (registered / B2C large)', <Widget>[
        if (notes.isEmpty) const Text('None', style: TextStyle(color: AppColors.muted)),
        for (final Map<String, dynamic> n in notes)
          AmountRow('${n['note_no']} against ${n['invoice_no'] ?? '-'}', Inr.format(_i(n['note_value_paise']))),
      ]),
      _card('HSN summary', <Widget>[
        AmountRow('HSN rows', '${hsn.length}'),
        ..._taxRows(_sumRates(hsn)),
      ]),
      _card('Documents issued', <Widget>[
        for (final Map<String, dynamic> d in _l(r['documents']))
          AmountRow('${d['nature']}${d['from'] == null ? '' : ' (${d['from']} - ${d['to']})'}',
              '${_i(d['net_issued'])} + ${_i(d['cancelled'])} cancelled'),
      ]),
    ];
  }

  List<Widget> _gstr3bView(Map<String, dynamic> r) {
    final Map<String, dynamic> itc = _m(r['itc']);
    final Map<String, dynamic> pay = _m(r['payment']);
    final Map<String, dynamic> cash = _m(pay['cash_payable']);
    return <Widget>[
      _card('3.1 Outward taxable supplies', _taxRows(_m(r['outward_taxable']))),
      _card('Nil rated', <Widget>[AmountRow('Value', Inr.format(_i(_m(r['outward_nil_rated'])['taxable_paise'])))]),
      _card('4 Input tax credit (purchases)', <Widget>[
        const Text('Available', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
        ..._taxRows(_m(itc['available']), taxable: false),
        const Divider(),
        const Text('Reversed (debit notes)', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
        ..._taxRows(_m(itc['reversed']), taxable: false),
        const Divider(),
        const Text('Net ITC', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
        ..._taxRows(_m(itc['net']), taxable: false),
      ]),
      _card('Tax to pay in cash (after ITC)', <Widget>[
        ..._taxRows(cash, taxable: false),
        const Divider(height: 18),
        AmountRow('Total', Inr.format(_i(cash['total_paise'])), strong: true, big: true),
        AmountRow('ITC carried forward', Inr.format(_i(_m(pay['itc_carried_forward'])['total_paise']))),
      ]),
    ];
  }
}
