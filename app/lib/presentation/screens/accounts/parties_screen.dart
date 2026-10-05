import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/inr.dart';
import '../../../data/models/accounting.dart';
import '../../../services/accounting_api.dart';
import '../../../services/auth_service.dart';
import '../../../services/billing_api.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/ui_kit.dart';
import 'accounts_widgets.dart';
import 'party_detail_screen.dart';
import 'party_form_screen.dart';

enum _Filter { all, customers, suppliers }

/// Customers and suppliers with what each owes / is owed, searchable.
class PartiesScreen extends StatefulWidget {
  const PartiesScreen({super.key, this.api});

  final AccountingApi? api;

  @override
  State<PartiesScreen> createState() => _PartiesScreenState();
}

class _PartiesScreenState extends State<PartiesScreen> {
  late final AccountingApi _api = (widget.api ?? AccountingApi())
    ..onUnauthorized = context.read<AuthService>().sessionRejected;
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  _Filter _filter = _Filter.all;
  List<Party> _parties = <Party>[];
  bool _loading = true;
  ApiOutcome<ApiPage<Party>>? _failure;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final String? token = context.read<AuthService>().token;
    if (token == null) {
      setState(() {
        _loading = false;
        _failure = const ApiOutcome<ApiPage<Party>>.failed(401, 'Please log in again.');
      });
      return;
    }
    final int request = ++_request;
    setState(() => _loading = true);
    final ApiOutcome<ApiPage<Party>> r = await _api.parties(token,
        type: switch (_filter) {
          _Filter.all => null,
          _Filter.customers => 'customer',
          _Filter.suppliers => 'supplier',
        },
        query: _search.text,
        perPage: 200);
    if (!mounted || request != _request) return;
    setState(() {
      _loading = false;
      _failure = r.isOk ? null : r;
      if (r.isOk) _parties = r.value!.items;
    });
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute<Object?>(builder: (_) => screen));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final int collect = _parties.where((Party p) => p.balancePaise > 0).fold(0, (int s, Party p) => s + p.balancePaise);
    final int pay = _parties.where((Party p) => p.balancePaise < 0).fold(0, (int s, Party p) => s - p.balancePaise);
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('Parties')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(PartyFormScreen(
          api: _api,
          type: _filter == _Filter.suppliers ? PartyType.supplier : PartyType.customer,
        )),
        foregroundColor: AppColors.ink,
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Add party'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _search,
              onChanged: (_) {
                setState(() {});
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 300), _load);
              },
              decoration: InputDecoration(
                hintText: 'Search name, phone or GSTIN',
                prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.muted),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _search.clear();
                          _load();
                        },
                      ),
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(
              children: <Widget>[
                for (final (_Filter f, String label) in <(_Filter, String)>[
                  (_Filter.all, 'All'),
                  (_Filter.customers, 'Customers'),
                  (_Filter.suppliers, 'Suppliers'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: AccountsPill(
                      label: label,
                      selected: _filter == f,
                      onTap: () {
                        setState(() => _filter = f);
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _failure != null
                ? AccountsOfflineNotice(onRetry: _load, offline: _failure!.isOffline, message: _failure!.message)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 96 + MediaQuery.paddingOf(context).bottom),
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(child: StatCard(label: 'To collect', value: Inr.format(collect))),
                            const SizedBox(width: 10),
                            Expanded(child: StatCard(label: 'To pay', value: Inr.format(pay))),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_loading && _parties.isEmpty)
                          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
                        else if (_parties.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 36),
                            child: Column(
                              children: <Widget>[
                                Icon(Icons.people_outline, size: 48, color: AppColors.muted),
                                SizedBox(height: 10),
                                Text('No parties yet',
                                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.ink)),
                                SizedBox(height: 4),
                                Text('Add the customers who buy on credit and your suppliers.',
                                    textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
                              ],
                            ),
                          ),
                        for (final Party p in _parties)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _PartyTile(
                              party: p,
                              onTap: () => _open(PartyDetailScreen(partyId: p.id, api: _api)),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PartyTile extends StatelessWidget {
  const _PartyTile({required this.party, required this.onTap});

  final Party party;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(party.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink)),
                    const SizedBox(height: 2),
                    Text(
                      <String>[party.type.label, if (party.phone != null) party.phone!].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Flexible(child: BalanceLabel(party.balancePaise)),
            ],
          ),
        ),
      ),
    );
  }
}
