import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/platform.dart';
import '../../services/auth_service.dart';
import '../../services/invoice_scan_service.dart';
import '../../services/invoice_upload.dart';
import '../../theme/app_theme.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/ui_kit.dart';
import 'invoice_scan_screen.dart';

/// The shop's supplier bills being read with AI. Many photos or PDFs can be
/// picked at once; they upload straight away and the server reads them one
/// after another as the AI service allows, so staff can go back to work and
/// come back to "Ready to check". A ready bill opens the usual check screen;
/// once added to stock it leaves this list. Online only.
class SupplierBillsScreen extends StatefulWidget {
  const SupplierBillsScreen({super.key, this.service, this.pickFiles});

  /// Replaced in tests.
  final InvoiceScanService? service;

  /// Stands in for the file picker in tests.
  @visibleForTesting
  final Future<List<XFile>> Function()? pickFiles;

  @override
  State<SupplierBillsScreen> createState() => _SupplierBillsScreenState();
}

enum _Pick { camera, photos, files }

class _SupplierBillsScreenState extends State<SupplierBillsScreen> {
  late final InvoiceScanService _service =
      (widget.service ?? InvoiceScanService())
        ..onUnauthorized = context.read<AuthService>().sessionRejected;

  List<InvoiceScan>? _bills;

  /// Why the list couldn't be loaded (offline, server error).
  String? _loadProblem;

  /// Files picked but not yet uploaded: (done, total).
  (int, int)? _uploading;

  /// Files that could not be uploaded, with the reason.
  final List<String> _uploadProblems = <String>[];

  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  String? get _token => context.read<AuthService>().token;

  Future<void> _load() async {
    final String? token = _token;
    if (token == null) return;
    final List<InvoiceScan>? bills = await _service.list(
      token: token,
      onError: (String m) => _loadProblem = m,
    );
    if (!mounted) return;
    setState(() {
      if (bills != null) {
        _bills = bills;
        _loadProblem = null;
      }
    });
    // Keep the statuses moving while the server is still reading some.
    _refresh?.cancel();
    if (bills == null || bills.any((InvoiceScan b) => b.isPending)) {
      _refresh = Timer(const Duration(seconds: 5), _load);
    }
  }

  // ---- Adding bills ---------------------------------------------------------

  Future<void> _addBills() async {
    final _Pick? pick = AppPlatform.supportsCamera
        ? await showModalBottomSheet<_Pick>(
            context: context,
            backgroundColor: AppColors.card,
            builder: (BuildContext ctx) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  ListTile(
                    leading: const Icon(Icons.photo_camera_outlined),
                    title: const Text('Take a photo'),
                    onTap: () => Navigator.of(ctx).pop(_Pick.camera),
                  ),
                  ListTile(
                    leading: const Icon(Icons.photo_library_outlined),
                    title: const Text('Choose photos'),
                    subtitle: const Text('Pick as many bills as you like'),
                    onTap: () => Navigator.of(ctx).pop(_Pick.photos),
                  ),
                  ListTile(
                    leading: const Icon(Icons.picture_as_pdf_outlined),
                    title: const Text('Choose PDFs'),
                    subtitle: const Text('Read fastest and most accurately'),
                    onTap: () => Navigator.of(ctx).pop(_Pick.files),
                  ),
                ],
              ),
            ),
          )
        : _Pick.files;
    if (pick == null || !mounted) return;

    final List<XFile> files;
    try {
      files = switch (pick) {
        _Pick.camera => <XFile>[
          if (await ImagePicker().pickImage(
                source: ImageSource.camera,
                maxWidth: InvoiceUpload.maxImageSide.toDouble(),
                maxHeight: InvoiceUpload.maxImageSide.toDouble(),
                imageQuality: 90,
              )
              case final XFile f)
            f,
        ],
        _Pick.photos => await ImagePicker().pickMultiImage(
          maxWidth: InvoiceUpload.maxImageSide.toDouble(),
          maxHeight: InvoiceUpload.maxImageSide.toDouble(),
          imageQuality: 90,
        ),
        _Pick.files =>
          await (widget.pickFiles?.call() ??
              openFiles(
                acceptedTypeGroups: <XTypeGroup>[
                  AppPlatform.supportsCamera
                      ? InvoiceUpload.pdfFiles
                      : InvoiceUpload.invoiceFiles,
                ],
              )),
      };
    } on PlatformException catch (e) {
      debugPrint('[SupplierBills] pick failed: $e');
      _toast(
        e.code == 'camera_access_denied'
            ? 'Allow camera access in Settings to photograph bills.'
            : 'Could not open the picker.',
      );
      return;
    }
    if (files.isEmpty || !mounted) return;
    await _upload(files, fromFiles: pick == _Pick.files);
  }

  Future<void> _upload(List<XFile> files, {required bool fromFiles}) async {
    final String? token = _token;
    if (token == null) return;
    setState(() {
      _uploading = (0, files.length);
      _uploadProblems.clear();
    });
    for (int i = 0; i < files.length; i++) {
      final (InvoiceUpload? upload, String? problem) =
          await InvoiceUpload.prepare(files[i], fromFiles: fromFiles);
      String? failed = problem;
      if (upload != null) {
        final InvoiceScanResponse r = await _service.upload(
          token: token,
          bytes: upload.bytes,
          filename: upload.name,
        );
        failed = r.scan == null ? r.message : null;
      }
      if (!mounted) return;
      setState(() {
        if (failed != null) _uploadProblems.add('${files[i].name}: $failed');
        _uploading = (i + 1, files.length);
      });
    }
    setState(() => _uploading = null);
    await _load();
  }

  // ---- One bill -------------------------------------------------------------

  Future<void> _check(InvoiceScan bill) async {
    final String? token = _token;
    if (token == null) return;
    final InvoiceScanResponse r = await _service.fetch(
      token: token,
      id: bill.id,
    );
    if (!mounted) return;
    final InvoiceScan? scan = r.scan;
    if (scan == null) {
      _toast(r.message ?? 'Could not open this bill.');
      return;
    }
    await Navigator.of(context).push(
      AdaptiveLayout.route<void>(
        context,
        maxWidth: AdaptiveLayout.contentMaxWidth,
        builder: (_) => InvoiceScanScreen(initialScan: scan, service: _service),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _retry(InvoiceScan bill) async {
    final String? token = _token;
    if (token == null) return;
    final InvoiceScanResponse r = await _service.retry(
      token: token,
      id: bill.id,
    );
    if (!mounted) return;
    if (r.scan == null) _toast(r.message ?? 'Could not try again.');
    _load();
  }

  Future<void> _remove(InvoiceScan bill) async {
    final String? token = _token;
    if (token == null) return;
    final bool ok = await _service.close(token: token, id: bill.id);
    if (!mounted) return;
    if (!ok) _toast("Couldn't reach the server. Please try again.");
    _load();
  }

  Future<void> _typeBill() async {
    await Navigator.of(context).push(
      AdaptiveLayout.route<void>(
        context,
        maxWidth: AdaptiveLayout.contentMaxWidth,
        builder: (_) => const InvoiceScanScreen.manual(),
      ),
    );
  }

  void _toast(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  // ---- Layout ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final List<InvoiceScan>? bills = _bills;
    final (int, int)? uploading = _uploading;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('Supplier bills')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: <Widget>[
            PrimaryButton(
              label: AppPlatform.supportsCamera
                  ? 'Add bills'
                  : 'Add bills (photos or PDFs)',
              icon: Icons.add_photo_alternate_outlined,
              onPressed: uploading == null ? _addBills : null,
            ),
            const SizedBox(height: 10),
            SecondaryButton(
              label: 'Type a bill instead',
              icon: Icons.keyboard_outlined,
              onPressed: _typeBill,
            ),
            const SizedBox(height: 12),
            const Text(
              'Add all your bills at once. Medikabiz reads them one by one; '
              'you can keep working and come back when they are ready.',
              style: TextStyle(
                color: AppColors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (uploading != null) ...<Widget>[
              const SizedBox(height: 14),
              _Banner(
                icon: Icons.cloud_upload_outlined,
                text: 'Uploaded ${uploading.$1} of ${uploading.$2}…',
                busy: true,
              ),
            ],
            for (final String p in _uploadProblems) ...<Widget>[
              const SizedBox(height: 10),
              _Banner(
                icon: Icons.error_outline,
                text: p,
                color: AppColors.statusRed,
              ),
            ],
            if (_loadProblem != null && bills == null) ...<Widget>[
              const SizedBox(height: 14),
              _Banner(icon: Icons.cloud_off_outlined, text: _loadProblem!),
            ],
            const SizedBox(height: 18),
            if (bills == null && _loadProblem == null)
              const Center(child: CircularProgressIndicator())
            else if (bills != null && bills.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No bills waiting. Bills you add show here while they are '
                  'read, then as "Ready to check".',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else if (bills != null)
              for (final InvoiceScan b in bills)
                _BillRow(
                  bill: b,
                  onCheck: () => _check(b),
                  onRetry: () => _retry(b),
                  onRemove: () => _remove(b),
                ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.text,
    this.color = AppColors.muted,
    this.busy = false,
  });

  final IconData icon;
  final String text;
  final Color color;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: <Widget>[
          if (busy)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          else
            Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: const TextStyle(color: AppColors.ink)),
          ),
        ],
      ),
    );
  }
}

class _BillRow extends StatelessWidget {
  const _BillRow({
    required this.bill,
    required this.onCheck,
    required this.onRetry,
    required this.onRemove,
  });

  final InvoiceScan bill;
  final VoidCallback onCheck;
  final VoidCallback onRetry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final InvoiceScan b = bill;
    final String title = (b.supplierName?.isNotEmpty ?? false)
        ? b.supplierName!
        : (b.fileName?.isNotEmpty ?? false)
        ? b.fileName!
        : 'Bill';
    final (IconData icon, Color color, String status) = switch (b.status) {
      'done' => (
        Icons.check_circle_outline,
        AppColors.statusGreen,
        'Ready to check · ${b.itemsCount ?? 0} items'
            '${(b.invoiceNo?.isNotEmpty ?? false) ? ' · ${b.invoiceNo}' : ''}',
      ),
      'failed' => (
        Icons.error_outline,
        AppColors.statusRed,
        b.error ?? "Couldn't read this bill.",
      ),
      'processing' => (Icons.autorenew, AppColors.muted, 'Reading…'),
      _ =>
        b.retrying
            ? (
                Icons.hourglass_top,
                AppColors.muted,
                'AI service busy, trying again by itself',
              )
            : (Icons.schedule, AppColors.muted, 'Waiting to be read'),
    };
    final DateTime? at = b.createdAt;
    // A Material (not a decorated box) so the row's tap ripple shows.
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.card,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: const BorderSide(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ListTile(
              minVerticalPadding: 12,
              leading: Icon(icon, color: color, size: 28),
              title: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              subtitle: Text(
                at == null ? status : '$status\nAdded ${Fmt.date(at)}',
                style: const TextStyle(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              trailing: b.isDone ? const Icon(Icons.chevron_right) : null,
              onTap: b.isDone ? onCheck : null,
              mouseCursor: b.isDone ? SystemMouseCursors.click : null,
            ),
            if (b.isFailed)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: <Widget>[
                    if (b.canRetry)
                      PrimaryButton(
                        label: 'Try again',
                        icon: Icons.refresh,
                        expand: false,
                        onPressed: onRetry,
                      ),
                    SecondaryButton(
                      label: 'Remove',
                      expand: false,
                      onPressed: onRemove,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
