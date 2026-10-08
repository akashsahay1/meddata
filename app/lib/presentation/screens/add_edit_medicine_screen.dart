import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../core/platform.dart';
import '../../core/formatters.dart';
import '../../data/models/medicine.dart';
import '../../domain/pack_size.dart';
import '../../domain/product_stock.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../state/medicine_provider.dart';
import '../../theme/app_theme.dart';
import '../widgets/ui_kit.dart';
import 'barcode_scan_screen.dart';
import 'invoice_scan_screen.dart';
import 'upgrade_screen.dart';

class AddEditMedicineScreen extends StatefulWidget {
  final Medicine? existing;

  /// Add a new batch of this medicine: product details are prefilled, the
  /// batch fields (batch no, quantity, dates) start empty.
  final Medicine? newBatchOf;

  /// New medicine from a scan: the barcode to fill in, and the master-catalog
  /// entry it matched (if any) to prefill the product details from.
  final String? initialBarcode;
  final Map<String, dynamic>? catalogMatch;

  /// Backend for the name typeahead and barcode lookup (tests pass a fake).
  final ApiClient? api;
  const AddEditMedicineScreen({
    super.key,
    this.existing,
    this.newBatchOf,
    this.initialBarcode,
    this.catalogMatch,
    this.api,
  });

  @override
  State<AddEditMedicineScreen> createState() => _AddEditMedicineScreenState();
}

class _AddEditMedicineScreenState extends State<AddEditMedicineScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _brand;
  late final TextEditingController _batch;
  late final TextEditingController _barcode;
  late final TextEditingController _quantity;

  /// Pieces per pack (tablets per strip); blank = 1. With a pack size of
  /// more than one and a unit that counts pieces, stock is entered as
  /// [_packs] + [_loose] and prices per pack ([_packsMode]); stored values
  /// are always per piece.
  late final TextEditingController _packSize;
  late final TextEditingController _packs;
  late final TextEditingController _loose;
  bool _packsMode = false;

  /// The pack size the packs/loose and per-pack price fields are written
  /// in while [_packsMode] is on (kept while the field is being retyped).
  int _modePackSize = 1;
  late final TextEditingController _lowStock;
  late final TextEditingController _purchase;
  late final TextEditingController _selling;
  late final TextEditingController _notes;
  late final TextEditingController _hsn;

  /// GST rate of the product in basis points; null = the shop's default.
  int? _gstRateBp;

  String _unit = 'Tablets';
  String _category = 'Uncategorised';
  DateTime? _mfgDate;
  DateTime _expiryDate = DateTime.now().add(const Duration(days: 365));

  // Medicine-name autocomplete against the backend master list.
  late final ApiClient _api = widget.api ?? ApiClient();
  final FocusNode _nameFocus = FocusNode();
  Timer? _searchDebounce;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final Medicine? m = widget.existing ?? widget.newBatchOf;
    final bool batchOnly = widget.existing == null && widget.newBatchOf != null;
    _name = TextEditingController(text: m?.name ?? '');
    _brand = TextEditingController(text: m?.brand ?? '');
    _batch = TextEditingController(text: batchOnly ? '' : (m?.batchNo ?? ''));
    _barcode = TextEditingController(text: m?.barcode ?? '');
    _quantity = TextEditingController(
        text: batchOnly ? '' : (m?.quantity.toString() ?? ''));
    _lowStock = TextEditingController(
        text: (m?.lowStockThreshold ?? AppConstants.defaultLowStockThreshold)
            .toString());
    _purchase = TextEditingController(
        text: (m != null && m.purchasePrice > 0)
            ? m.purchasePrice.toString()
            : '');
    _selling = TextEditingController(
        text: (m != null && m.sellingPrice > 0)
            ? m.sellingPrice.toString()
            : '');
    _notes = TextEditingController(text: m?.notes ?? '');
    _hsn = TextEditingController(text: m?.hsn ?? '');
    _gstRateBp = m?.gstRateBp;
    _unit = m?.unit ?? 'Tablets';
    _packSize = TextEditingController(
        text: (m?.packSize ?? 1) > 1 ? '${m!.packSize}' : '');
    _packs = TextEditingController();
    _loose = TextEditingController();
    _syncMode();
    final String stored = m?.category.trim() ?? '';
    _category = stored.isEmpty ? 'Uncategorised' : stored;
    _mfgDate = batchOnly ? null : m?.mfgDate;
    if (m != null && !batchOnly) _expiryDate = m.expiryDate;
    if (m == null) {
      _barcode.text = widget.initialBarcode?.trim() ?? '';
      if (widget.catalogMatch != null) _applyCatalog(widget.catalogMatch!);
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _nameFocus.dispose();
    for (final TextEditingController c in <TextEditingController>[
      _name, _brand, _batch, _barcode, _quantity, _packSize, _packs, _loose,
      _lowStock, _purchase, _selling, _notes, _hsn,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  int get _packSizeValue =>
      (int.tryParse(_packSize.text.trim()) ?? 1).clamp(1, PackSize.max);

  /// Stock typed as packs + loose pieces, in pieces.
  int _packsTotal() =>
      (int.tryParse(_packs.text.trim()) ?? 0) * _modePackSize +
      (int.tryParse(_loose.text.trim()) ?? 0);

  /// Stock in pieces as typed, in either mode.
  int get _quantityValue =>
      _packsMode ? _packsTotal() : (int.tryParse(_quantity.text.trim()) ?? 0);

  /// Switch the stock and price fields between pieces and packs when the
  /// unit or pack size changes, keeping what was typed. A [keepSelling]
  /// price is already per pack (the catalog lists pack prices).
  void _syncMode({bool keepSelling = false}) {
    final int ps = _packSizeValue;
    final bool packs = PackSize.applies(_unit, ps);
    final List<TextEditingController> prices = <TextEditingController>[
      _purchase,
      if (!keepSelling) _selling,
    ];
    void scale(double Function(double) f) {
      for (final TextEditingController c in prices) {
        final double? v = double.tryParse(c.text.trim());
        if (v != null) c.text = _money(f(v));
      }
    }

    if (packs == _packsMode) {
      if (packs) _modePackSize = ps;
      return;
    }
    if (packs) {
      final String typed = _quantity.text.trim();
      final (int p, int l) = PackSize.split(int.tryParse(typed) ?? 0, ps);
      _packs.text = typed.isEmpty ? '' : '$p';
      _loose.text = l == 0 ? '' : '$l';
      scale((double v) => v * ps);
      _modePackSize = ps;
    } else {
      final bool blank =
          _packs.text.trim().isEmpty && _loose.text.trim().isEmpty;
      _quantity.text = blank ? '' : '${_packsTotal()}';
      scale((double v) => v / _modePackSize);
    }
    _packsMode = packs;
  }

  /// A price for a field: paise shown only when there are some.
  static String _money(double v) {
    final String s = v.toStringAsFixed(2);
    return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
  }

  /// Manufacture date can't be in the future and must fall before expiry;
  /// expiry must fall after the manufacture date. The pickers are bounded
  /// accordingly and [_dateError] re-checks on save.
  Future<void> _pickDate({required bool isExpiry}) async {
    final DateTime today = _day(DateTime.now());
    final DateTime earliest = DateTime(2000);
    final DateTime latest = DateTime(2100);
    final DateTime first;
    final DateTime last;
    DateTime initial;
    if (isExpiry) {
      first = _mfgDate == null
          ? earliest
          : _day(_mfgDate!).add(const Duration(days: 1));
      last = latest;
      initial = _expiryDate;
    } else {
      final DateTime beforeExpiry =
          _day(_expiryDate).subtract(const Duration(days: 1));
      last = beforeExpiry.isBefore(today) ? beforeExpiry : today;
      first = earliest;
      initial = _mfgDate ?? last;
    }
    if (last.isBefore(first)) {
      _showDateError(isExpiry
          ? 'No valid expiry date after this manufacture date.'
          : 'Set a later expiry date first.');
      return;
    }
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (picked != null) {
      setState(() {
        if (isExpiry) {
          _expiryDate = picked;
        } else {
          _mfgDate = picked;
        }
      });
    }
  }

  /// Null when the dates are consistent, otherwise a message for the user.
  String? _dateError() {
    final DateTime? mfg = _mfgDate == null ? null : _day(_mfgDate!);
    if (mfg == null) return null;
    if (mfg.isAfter(_day(DateTime.now()))) {
      return "Manufacture date can't be in the future.";
    }
    if (!mfg.isBefore(_day(_expiryDate))) {
      return 'Expiry date must be after the manufacture date.';
    }
    return null;
  }

  void _showDateError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _scanBarcode() async {
    final String? code = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const BarcodeScanScreen()),
    );
    if (code != null && code.isNotEmpty) {
      setState(() => _barcode.text = code);
      await _lookupBarcode(code);
    }
  }

  /// Only a brand-new medicine looks its barcode up; editing a product or
  /// adding a batch keeps the details already chosen.
  bool get _isNewProduct => widget.existing == null && widget.newBatchOf == null;

  /// After a scan (or Enter from a USB scanner): if the shop already has this
  /// barcode, offer to add a batch to it instead; otherwise prefill the form
  /// from the master catalog.
  Future<void> _lookupBarcode(String raw) async {
    final String code = raw.trim();
    if (!mounted || !_isNewProduct || code.isEmpty) return;
    final ProductStock? own =
        context.read<MedicineProvider>().productByBarcode(code);
    if (own != null) {
      final bool addBatch = await _confirmAddBatch(own) ?? false;
      if (!addBatch || !mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) =>
            AddEditMedicineScreen(newBatchOf: own.first, api: widget.api),
      ));
      return;
    }
    final String? token = context.read<AuthService>().token;
    final Map<String, dynamic>? match =
        await _api.lookupBarcode(code, token: token);
    if (!mounted || match == null) return;
    // Don't overwrite a name the user has already typed without asking.
    if (_name.text.trim().isEmpty) {
      setState(() => _applyCatalog(match));
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Barcode matches ${match['name'] ?? 'a catalog medicine'}'),
        action: SnackBarAction(
          label: 'Use',
          onPressed: () => setState(() => _applyCatalog(match)),
        ),
      ));
  }

  Future<bool?> _confirmAddBatch(ProductStock p) {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Already in inventory'),
        content: Text('${p.name} has this barcode. '
            'Add a new batch to it instead?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Add batch'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final String? dateError = _dateError();
    if (dateError != null) {
      _showDateError(dateError);
      return;
    }
    final MedicineProvider mp = context.read<MedicineProvider>();
    final DateTime now = DateTime.now();
    final String name = _name.text.trim();
    final String batch = _batch.text.trim();
    // Prices are typed per pack in packs mode; stored per piece.
    final int perPack = _packsMode ? _modePackSize : 1;
    double price(TextEditingController c) =>
        (double.tryParse(c.text.trim()) ?? 0) / perPack;

    Medicine medicine = (widget.existing ??
            Medicine(
              id: const Uuid().v4(),
              name: name,
              quantity: 0,
              expiryDate: _expiryDate,
              createdAt: now,
              updatedAt: now,
            ))
        .copyWith(
      name: name,
      brand: _brand.text.trim(),
      category: _category,
      batchNo: batch,
      barcode: _barcode.text.trim(),
      quantity: _quantityValue,
      unit: _unit,
      packSize: _packSizeValue,
      lowStockThreshold: int.tryParse(_lowStock.text.trim()) ??
          AppConstants.defaultLowStockThreshold,
      purchasePrice: price(_purchase),
      sellingPrice: price(_selling),
      mfgDate: _mfgDate,
      expiryDate: _expiryDate,
      notes: _notes.text.trim(),
      updatedAt: now,
      hsn: _hsn.text.trim(),
      gstRateBp: _gstRateBp,
      clearGstRate: _gstRateBp == null,
    );
    // copyWith keeps the old value for a null, so a manufacture date the
    // user cleared while editing has to be dropped explicitly.
    if (_mfgDate == null && medicine.mfgDate != null) {
      medicine = Medicine.fromMap(
          <String, Object?>{...medicine.toMap(), 'mfg_date': null});
    }

    if (_isEdit) {
      await mp.update(medicine);
      if (!mounted) return;
      Navigator.of(context).pop();
      return;
    }

    // Duplicate check before insert.
    final bool dup = await mp.isDuplicate(name, batch);
    bool allowDuplicate = false;
    if (dup && mounted) {
      allowDuplicate = await _confirmDuplicate() ?? false;
      if (!allowDuplicate) return;
    }

    final AddResult result =
        await mp.add(medicine, allowDuplicate: allowDuplicate);
    if (!mounted) return;
    switch (result) {
      case AddResult.success:
        Navigator.of(context).pop();
        break;
      case AddResult.blockedByFreeLimit:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const UpgradeScreen()),
        );
        break;
      case AddResult.duplicate:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Duplicate medicine')),
        );
        break;
    }
  }

  Future<bool?> _confirmDuplicate() {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Possible duplicate'),
        content: const Text(
            'A medicine with the same name and batch already exists. Add anyway?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Add anyway'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.card,
      body: Column(
        children: <Widget>[
          _header(),
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                children: <Widget>[
                  _nameAutocompleteField(),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: LabeledField(
                          label: 'Brand',
                          hint: 'e.g. Calpol',
                          controller: _brand,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: _categoryDropdown()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _barcodeField(),
                  const SizedBox(height: 16),
                  LabeledField(
                    label: 'Batch / lot no.',
                    hint: 'B2401',
                    controller: _batch,
                  ),
                  const SizedBox(height: 18),
                  Container(height: 1, color: AppColors.divider),
                  const SizedBox(height: 18),
                  // How the medicine is counted: the unit, and for tablets,
                  // capsules and ml how many make a pack, so stock and
                  // prices can be given per strip or bottle.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(flex: 6, child: _unitDropdown()),
                      if (kPieceUnits.contains(_unit)) ...<Widget>[
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 7,
                          child: _numberField(
                            _packSize,
                            PackSize.perPackLabel(_unit),
                            hint: 'e.g. 10',
                            onChanged: (_) => setState(_syncMode),
                          ),
                        ),
                      ],
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 7,
                        child: _numberField(
                          _lowStock,
                          'Low-stock at',
                          hint: '10',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _stockFields(),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: _numberField(
                          _purchase,
                          _packsMode
                              ? 'Purchase price per ${PackSize.packNoun(_unit)}'
                              : 'Purchase price',
                          hint: '0.00',
                          decimal: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _numberField(
                          _selling,
                          _packsMode
                              ? 'MRP per ${PackSize.packNoun(_unit)}'
                              : 'Selling price (MRP)',
                          hint: '0.00',
                          decimal: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Product-level GST details used on bills (all batches).
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: _numberField(_hsn, 'HSN code', hint: '3004'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: _gstDropdown()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: _dateField(
                          label: 'Manufacture date',
                          value: _mfgDate == null ? 'Not set' : Fmt.date(_mfgDate!),
                          placeholder: _mfgDate == null,
                          onTap: () => _pickDate(isExpiry: false),
                          onClear: _mfgDate == null
                              ? null
                              : () => setState(() => _mfgDate = null),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _dateField(
                          label: 'Expiry date *',
                          value: Fmt.date(_expiryDate),
                          onTap: () => _pickDate(isExpiry: true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  LabeledField(
                    label: 'Notes',
                    hint: 'Storage instructions, dosage notes.',
                    controller: _notes,
                    maxLines: 3,
                  ),
                  if (_isEdit) ...<Widget>[
                    const SizedBox(height: 18),
                    _deleteButton(),
                  ],
                ],
              ),
            ),
          ),
          _bottomBar(),
        ],
      ),
    );
  }

  /// Stock in pieces, or as packs + loose pieces when the pack size
  /// applies ("6 strips + 3 tablets = 63 tablets").
  Widget _stockFields() {
    if (!_packsMode) {
      return _numberField(_quantity, 'Quantity *', hint: '0', required: true);
    }
    final String pack = PackSize.packNoun(_unit);
    final String piece = PackSize.pieceNoun(_unit);
    final bool blank =
        _packs.text.trim().isEmpty && _loose.text.trim().isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: _numberField(
                _packs,
                '${pack[0].toUpperCase()}${pack.substring(1)}s *',
                hint: '0',
                onChanged: (_) => setState(() {}),
                // One of the two must be filled in.
                validator: (String? v) => (v == null || v.trim().isEmpty) &&
                        _loose.text.trim().isEmpty
                    ? 'Required'
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _numberField(
                _loose,
                'Loose ${piece == 'ml' ? 'ml' : '${piece}s'}',
                hint: '0',
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 2),
          child: Text(
            blank
                ? 'Stock is kept in ${_unit.toLowerCase()}; '
                    '1 $pack = $_modePackSize ${_unit.toLowerCase()}'
                : '= ${_packsTotal()} ${_unit.toLowerCase()} in stock',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
        ),
      ],
    );
  }

  Widget _header() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      // 5dp less padding around the 38dp back button: its touch area is 48dp.
      padding: EdgeInsets.fromLTRB(
          11, MediaQuery.of(context).padding.top + 7, 16, 7),
      child: Row(
        children: <Widget>[
          TapTarget(
            label: 'Back',
            onTap: () => Navigator.of(context).maybePop(),
            child: InkWell(
              onTap: () => Navigator.of(context).maybePop(),
              borderRadius: BorderRadius.circular(11),
              child: Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Icon(Icons.chevron_left,
                    size: 22, color: AppColors.ink),
              ),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              _isEdit
                  ? 'Edit Medicine'
                  : (widget.newBatchOf != null ? 'Add batch' : 'Add Medicine'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: AppColors.ink,
              ),
            ),
          ),
          if (_isNewProduct)
            TextButton.icon(
              onPressed: _scanInvoice,
              icon: const Icon(Icons.document_scanner_outlined, size: 18),
              label: const Text('Scan invoice'),
            ),
        ],
      ),
    );
  }

  /// A whole supplier bill at once: read with AI, checked, then added.
  void _scanInvoice() {
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => const InvoiceScanScreen(),
    ));
  }

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7, left: 2),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.muted,
        ),
      ),
    );
  }

  /// Medicine-name field with a debounced typeahead backed by the master list.
  /// Uses the existing [_name] controller + [_nameFocus] so validation and
  /// [_save] keep working unchanged; only the field's decoration is bespoke so
  /// it matches the [LabeledField] look elsewhere on the form.
  Widget _nameAutocompleteField() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double fieldWidth = constraints.maxWidth;
        return RawAutocomplete<Map<String, dynamic>>(
          textEditingController: _name,
          focusNode: _nameFocus,
          displayStringForOption: (Map<String, dynamic> m) =>
              (m['name'] as String?) ?? '',
          optionsBuilder: _searchNames,
          onSelected: _onNameSelected,
          fieldViewBuilder: (
            BuildContext context,
            TextEditingController controller,
            FocusNode focusNode,
            VoidCallback onFieldSubmitted,
          ) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _fieldLabel('Medicine name *'),
                TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  onFieldSubmitted: (_) => onFieldSubmitted(),
                  textInputAction: TextInputAction.next,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                  decoration:
                      const InputDecoration(hintText: 'e.g. Paracetamol 500mg'),
                  // Re-check as it's edited so a stale "Required" clears.
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: (String? v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ],
            );
          },
          optionsViewBuilder: (
            BuildContext context,
            void Function(Map<String, dynamic>) onSelected,
            Iterable<Map<String, dynamic>> options,
          ) {
            return Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Material(
                  elevation: 4,
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(AppRadii.input),
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(maxHeight: 260, maxWidth: fieldWidth),
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: options.length,
                      itemBuilder: (BuildContext context, int index) {
                        final Map<String, dynamic> m = options.elementAt(index);
                        return _suggestionTile(m, () => onSelected(m));
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _suggestionTile(Map<String, dynamic> m, VoidCallback onTap) {
    final String name = (m['name'] as String?) ?? '';
    final String manufacturer = (m['manufacturer'] as String?) ?? '';
    final String packSize = (m['pack_size'] as String?) ?? '';
    final String subtitle = <String>[manufacturer, packSize]
        .where((String s) => s.isNotEmpty)
        .join(' · ');
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            if (subtitle.isNotEmpty) ...<Widget>[
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.muted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Debounced (~250ms) master-list lookup. Returns nothing for queries below
  /// the backend's 2-char minimum; a superseded lookup never completes and is
  /// harmlessly discarded by [RawAutocomplete].
  Future<Iterable<Map<String, dynamic>>> _searchNames(
      TextEditingValue value) async {
    final String q = value.text.trim();
    if (q.length < 2) return const <Map<String, dynamic>>[];
    _searchDebounce?.cancel();
    final Completer<Iterable<Map<String, dynamic>>> completer =
        Completer<Iterable<Map<String, dynamic>>>();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () async {
      if (!mounted) return;
      final String? token = context.read<AuthService>().token;
      final List<Map<String, dynamic>> results =
          await _api.searchMedicines(q, token: token);
      if (!completer.isCompleted) completer.complete(results);
    });
    return completer.future;
  }

  void _onNameSelected(Map<String, dynamic> m) {
    setState(() => _applyCatalog(m));
    _nameFocus.unfocus();
  }

  /// Fill the product fields from a master-catalog entry.
  void _applyCatalog(Map<String, dynamic> m) {
    _name.text = (m['name'] as String?) ?? _name.text;
    _brand.text = (m['manufacturer'] as String?) ?? '';
    final Object? price = m['price'];
    if (price is num) {
      _selling.text = price.toStringAsFixed(2);
    }
    final Object? unit = m['unit'];
    if (unit is String) {
      final String canonical = AppConstants.canonicalUnit(unit);
      if (AppConstants.units.contains(canonical)) _unit = canonical;
    }
    // "strip of 10 tablets" -> 10; the catalog price is for that pack.
    final Object? pack = m['pack_size'];
    if (pack is String) {
      final int n = PackSize.parse(pack);
      _packSize.text = n > 1 ? '$n' : '';
    }
    _syncMode(keepSelling: price is num);
    final Object? barcode = m['barcode'];
    if (_barcode.text.trim().isEmpty && barcode is String) {
      _barcode.text = barcode;
    }
    final Object? hsn = m['hsn'];
    if (hsn is String && hsn.isNotEmpty) _hsn.text = hsn;
    final Object? gst = m['gst_rate_bp'];
    if (gst is num) _gstRateBp = gst.toInt();
  }

  Widget _numberField(
    TextEditingController c,
    String label, {
    String? hint,
    bool required = false,
    bool decimal = false,
    ValueChanged<String>? onChanged,
    FormFieldValidator<String>? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _fieldLabel(label),
        TextFormField(
          controller: c,
          onChanged: onChanged,
          keyboardType: TextInputType.numberWithOptions(decimal: decimal),
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(
                RegExp(decimal ? r'[0-9.]' : r'[0-9]')),
          ],
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
          decoration: InputDecoration(hintText: hint),
          // Re-check as it's edited so a stale "Required" clears.
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: validator ??
              (required
                  ? (String? v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null
                  : null),
        ),
      ],
    );
  }

  Widget _barcodeField() {
    // The scan button's 48dp touch area takes 4dp of the field's padding.
    final bool scan = AppPlatform.supportsCamera;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _fieldLabel('Barcode'),
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadii.input),
            border: Border.all(color: AppColors.border, width: 1.5),
          ),
          padding: EdgeInsets.fromLTRB(
              14, scan ? 2 : 6, scan ? 2 : 6, scan ? 2 : 6),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextFormField(
                  controller: _barcode,
                  // A USB scanner types the code and presses Enter.
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: _lookupBarcode,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                  decoration: InputDecoration(
                    hintText: AppPlatform.supportsCamera
                        ? 'Scan or enter code'
                        : 'Scan with USB scanner or type',
                    filled: false,
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              // On a PC a USB scanner types straight into the field.
              if (scan) ...<Widget>[
              const SizedBox(width: 4),
              TapTarget(
                label: 'Scan barcode',
                onTap: _scanBarcode,
                child: InkWell(
                  onTap: _scanBarcode,
                  borderRadius: BorderRadius.circular(9),
                  child: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.green,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(Icons.qr_code_scanner,
                        size: 20, color: Colors.white),
                  ),
                ),
              ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// GST rate of the medicine; "Shop default" leaves it to the rate set in
  /// the shop's invoice details.
  Widget _gstDropdown() {
    const List<int> rates = <int>[0, 500, 1200, 1800, 2800];
    final int? current = _gstRateBp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _fieldLabel('GST rate'),
        DropdownButtonFormField<int?>(
          initialValue: current,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: AppColors.muted),
          style: const TextStyle(
            fontFamily: AppTheme.fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
          items: <DropdownMenuItem<int?>>[
            const DropdownMenuItem<int?>(child: Text('Shop default')),
            for (final int r in <int>[
              ...rates,
              if (current != null && !rates.contains(current)) current,
            ])
              DropdownMenuItem<int?>(
                  value: r, child: Text('${r % 100 == 0 ? r ~/ 100 : r / 100}%')),
          ],
          onChanged: (int? v) => setState(() => _gstRateBp = v),
        ),
      ],
    );
  }

  Widget _unitDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _fieldLabel('Unit'),
        DropdownButtonFormField<String>(
          initialValue: _unit,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: AppColors.muted),
          style: const TextStyle(
            fontFamily: AppTheme.fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
          items: (AppConstants.units.contains(_unit)
                  ? AppConstants.units
                  : <String>[_unit, ...AppConstants.units])
              .map((String u) =>
                  DropdownMenuItem<String>(value: u, child: Text(u)))
              .toList(),
          onChanged: (String? v) => setState(() {
            _unit = v ?? 'Tablets';
            _syncMode();
          }),
        ),
      ],
    );
  }

  Widget _categoryDropdown() {
    // Keep any legacy free-text value that predates the preset list so an edit
    // never silently drops it.
    final List<String> options = AppConstants.categories.contains(_category)
        ? AppConstants.categories
        : <String>[_category, ...AppConstants.categories];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _fieldLabel('Category'),
        DropdownButtonFormField<String>(
          initialValue: _category,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: AppColors.muted),
          style: const TextStyle(
            fontFamily: AppTheme.fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
          items: options
              .map((String c) => DropdownMenuItem<String>(
                    value: c,
                    child: Text(c, overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: (String? v) =>
              setState(() => _category = v ?? 'Uncategorised'),
        ),
      ],
    );
  }

  Widget _dateField({
    required String label,
    required String value,
    required VoidCallback onTap,
    bool placeholder = false,
    VoidCallback? onClear,
  }) {
    final String name = label.replaceAll(' *', '');
    final Widget field = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.input),
      // Read as one control, e.g. "Expiry date: 05 Oct 2027".
      child: Semantics(
        button: true,
        label: '$name: $value',
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadii.input),
            border: Border.all(color: AppColors.border, width: 1.5),
          ),
          child: Row(
            children: <Widget>[
              const Icon(Icons.calendar_today_outlined,
                  size: 17, color: AppColors.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: placeholder ? AppColors.muted : AppColors.ink,
                  ),
                ),
              ),
              // Room for the clear button, which is drawn over this end.
              if (onClear != null) const SizedBox(width: 20),
            ],
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // The field reads its label out itself.
        ExcludeSemantics(child: _fieldLabel(label)),
        if (onClear == null)
          field
        else
          Stack(
            children: <Widget>[
              field,
              // The small "x" with a 48dp touch area over the field's end.
              Positioned(
                top: 0,
                bottom: 0,
                right: 1.5,
                child: TapTarget(
                  label: 'Clear ${name.toLowerCase()}',
                  onTap: onClear,
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.close, size: 16, color: AppColors.muted),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _deleteButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _deleteMedicine,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.statusRed,
          backgroundColor: AppColors.card,
          side: const BorderSide(color: Color(0xFFF4CCCE), width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: const Icon(Icons.delete_outline, size: 20),
        label: const Text('Delete medicine'),
      ),
    );
  }

  Future<void> _deleteMedicine() async {
    final Medicine? m = widget.existing;
    if (m == null) return;
    final MedicineProvider mp = context.read<MedicineProvider>();
    final bool ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: const Text('Delete medicine?'),
            content: Text('Remove ${m.name} from your stock?'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                style:
                    TextButton.styleFrom(foregroundColor: AppColors.statusRed),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    await mp.delete(m.id);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Deleted ${m.name}'),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () => mp.undoDelete(m.id),
        ),
      ),
    );
  }

  Widget _bottomBar() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      padding: EdgeInsets.fromLTRB(
          18, 12, 18, MediaQuery.of(context).padding.bottom + 14),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 1,
            child: SecondaryButton(
              label: 'Cancel',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: PrimaryButton(
              label: _isEdit ? 'Save changes' : 'Add medicine',
              onPressed: _save,
            ),
          ),
        ],
      ),
    );
  }
}
