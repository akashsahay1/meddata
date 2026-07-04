import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../data/models/medicine.dart';
import '../../state/medicine_provider.dart';
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
  late final TextEditingController _category;
  late final TextEditingController _batch;
  late final TextEditingController _barcode;
  late final TextEditingController _quantity;
  late final TextEditingController _lowStock;
  late final TextEditingController _purchase;
  late final TextEditingController _selling;
  late final TextEditingController _notes;

  String _unit = 'Tablets';
  DateTime? _mfgDate;
  DateTime _expiryDate = DateTime.now().add(const Duration(days: 365));

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final Medicine? m = widget.existing;
    _name = TextEditingController(text: m?.name ?? '');
    _brand = TextEditingController(text: m?.brand ?? '');
    _category = TextEditingController(text: m?.category ?? '');
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
    _mfgDate = m?.mfgDate;
    if (m != null) _expiryDate = m.expiryDate;
  }

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _name, _brand, _category, _batch, _barcode, _quantity,
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
      category: _category.text.trim(),
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
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Medicine' : 'Add Medicine'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            _field(_name, 'Medicine name *', required: true),
            _field(_brand, 'Brand / manufacturer'),
            _field(_category, 'Category'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(child: _field(_batch, 'Batch / lot no.')),
                const SizedBox(width: 10),
                Expanded(
                  child: _field(
                    _barcode,
                    'Barcode',
                    suffix: IconButton(
                      icon: const Icon(Icons.qr_code_scanner),
                      onPressed: _scanBarcode,
                    ),
                  ),
                ),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: _field(
                    _quantity,
                    'Quantity *',
                    required: true,
                    number: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: _unitDropdown()),
              ],
            ),
            _field(_lowStock, 'Low-stock alert at', number: true),
            Row(
              children: <Widget>[
                Expanded(child: _field(_purchase, 'Purchase price', number: true, decimal: true)),
                const SizedBox(width: 10),
                Expanded(child: _field(_selling, 'Selling price (MRP)', number: true, decimal: true)),
              ],
            ),
            const SizedBox(height: 4),
            _dateTile(
              label: 'Expiry date *',
              value: Fmt.date(_expiryDate),
              onTap: () => _pickDate(isExpiry: true),
            ),
            const SizedBox(height: 10),
            _dateTile(
              label: 'Manufacture date',
              value: _mfgDate == null ? 'Not set' : Fmt.date(_mfgDate!),
              onTap: () => _pickDate(isExpiry: false),
              onClear: _mfgDate == null ? null : () => setState(() => _mfgDate = null),
            ),
            const SizedBox(height: 10),
            _field(_notes, 'Notes', maxLines: 3),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _save,
              child: Text(_isEdit ? 'Save changes' : 'Add medicine'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    bool required = false,
    bool number = false,
    bool decimal = false,
    int maxLines = 1,
    Widget? suffix,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        maxLines: maxLines,
        keyboardType: number
            ? TextInputType.numberWithOptions(decimal: decimal)
            : TextInputType.text,
        inputFormatters: number
            ? <TextInputFormatter>[
                FilteringTextInputFormatter.allow(
                    RegExp(decimal ? r'[0-9.]' : r'[0-9]')),
              ]
            : null,
        decoration: InputDecoration(labelText: label, suffixIcon: suffix),
        validator: required
            ? (String? v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null
            : null,
      ),
    );
  }

  Widget _unitDropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: _unit,
        decoration: const InputDecoration(labelText: 'Unit'),
        items: AppConstants.units
            .map((String u) =>
                DropdownMenuItem<String>(value: u, child: Text(u)))
            .toList(),
        onChanged: (String? v) => setState(() => _unit = v ?? 'Tablets'),
      ),
    );
  }

  Widget _dateTile({
    required String label,
    required String value,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    final Color fg = Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: fg),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.calendar_today_outlined, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(label,
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurface)),
                  Text(value,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            if (onClear != null)
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: onClear,
              ),
          ],
        ),
      ),
    );
  }
}
