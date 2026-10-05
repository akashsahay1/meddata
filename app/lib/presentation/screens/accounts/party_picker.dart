import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/models/accounting.dart';
import '../../../services/accounting_api.dart';
import '../../../services/auth_service.dart';
import '../../../services/billing_api.dart';
import '../../../theme/app_theme.dart';
import 'accounts_widgets.dart';
import 'party_form_screen.dart';

/// Choose a customer (or supplier) account, or add a new one. Resolves to
/// null when closed without choosing. [name], [phone] and [gstin] fill a
/// new party (e.g. what was typed on the bill, or read from an invoice).
Future<Party?> pickParty(
  BuildContext context, {
  required bool suppliers,
  AccountingApi? api,
  String? name,
  String? phone,
  String? gstin,
}) {
  return showModalBottomSheet<Party>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext ctx) => _PartyPicker(
      suppliers: suppliers,
      api: api ?? AccountingApi(),
      name: name,
      phone: phone,
      gstin: gstin,
    ),
  );
}

class _PartyPicker extends StatefulWidget {
  const _PartyPicker({required this.suppliers, required this.api, this.name, this.phone, this.gstin});

  final bool suppliers;
  final AccountingApi api;
  final String? name;
  final String? phone;
  final String? gstin;

  @override
  State<_PartyPicker> createState() => _PartyPickerState();
}

class _PartyPickerState extends State<_PartyPicker> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  List<Party> _parties = <Party>[];
  bool _loading = true;
  ApiOutcome<ApiPage<Party>>? _failure;
  int _request = 0;

  String get _noun => widget.suppliers ? 'supplier' : 'customer';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final String? token = context.read<AuthService>().token;
    if (token == null) return;
    final int request = ++_request;
    setState(() => _loading = true);
    final ApiOutcome<ApiPage<Party>> r = await widget.api.parties(token,
        type: widget.suppliers ? 'supplier' : 'customer', query: _search.text, perPage: 100);
    if (!mounted || request != _request) return;
    setState(() {
      _loading = false;
      _failure = r.isOk ? null : r;
      _parties = r.value?.items ?? <Party>[];
    });
  }

  Future<void> _addNew() async {
    final NavigatorState nav = Navigator.of(context);
    final String typed = _search.text.trim();
    final Party? created = await nav.push<Party>(MaterialPageRoute<Party>(
      builder: (_) => PartyFormScreen(
        type: widget.suppliers ? PartyType.supplier : PartyType.customer,
        name: typed.isNotEmpty && !RegExp(r'^[0-9+\s-]+$').hasMatch(typed) ? typed : widget.name,
        phone: widget.phone,
        gstin: widget.gstin,
        api: widget.api,
      ),
    ));
    if (created != null && mounted) nav.pop(created);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Text('Choose $_noun',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.ink)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _search,
                  onChanged: (_) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 300), _load);
                  },
                  decoration: const InputDecoration(
                    hintText: 'Search name, phone or GSTIN',
                    prefixIcon: Icon(Icons.search, size: 20),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.person_add_alt_1_outlined, color: AppColors.green),
                title: Text('Add new $_noun', style: const TextStyle(fontWeight: FontWeight.w700)),
                onTap: _addNew,
              ),
              const Divider(height: 1),
              Flexible(
                child: _failure != null
                    ? AccountsOfflineNotice(onRetry: _load, offline: _failure!.isOffline, message: _failure!.message)
                    : _loading && _parties.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : _parties.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text('No ${_noun}s found.',
                                    textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
                              )
                            : ListView(
                                shrinkWrap: true,
                                children: <Widget>[
                                  for (final Party p in _parties)
                                    ListTile(
                                      title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                      subtitle: p.subtitle.isEmpty ? null : Text(p.subtitle),
                                      trailing: BalanceLabel(p.balancePaise),
                                      onTap: () => Navigator.of(context).pop(p),
                                    ),
                                ],
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
