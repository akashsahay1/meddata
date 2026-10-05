import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../data/models/bill.dart';
import '../../../domain/gst.dart';
import '../../../services/auth_service.dart';
import '../../../services/billing_api.dart';
import '../../../theme/app_theme.dart';
import 'billing_widgets.dart';

/// The shop's details printed on its invoices: names, GSTIN and state,
/// address, phone, drug licence no., invoice prefix, and the GST rate for
/// medicines that have none set. Saved on the server (all devices share it).
class ShopSettingsScreen extends StatefulWidget {
  const ShopSettingsScreen({super.key, this.api});

  final BillingApi? api;

  @override
  State<ShopSettingsScreen> createState() => _ShopSettingsScreenState();
}

class _ShopSettingsScreenState extends State<ShopSettingsScreen> {
  late final BillingApi _api = widget.api ?? BillingApi();
  final GlobalKey<FormState> _form = GlobalKey<FormState>();

  final TextEditingController _name = TextEditingController();
  final TextEditingController _legalName = TextEditingController();
  final TextEditingController _gstin = TextEditingController();
  final TextEditingController _address = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _license = TextEditingController();
  final TextEditingController _prefix = TextEditingController();
  String? _state;
  int _defaultGst = 500;

  bool _loading = true;
  bool _saving = false;
  ApiOutcome<ShopProfile>? _failure;

  static const List<int> _rates = <int>[0, 500, 1200, 1800, 2800];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _name, _legalName, _gstin, _address, _phone, _license, _prefix,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final String? token = context.read<AuthService>().token;
    if (token == null) return;
    setState(() => _loading = true);
    final ApiOutcome<ShopProfile> r = await _api.shop(token);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _failure = r.isOk ? null : r;
      if (r.isOk) _fill(r.value!);
    });
  }

  void _fill(ShopProfile s) {
    _name.text = s.name;
    _legalName.text = s.legalName ?? '';
    _gstin.text = s.gstin ?? '';
    _address.text = s.address ?? '';
    _phone.text = s.phone ?? '';
    _license.text = s.drugLicenseNo ?? '';
    _prefix.text = s.invoicePrefix ?? '';
    _state = s.stateCode;
    _defaultGst = s.defaultGstRateBp;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final String? token = context.read<AuthService>().token;
    if (token == null) return;
    String? opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    setState(() => _saving = true);
    final ApiOutcome<ShopProfile> r = await _api.updateShop(token, <String, Object?>{
      'name': _name.text.trim(),
      'legal_name': opt(_legalName),
      'gstin': opt(_gstin),
      'state_code': _state,
      'address': opt(_address),
      'phone': opt(_phone),
      'drug_license_no': opt(_license),
      'invoice_prefix': opt(_prefix),
      'default_gst_rate_bp': _defaultGst,
    });
    if (!mounted) return;
    setState(() => _saving = false);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (!r.isOk) {
      messenger.showSnackBar(SnackBar(
          content: Text(r.isOffline
              ? 'No internet - the details were not saved.'
              : (r.message ?? 'Could not save the details.'))));
      return;
    }
    messenger.showSnackBar(const SnackBar(content: Text('Invoice details saved')));
    Navigator.of(context).maybePop();
  }

  void _onGstin(String v) {
    final String g = Gstin.normalize(v);
    if (Gstin.isValid(g)) setState(() => _state = g.substring(0, 2));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('Shop & invoice details')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failure != null
              ? BillingOfflineNotice(
                  onRetry: _load, offline: _failure!.isOffline, message: _failure!.message)
              : _formBody(),
    );
  }

  Widget _formBody() {
    final String code = _prefix.text.trim().isEmpty ? 'INV' : _prefix.text.trim().toUpperCase();
    final String prefix = '$code/${GstMath.financialYear(DateTime.now())}';
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Form(
          key: _form,
          child: ListView(
            padding: EdgeInsets.fromLTRB(18, 8, 18, 32 + MediaQuery.paddingOf(context).bottom),
            children: <Widget>[
              const Text(
                'Printed on your GST invoices. Bills already made keep the details they were printed with.',
                style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w500),
              ),
              const BillingSectionLabel('Business'),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Shop name *'),
                validator: (String? v) => (v ?? '').trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _legalName,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                    labelText: 'Legal name', helperText: 'Registered business name, if different'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _address,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Address'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _license,
                decoration: const InputDecoration(labelText: 'Drug licence no.'),
              ),
              const BillingSectionLabel('GST'),
              TextFormField(
                controller: _gstin,
                maxLength: 15,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp('[0-9A-Za-z]')),
                  TextInputFormatter.withFunction((TextEditingValue _, TextEditingValue v) =>
                      v.copyWith(text: v.text.toUpperCase())),
                ],
                onChanged: _onGstin,
                decoration: const InputDecoration(labelText: 'GSTIN', counterText: ''),
                validator: (String? v) {
                  final String g = Gstin.normalize(v ?? '');
                  return g.isEmpty || Gstin.isValid(g) ? null : 'Not a valid GSTIN - check it';
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                key: ValueKey<String?>(_state),
                initialValue: _state,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'State'),
                items: <DropdownMenuItem<String?>>[
                  const DropdownMenuItem<String?>(child: Text('Not set')),
                  for (final MapEntry<String, String> e in GstStates.all.entries)
                    DropdownMenuItem<String?>(value: e.key, child: Text('${e.key} - ${e.value}')),
                ],
                onChanged: (String? v) => setState(() => _state = v),
                validator: (String? v) {
                  final String g = Gstin.normalize(_gstin.text);
                  if (Gstin.isValid(g) && v != null && v != g.substring(0, 2)) {
                    return 'Must match the GSTIN (${GstStates.label(g.substring(0, 2))})';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _rates.contains(_defaultGst) ? _defaultGst : null,
                decoration: const InputDecoration(
                  labelText: 'GST rate for medicines without one',
                  helperText: 'Set a rate on a medicine to override this',
                ),
                items: <DropdownMenuItem<int>>[
                  for (final int r in _rates)
                    DropdownMenuItem<int>(value: r, child: Text('${r ~/ 100}%')),
                ],
                onChanged: (int? v) => setState(() => _defaultGst = v ?? _defaultGst),
              ),
              const BillingSectionLabel('Invoice numbers'),
              TextFormField(
                controller: _prefix,
                maxLength: 3,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp('[0-9A-Za-z]')),
                ],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Invoice prefix',
                  hintText: 'INV',
                  helperText: 'Bills are numbered $prefix/000001, $prefix/000002, ... '
                      'starting again each April.',
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving…' : 'Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
