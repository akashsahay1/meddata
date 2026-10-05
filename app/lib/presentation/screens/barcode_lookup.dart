import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/platform.dart';
import '../../domain/product_stock.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../state/medicine_provider.dart';
import 'add_edit_medicine_screen.dart';
import 'barcode_scan_screen.dart';
import 'product_detail_screen.dart';
import 'upgrade_screen.dart';

/// Get a barcode from the user: the camera on phones, a small input dialog on
/// desktop (a USB scanner types the code and presses Enter).
Future<String?> readBarcode(BuildContext context) async {
  final String? code = AppPlatform.supportsCamera
      ? await Navigator.of(context).push<String>(
          MaterialPageRoute<String>(builder: (_) => const BarcodeScanScreen()))
      : await showDialog<String>(
          context: context, builder: (_) => const _BarcodeInputDialog());
  final String trimmed = code?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

/// Scan, then open what the barcode belongs to: the shop's own product first,
/// else a new medicine prefilled from the master catalog, else a new medicine
/// with just the barcode filled in.
Future<void> scanAndOpen(BuildContext context) async {
  final String? code = await readBarcode(context);
  if (code == null || !context.mounted) return;

  final MedicineProvider mp = context.read<MedicineProvider>();
  final NavigatorState nav = Navigator.of(context);
  final ProductStock? own = mp.productByBarcode(code);
  if (own != null) {
    nav.push(MaterialPageRoute<void>(
        builder: (_) => ProductDetailScreen(productId: own.productId)));
    return;
  }

  if (!mp.canAdd()) {
    nav.push(MaterialPageRoute<void>(builder: (_) => const UpgradeScreen()));
    return;
  }

  final String? token = context.read<AuthService>().token;
  final Map<String, dynamic>? match =
      await ApiClient().lookupBarcode(code, token: token);
  if (!context.mounted) return;
  if (match == null) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
          content: Text('New barcode - enter the medicine details')));
  }
  nav.push(MaterialPageRoute<void>(
    builder: (_) =>
        AddEditMedicineScreen(initialBarcode: code, catalogMatch: match),
  ));
}

class _BarcodeInputDialog extends StatefulWidget {
  const _BarcodeInputDialog();

  @override
  State<_BarcodeInputDialog> createState() => _BarcodeInputDialogState();
}

class _BarcodeInputDialogState extends State<_BarcodeInputDialog> {
  final TextEditingController _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_code.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Scan barcode'),
      content: TextField(
        controller: _code,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: const InputDecoration(
            hintText: 'Scan with USB scanner or type'),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('Find')),
      ],
    );
  }
}
