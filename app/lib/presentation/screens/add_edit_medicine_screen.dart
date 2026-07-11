import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../data/models/medicine.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../state/medicine_provider.dart';
import '../../theme/app_theme.dart';
import '../widgets/ui_kit.dart';
import 'barcode_scan_screen.dart';
import 'upgrade_screen.dart';

class AddEditMedicineScreen extends StatefulWidget {
  final Medicine? existing;
  const AddEditMedicineScreen({super.key, this.existing});

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
  late final TextEditingController _lowStock;
  late final TextEditingController _purchase;
  late final TextEditingController _selling;
  late final TextEditingController _notes;

  String _unit = 'Tablets';
  String _category = 'Uncategorised';
  DateTime? _mfgDate;
  DateTime _expiryDate = DateTime.now().add(const Duration(days: 365));

  // Medicine-name autocomplete against the backend master list.
  final ApiClient _api = ApiClient();
  final FocusNode _nameFocus = FocusNode();
  Timer? _searchDebounce;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final Medicine? m = widget.existing;
    _name = TextEditingController(text: m?.name ?? '');
    _brand = TextEditingController(text: m?.brand ?? '');
    _batch = TextEditingController(text: m?.batchNo ?? '');
    _barcode = TextEditingController(text: m?.barcode ?? '');
    _quantity = TextEditingController(text: m?.quantity.toString() ?? '');
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
    _unit = m?.unit ?? 'Tablets';
    final String stored = m?.category.trim() ?? '';
    _category = stored.isEmpty ? 'Uncategorised' : stored;
    _mfgDate = m?.mfgDate;
    if (m != null) _expiryDate = m.expiryDate;
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _nameFocus.dispose();
    for (final TextEditingController c in <TextEditingController>[
      _name, _brand, _batch, _barcode, _quantity,
      _lowStock, _purchase, _selling, _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate({required bool isExpiry}) async {
    final DateTime initial = isExpiry ? _expiryDate : (_mfgDate ?? DateTime.now());
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
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

  Future<void> _scanBarcode() async {
    final String? code = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const BarcodeScanScreen()),
    );
    if (code != null && code.isNotEmpty) {
      setState(() => _barcode.text = code);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final MedicineProvider mp = context.read<MedicineProvider>();
    final DateTime now = DateTime.now();
    final String name = _name.text.trim();
    final String batch = _batch.text.trim();

    final Medicine medicine = (widget.existing ??
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
      quantity: int.tryParse(_quantity.text.trim()) ?? 0,
      unit: _unit,
      lowStockThreshold: int.tryParse(_lowStock.text.trim()) ??
          AppConstants.defaultLowStockThreshold,
      purchasePrice: double.tryParse(_purchase.text.trim()) ?? 0,
      sellingPrice: double.tryParse(_selling.text.trim()) ?? 0,
      mfgDate: _mfgDate,
      expiryDate: _expiryDate,
      notes: _notes.text.trim(),
      updatedAt: now,
    );

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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        flex: 7,
                        child: _numberField(
                          _quantity,
                          'Quantity *',
                          hint: '0',
                          required: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(flex: 6, child: _unitDropdown()),
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: _numberField(
                          _purchase,
                          'Purchase price',
                          hint: '0.00',
                          decimal: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _numberField(
                          _selling,
                          'Selling price (MRP)',
                          hint: '0.00',
                          decimal: true,
                        ),
                      ),
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

  Widget _header() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      padding: EdgeInsets.fromLTRB(
          16, MediaQuery.of(context).padding.top + 12, 16, 12),
      child: Row(
        children: <Widget>[
          InkWell(
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
          const SizedBox(width: 12),
          Text(
            _isEdit ? 'Edit Medicine' : 'Add Medicine',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
    setState(() {
      _name.text = (m['name'] as String?) ?? _name.text;
      _brand.text = (m['manufacturer'] as String?) ?? '';
      final Object? price = m['price'];
      if (price is num) {
        _selling.text = price.toStringAsFixed(2);
      }
      final Object? unit = m['unit'];
      if (unit is String && AppConstants.units.contains(unit)) {
        _unit = unit;
      }
    });
    _nameFocus.unfocus();
  }

  Widget _numberField(
    TextEditingController c,
    String label, {
    String? hint,
    bool required = false,
    bool decimal = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _fieldLabel(label),
        TextFormField(
          controller: c,
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
          validator: required
              ? (String? v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null
              : null,
        ),
      ],
    );
  }

  Widget _barcodeField() {
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
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextFormField(
                  controller: _barcode,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Scan or enter code',
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
              const SizedBox(width: 8),
              InkWell(
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
            ],
          ),
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
          items: AppConstants.units
              .map((String u) =>
                  DropdownMenuItem<String>(value: u, child: Text(u)))
              .toList(),
          onChanged: (String? v) => setState(() => _unit = v ?? 'Tablets'),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _fieldLabel(label),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.input),
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
                if (onClear != null)
                  InkWell(
                    onTap: onClear,
                    borderRadius: BorderRadius.circular(20),
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(Icons.close, size: 16, color: AppColors.muted),
                    ),
                  ),
              ],
            ),
          ),
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
