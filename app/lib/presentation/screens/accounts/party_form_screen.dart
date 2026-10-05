import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/inr.dart';
import '../../../data/models/accounting.dart';
import '../../../domain/gst.dart';
import '../../../services/accounting_api.dart';
import '../../../services/auth_service.dart';
import '../../../theme/app_theme.dart';
import '../billing/billing_widgets.dart';
import 'accounts_widgets.dart';

/// Add or edit a customer / supplier. Pops with the saved [Party].
class PartyFormScreen extends StatefulWidget {
  const PartyFormScreen({
    super.key,
    this.party,
    this.type = PartyType.customer,
    this.name,
    this.phone,
    this.gstin,
    this.api,
  });

  /// The party to edit (null: a new one).
  final Party? party;

  /// For a new party: its type and details to start from (e.g. from a bill
  /// or a scanned supplier invoice).
  final PartyType type;
  final String? name;
  final String? phone;
  final String? gstin;
  final AccountingApi? api;

  @override
  State<PartyFormScreen> createState() => _PartyFormScreenState();
}

class _PartyFormScreenState extends State<PartyFormScreen> {
  late final AccountingApi _api = (widget.api ?? AccountingApi())
    ..onUnauthorized = context.read<AuthService>().sessionRejected;
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(
    text: widget.party?.name ?? widget.name ?? '',
  );
  late final TextEditingController _phone = TextEditingController(
    text: widget.party?.phone ?? widget.phone ?? '',
  );
  late final TextEditingController _gstin = TextEditingController(
    text: widget.party?.gstin ?? widget.gstin ?? '',
  );
  late final TextEditingController _address = TextEditingController(
    text: widget.party?.address ?? '',
  );
  late final TextEditingController _notes = TextEditingController(
    text: widget.party?.notes ?? '',
  );
  late final TextEditingController _opening = TextEditingController(
    text: (widget.party?.openingBalancePaise ?? 0) == 0
        ? ''
        : Inr.format(
            widget.party!.openingBalancePaise.abs(),
            symbol: false,
          ).replaceAll(',', ''),
  );

  late PartyType _type = widget.party?.type ?? widget.type;
  late String? _state = widget.party?.stateCode;

  /// Opening balance: true = they owe the shop.
  late bool _theyOwe = switch (widget.party?.openingBalancePaise ?? 0) {
    0 => _type != PartyType.supplier,
    final int v => v > 0,
  };

  /// Same id on a retry after no answer, so the party isn't added twice.
  final String _newId = const Uuid().v4();

  /// The user picked "They owe me" / "I owe them" themselves.
  bool _oweChosen = false;
  bool _saving = false;
  Map<String, String> _serverErrors = <String, String>{};

  bool get _editing => widget.party != null;

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _name,
      _phone,
      _gstin,
      _address,
      _notes,
      _opening,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _gstinValue => Gstin.normalize(_gstin.text);

  Future<void> _save() async {
    setState(() => _serverErrors = <String, String>{});
    if (!_form.currentState!.validate()) return;
    final String? token = context.read<AuthService>().token;
    if (token == null) return;
    final int opening = parseRupees(_opening.text) ?? 0;
    final String gstin = _gstinValue;
    final Map<String, Object?> data = <String, Object?>{
      if (!_editing) 'id': _newId,
      'type': _type.name,
      'name': _name.text.trim(),
      'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      'gstin': gstin.isEmpty ? null : gstin,
      'state_code': gstin.isEmpty ? _state : Gstin.stateOf(gstin),
      'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
      'opening_balance_paise': _theyOwe ? opening : -opening,
      'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    };
    setState(() => _saving = true);
    final DocResult<Party> r = await _api.saveParty(
      token,
      data,
      id: widget.party?.id,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (r.isOk) {
      Navigator.of(context).pop(r.value);
      return;
    }
    final Object? errors = r.body?['errors'];
    if (errors is Map && errors.isNotEmpty) {
      setState(
        () => _serverErrors = <String, String>{
          for (final MapEntry<Object?, Object?> e in errors.entries)
            '${e.key}': e.value is List && (e.value! as List).isNotEmpty
                ? '${(e.value! as List).first}'
                : '${e.value}',
        },
      );
      _form.currentState!.validate();
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            r.isOffline
                ? 'No internet - the party was not saved. Try again when online.'
                : (r.message ?? 'Could not save.'),
          ),
        ),
      );
  }

  String? _server(String key) => _serverErrors[key];

  @override
  Widget build(BuildContext context) {
    final String gstin = _gstinValue;
    final bool gstinOk = gstin.length == 15 && Gstin.isValid(gstin);
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(_editing ? 'Edit party' : 'New party')),
      body: Form(
        key: _form,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            32 + MediaQuery.paddingOf(context).bottom,
          ),
          children: <Widget>[
            const BillingSectionLabel('Type'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final PartyType t in PartyType.values)
                  AccountsPill(
                    label: t.label,
                    selected: _type == t,
                    onTap: () => setState(() {
                      _type = t;
                      // A new party's balance side follows its type until chosen.
                      if (!_oweChosen && widget.party == null) {
                        _theyOwe = t != PartyType.supplier;
                      }
                    }),
                  ),
              ],
            ),
            const BillingSectionLabel('Details'),
            TextFormField(
              controller: _name,
              maxLength: 100,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
                counterText: '',
              ),
              validator: (String? v) =>
                  (v ?? '').trim().isEmpty ? 'Enter a name' : _server('name'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _phone,
              maxLength: 20,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone (optional)',
                counterText: '',
              ),
              validator: (String? v) {
                final String t = (v ?? '').trim();
                if (t.isNotEmpty &&
                    !RegExp(r'^[0-9+\-\s()]{6,20}$').hasMatch(t)) {
                  return 'Not a valid phone number';
                }
                return _server('phone');
              },
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _gstin,
              maxLength: 15,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp('[0-9A-Za-z]')),
                TextInputFormatter.withFunction(
                  (TextEditingValue _, TextEditingValue v) =>
                      v.copyWith(text: v.text.toUpperCase()),
                ),
              ],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'GSTIN (optional)',
                counterText: '',
                helperText: gstinOk
                    ? 'State: ${GstStates.label(gstin.substring(0, 2))}'
                    : null,
              ),
              validator: (String? v) {
                final String g = Gstin.normalize(v ?? '');
                if (g.isNotEmpty && !Gstin.isValid(g)) {
                  return 'Not a valid GSTIN - check it';
                }
                return _server('gstin');
              },
            ),
            if (!gstinOk) ...<Widget>[
              const SizedBox(height: 10),
              DropdownButtonFormField<String?>(
                initialValue: _state,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'State (optional)',
                  errorText: _server('state_code'),
                ),
                items: <DropdownMenuItem<String?>>[
                  const DropdownMenuItem<String?>(
                    child: Text('Not set (same as shop)'),
                  ),
                  for (final MapEntry<String, String> e
                      in GstStates.all.entries)
                    DropdownMenuItem<String?>(
                      value: e.key,
                      child: Text('${e.key} - ${e.value}'),
                    ),
                ],
                onChanged: (String? v) => setState(() => _state = v),
              ),
            ],
            const SizedBox(height: 10),
            TextFormField(
              controller: _address,
              minLines: 1,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Address (optional)',
                counterText: '',
              ),
            ),
            const BillingSectionLabel('Opening balance'),
            TextFormField(
              controller: _opening,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: rupeeInput,
              decoration: const InputDecoration(
                labelText: 'Amount (₹)',
                hintText: '0.00',
              ),
              validator: (String? v) =>
                  (v ?? '').trim().isNotEmpty && parseRupees(v!) == null
                  ? 'Enter an amount'
                  : _server('opening_balance_paise'),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                AccountsPill(
                  label: 'They owe me',
                  selected: _theyOwe,
                  onTap: () => setState(() {
                    _theyOwe = true;
                    _oweChosen = true;
                  }),
                ),
                AccountsPill(
                  label: 'I owe them',
                  selected: !_theyOwe,
                  onTap: () => setState(() {
                    _theyOwe = false;
                    _oweChosen = true;
                  }),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'What was due before you started using Meddata.',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _notes,
              minLines: 1,
              maxLines: 4,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                counterText: '',
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: inkOnOrange,
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving…' : 'Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
