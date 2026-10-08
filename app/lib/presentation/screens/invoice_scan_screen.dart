import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../core/platform.dart';
import '../../data/models/accounting.dart';
import '../../data/models/medicine.dart';
import '../../domain/accounting.dart';
import '../../domain/invoice_draft.dart';
import '../../domain/pack_size.dart';
import '../../domain/product_stock.dart';
import '../../services/accounting_api.dart';
import '../../services/auth_service.dart';
import '../../services/billing_api.dart' show ApiOutcome;
import '../../services/invoice_scan_service.dart';
import '../../state/medicine_provider.dart';
import '../../sync/sync_engine.dart';
import '../../theme/app_theme.dart';
import '../widgets/ui_kit.dart';
import 'accounts/party_picker.dart';
import 'upgrade_screen.dart';

/// Add stock from a supplier's purchase invoice: a photo (camera or gallery
/// on phones) or a file (photo or PDF) is read on the server with AI, then
/// every line is reviewed and fixed here before it is added the same way as
/// a manual add (a known medicine gets a new batch). Online only.
class InvoiceScanScreen extends StatefulWidget {
  const InvoiceScanScreen({
    super.key,
    this.service,
    this.initialScan,
    this.accountingApi,
  });

  /// Replaced in tests.
  final InvoiceScanService? service;

  /// Supplier accounts and purchase entries (replaced in tests).
  final AccountingApi? accountingApi;

  /// Start from a scan that was already uploaded (tests).
  @visibleForTesting
  final InvoiceScan? initialScan;

  @override
  State<InvoiceScanScreen> createState() => _InvoiceScanScreenState();
}

enum _Stage { pick, uploading, reading, review, saving }

enum _Source { camera, gallery, file }

class _InvoiceScanScreenState extends State<InvoiceScanScreen> {
  // A 401 (the server no longer accepts the login) signs out, as elsewhere.
  late final InvoiceScanService _service =
      (widget.service ?? InvoiceScanService())
        ..onUnauthorized = context.read<AuthService>().sessionRejected;
  late final AccountingApi _accounts = (widget.accountingApi ?? AccountingApi())
    ..onUnauthorized = context.read<AuthService>().sessionRejected;

  // ---- Purchase entry (online, with a supplier chosen) ----
  /// The supplier the purchase is recorded for; null = only add to stock.
  Party? _supplier;

  /// The server answered the supplier lookup (purchase entries possible).
  bool _accountsOnline = false;
  final TextEditingController _invoiceNo = TextEditingController();
  DateTime? _invoiceDate;

  /// Same ids on a retry after no answer: no second purchase, no second
  /// new medicine.
  String _purchaseId = const Uuid().v4();
  final Map<String, String> _newProductIds = <String, String>{};

  _Stage _stage = _Stage.pick;

  /// Why the last scan didn't work (shown on the pick stage).
  String? _error;

  /// The last call couldn't reach the server.
  bool _offline = false;
  int? _scanId;
  String _scanStatus = 'queued';

  /// Polling stopped (network trouble / very slow); offer "Check again".
  String? _pollProblem;
  InvoiceDraft? _draft;

  /// Lines whose batch number the shop already has (scanned twice?).
  Set<String> _duplicates = <String>{};
  int _duplicateCheck = 0;

  // The server's limits; checked here too so a big file fails fast.
  static const int _maxImageBytes = 7 * 1024 * 1024;
  static const int _maxPdfBytes = 10 * 1024 * 1024;
  static const Set<String> _extensions = <String>{
    'jpg',
    'jpeg',
    'png',
    'webp',
    'pdf',
  };
  static const XTypeGroup _pdfFiles = XTypeGroup(
    label: 'PDF',
    extensions: <String>['pdf'],
    mimeTypes: <String>['application/pdf'],
    uniformTypeIdentifiers: <String>['com.adobe.pdf'],
  );
  static const XTypeGroup _invoiceFiles = XTypeGroup(
    label: 'Invoice photo or PDF',
    extensions: <String>['jpg', 'jpeg', 'png', 'webp', 'pdf'],
    mimeTypes: <String>[
      'image/jpeg',
      'image/png',
      'image/webp',
      'application/pdf',
    ],
    uniformTypeIdentifiers: <String>[
      'public.jpeg',
      'public.png',
      'org.webmproject.webp',
      'com.adobe.pdf',
    ],
  );

  @override
  void initState() {
    super.initState();
    final InvoiceScan? scan = widget.initialScan;
    if (scan != null) {
      _scanId = scan.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _show(scan);
      });
    }
  }

  @override
  void dispose() {
    _scanId = null; // stops polling
    _invoiceNo.dispose();
    super.dispose();
  }

  // ---- Picking and uploading ----------------------------------------------

  Future<void> _pick(_Source source) async {
    XFile? file;
    try {
      switch (source) {
        case _Source.camera:
          // The picker asks for camera permission itself.
          file = await _pickImage(ImageSource.camera);
        case _Source.gallery:
          file = await _pickImage(ImageSource.gallery);
        case _Source.file:
          file = await openFile(
            acceptedTypeGroups: <XTypeGroup>[
              AppPlatform.supportsCamera ? _pdfFiles : _invoiceFiles,
            ],
          );
      }
    } on PlatformException catch (e) {
      debugPrint('[InvoiceScan] pick failed: $e');
      _toast(e.code == 'camera_access_denied'
          ? 'Allow camera access in Settings to photograph invoices.'
          : 'Could not open the picker.');
      return;
    } catch (e) {
      debugPrint('[InvoiceScan] pick failed: $e');
      _toast('Could not open the picker.');
      return;
    }
    if (file == null || !mounted) return;
    await _upload(file, source);
  }

  /// Downscaled to the AI's own image limit (long edge 2576 px): sharp
  /// enough for small print, quick to upload.
  Future<XFile?> _pickImage(ImageSource source) => ImagePicker().pickImage(
    source: source,
    maxWidth: 2576,
    maxHeight: 2576,
    imageQuality: 90,
  );

  Future<void> _upload(XFile file, _Source source) async {
    String name = file.name.trim();
    if (!name.contains('.')) {
      name =
          '${name.isEmpty ? 'invoice' : name}.'
          '${source == _Source.file ? 'pdf' : 'jpg'}';
    }
    final String ext = name.split('.').last.toLowerCase();
    if (!_extensions.contains(ext)) {
      setState(() => _error = 'Choose a JPG, PNG or WebP photo, or a PDF.');
      return;
    }
    final int size = await file.length();
    if (!mounted) return;
    final bool pdf = ext == 'pdf';
    if (size > (pdf ? _maxPdfBytes : _maxImageBytes)) {
      setState(
        () => _error = pdf
            ? 'This PDF is too large (10 MB at most).'
            : 'This photo is too large (7 MB at most).',
      );
      return;
    }
    final String? token = context.read<AuthService>().token;
    if (token == null) {
      setState(() => _error = 'Please log in again to scan invoices.');
      return;
    }

    setState(() {
      _stage = _Stage.uploading;
      _error = null;
      _offline = false;
    });
    final List<int> bytes = await file.readAsBytes();
    final InvoiceScanResponse r = await _service.upload(
      token: token,
      bytes: bytes,
      filename: name,
    );
    if (!mounted) return;
    final InvoiceScan? scan = r.scan;
    if (scan == null) {
      setState(() {
        _stage = _Stage.pick;
        _error = r.message;
        _offline = r.offline;
      });
      return;
    }
    _scanId = scan.id;
    _show(scan);
  }

  // ---- Waiting for the result -----------------------------------------------

  void _show(InvoiceScan scan) {
    if (scan.isDone) {
      final InvoiceDraft draft = InvoiceDraftMapper.fromResult(
        scan.result ?? const <String, dynamic>{},
        products: context.read<MedicineProvider>().products,
      );
      if (draft.lines.isEmpty) {
        setState(() {
          _stage = _Stage.pick;
          _error =
              'No medicines were found on this invoice. '
              'Try a clear, flat photo of the whole page.';
        });
        return;
      }
      setState(() {
        _draft = draft;
        _stage = _Stage.review;
        _invoiceNo.text = draft.invoiceNo;
        _invoiceDate = draft.invoiceDate;
        _purchaseId = const Uuid().v4();
        _newProductIds.clear();
      });
      _checkDuplicates();
      _findSupplier();
    } else if (scan.isFailed) {
      setState(() {
        _stage = _Stage.pick;
        _error = scan.error ?? 'Could not read this invoice. Please try again.';
      });
    } else {
      setState(() {
        _stage = _Stage.reading;
        _scanStatus = scan.status;
        _pollProblem = null;
      });
      _poll(scan.id);
    }
  }

  Future<void> _poll(int id) async {
    final DateTime started = DateTime.now();
    int failures = 0;
    while (true) {
      await Future<void>.delayed(const Duration(seconds: 3));
      if (!mounted || _scanId != id || _stage != _Stage.reading) return;
      final String? token = context.read<AuthService>().token;
      if (token == null) return;
      final InvoiceScanResponse r = await _service.fetch(token: token, id: id);
      if (!mounted || _scanId != id || _stage != _Stage.reading) return;
      final InvoiceScan? scan = r.scan;
      if (scan == null) {
        // Ride out a brief network blip, then let the user retry.
        if (r.offline && ++failures < 4) continue;
        setState(() => _pollProblem = r.message);
        return;
      }
      failures = 0;
      if (!scan.isPending) {
        _show(scan);
        return;
      }
      if (scan.status != _scanStatus) setState(() => _scanStatus = scan.status);
      if (DateTime.now().difference(started) > const Duration(minutes: 8)) {
        setState(
          () => _pollProblem =
              'This is taking longer than usual. The server is still working on it.',
        );
        return;
      }
    }
  }

  void _checkAgain() {
    final int? id = _scanId;
    if (id == null) return;
    setState(() => _pollProblem = null);
    _poll(id);
  }

  void _startOver() {
    setState(() {
      _scanId = null;
      _draft = null;
      _supplier = null;
      _duplicates = <String>{};
      _error = null;
      _pollProblem = null;
      _stage = _Stage.pick;
    });
  }

  // ---- Review ---------------------------------------------------------------

  /// Marks lines whose name + batch number is already in stock.
  Future<void> _checkDuplicates() async {
    final InvoiceDraft? draft = _draft;
    if (draft == null) return;
    final int run = ++_duplicateCheck;
    final MedicineProvider mp = context.read<MedicineProvider>();
    final Set<String> found = <String>{};
    for (final InvoiceDraftLine l in draft.lines) {
      if (l.batchNo.trim().isEmpty) continue;
      if (await mp.isDuplicate(l.target?.name ?? l.name, l.batchNo)) {
        found.add(l.id);
      }
    }
    if (mounted && run == _duplicateCheck) setState(() => _duplicates = found);
  }

  void _setLines(List<InvoiceDraftLine> lines) {
    setState(() => _draft = _draft!.copyWith(lines: lines));
    _checkDuplicates();
  }

  Future<void> _edit(InvoiceDraftLine line) async {
    final InvoiceDraftLine? edited =
        await showModalBottomSheet<InvoiceDraftLine>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: AppColors.card,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppRadii.cardLg),
            ),
          ),
          builder: (_) => _LineEditor(line: line),
        );
    if (edited == null || !mounted || _draft == null) return;
    InvoiceDraftLine next = edited;
    // A corrected name may now match one of the shop's medicines.
    if (next.product == null) {
      final ProductStock? p = InvoiceDraftMapper.matchProduct(
        name: next.name,
        manufacturer: next.manufacturer,
        barcode: next.barcode,
        products: context.read<MedicineProvider>().products,
      );
      if (p != null) next = next.copyWith(product: p, unit: p.unit);
    }
    _setLines(<InvoiceDraftLine>[
      for (final InvoiceDraftLine l in _draft!.lines)
        l.id == line.id ? next : l,
    ]);
  }

  void _remove(InvoiceDraftLine line) {
    final List<InvoiceDraftLine> lines = List<InvoiceDraftLine>.of(
      _draft!.lines,
    );
    final int index = lines.indexWhere((InvoiceDraftLine l) => l.id == line.id);
    if (index < 0) return;
    lines.removeAt(index);
    _setLines(lines);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Removed ${line.name}'),
          action: SnackBarAction(
            label: 'UNDO',
            onPressed: () {
              if (!mounted || _draft == null || _stage != _Stage.review) return;
              final List<InvoiceDraftLine> back = List<InvoiceDraftLine>.of(
                _draft!.lines,
              );
              back.insert(index > back.length ? back.length : index, line);
              _setLines(back);
            },
          ),
        ),
      );
  }

  Future<void> _addToStock() async {
    final InvoiceDraft draft = _draft!;
    final int invalid = draft.lines
        .where((InvoiceDraftLine l) => !l.isValid)
        .length;
    if (invalid > 0) {
      _toast(
        invalid == 1
            ? 'Fix the item marked in red first (tap it to edit, or remove it).'
            : 'Fix the $invalid items marked in red first (tap to edit, or remove them).',
      );
      return;
    }
    final MedicineProvider mp = context.read<MedicineProvider>();
    final DateTime now = DateTime.now();
    const Uuid uuid = Uuid();
    final List<Medicine> items = <Medicine>[
      for (final InvoiceDraftLine l in draft.lines)
        l.toMedicine(id: uuid.v4(), now: now),
    ];
    if (!mp.canAddProducts(mp.countNewProducts(items))) {
      _openUpgrade();
      return;
    }
    final int dupes = draft.lines
        .where((InvoiceDraftLine l) => _duplicates.contains(l.id))
        .length;
    if (dupes > 0 && !(await _confirmDuplicates(dupes))) return;
    if (!mounted) return;

    setState(() => _stage = _Stage.saving);
    final AddResult result = await mp.addFromInvoice(items);
    if (!mounted) return;
    if (result != AddResult.success) {
      setState(() => _stage = _Stage.review);
      _openUpgrade();
      return;
    }
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String from = draft.invoiceNo.isEmpty
        ? ''
        : ' from invoice ${draft.invoiceNo}';
    Navigator.of(context).pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Added ${items.length} item${items.length == 1 ? '' : 's'}$from',
          ),
        ),
      );
  }

  // ---- Purchase entry ----------------------------------------------------------

  /// Looks the bill's supplier up among the shop's suppliers (by GSTIN,
  /// else an exact name). Also tells whether purchase entries are possible
  /// (the server is reachable).
  Future<void> _findSupplier() async {
    final InvoiceDraft? draft = _draft;
    final String? token;
    try {
      token = context.read<AuthService>().token;
    } on ProviderNotFoundException {
      return; // signed-out shells (tests): only adding to stock
    }
    if (draft == null || token == null) return;
    final String gstin = draft.supplierGstin.trim().toUpperCase();
    final String name = draft.supplierName.trim();
    final ApiOutcome<ApiPage<Party>> r = await _accounts.parties(
      token,
      type: 'supplier',
      query: gstin.isNotEmpty ? gstin : (name.isNotEmpty ? name : null),
    );
    if (!mounted || _draft != draft) return;
    Party? found;
    for (final Party p in r.value?.items ?? const <Party>[]) {
      final bool sameGstin = gstin.isNotEmpty && p.gstin == gstin;
      final bool sameName =
          gstin.isEmpty && p.name.toLowerCase() == name.toLowerCase();
      if (sameGstin || sameName) found = p;
    }
    setState(() {
      _accountsOnline = r.isOk;
      _supplier ??= found;
    });
  }

  Future<void> _chooseSupplier() async {
    final InvoiceDraft? draft = _draft;
    final Party? p = await pickParty(
      context,
      suppliers: true,
      api: _accounts,
      name: draft == null || draft.supplierName.isEmpty
          ? null
          : draft.supplierName,
      gstin: draft == null || draft.supplierGstin.isEmpty
          ? null
          : draft.supplierGstin.toUpperCase(),
    );
    if (p != null && mounted) {
      setState(() {
        _supplier = p;
        _accountsOnline = true;
      });
    }
  }

  Future<void> _pickInvoiceDate() async {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime? d = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: today,
      initialDate: _invoiceDate == null || _invoiceDate!.isAfter(today)
          ? today
          : _invoiceDate!,
    );
    if (d != null) setState(() => _invoiceDate = d);
  }

  /// Records the supplier's bill on the server: it creates the batches and
  /// the stock movements, which come back to this device by sync. Nothing
  /// is added locally, so the stock is counted once.
  Future<void> _recordPurchase() async {
    final InvoiceDraft draft = _draft!;
    final Party supplier = _supplier!;
    final int invalid = draft.lines
        .where((InvoiceDraftLine l) => !l.isValid)
        .length;
    if (invalid > 0) {
      _toast(
        invalid == 1
            ? 'Fix the item marked in red first (tap it to edit, or remove it).'
            : 'Fix the $invalid items marked in red first (tap to edit, or remove them).',
      );
      return;
    }
    final String invoiceNo = _invoiceNo.text.trim();
    final DateTime? invoiceDate = _invoiceDate;
    if (invoiceNo.isEmpty || invoiceDate == null) {
      _toast("Enter the supplier's invoice number and date.");
      return;
    }
    if (invoiceDate.isAfter(DateTime.now())) {
      _toast('The invoice date is in the future - check it.');
      return;
    }
    final MedicineProvider mp = context.read<MedicineProvider>();
    final DateTime now = DateTime.now();
    final int newOnes = mp.countNewProducts(
      draft.lines.map(
        (InvoiceDraftLine l) => l.toMedicine(id: l.id, now: now),
      ),
    );
    if (!mp.canAddProducts(newOnes)) {
      _openUpgrade();
      return;
    }
    final int dupes = draft.lines
        .where((InvoiceDraftLine l) => _duplicates.contains(l.id))
        .length;
    if (dupes > 0 && !(await _confirmDuplicates(dupes))) return;
    if (!mounted) return;
    final AuthService auth = context.read<AuthService>();
    final SyncEngine sync = context.read<SyncEngine>();
    final String? token = auth.token;
    if (token == null) return;

    setState(() => _stage = _Stage.saving);
    // Medicines and batches this device hasn't sent yet go first, so the
    // purchase can refer to them.
    if (sync.pending > 0) {
      await sync.syncNow();
      final DateTime until = DateTime.now().add(const Duration(seconds: 15));
      while (sync.status == SyncStatus.syncing &&
          DateTime.now().isBefore(until)) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    final DocResult<Purchase> r = await _accounts.createPurchase(
      token,
      PurchaseFromInvoice.body(
        id: _purchaseId,
        partyId: supplier.id,
        invoiceNo: invoiceNo,
        invoiceDate: invoiceDate,
        lines: draft.lines,
        newProductId: (InvoiceDraftLine l) =>
            _newProductIds.putIfAbsent(l.id, () => const Uuid().v4()),
        deviceId: auth.deviceId,
        scanId: _scanId,
      ),
    );
    if (!mounted) return;
    if (!r.isOk) {
      setState(() => _stage = _Stage.review);
      switch (r.error) {
        case 'plan_limit':
          _openUpgrade();
        case 'duplicate_invoice':
          await showDialog<void>(
            context: context,
            builder: (BuildContext ctx) => AlertDialog(
              title: const Text('Already entered'),
              content: Text(
                'Invoice $invoiceNo from ${supplier.name} is already recorded, '
                'so its stock was not added again.',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        default:
          _toast(
            r.isOffline
                ? "Couldn't reach the server, so the purchase is not confirmed. "
                      "Tap Record purchase again - it won't be added twice."
                : (r.message ?? 'Could not record the purchase.'),
          );
      }
      return;
    }
    // Pull the new batches and stock now.
    await sync.syncNow();
    await mp.load();
    if (!mounted) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final int n = draft.lines.length;
    Navigator.of(context).pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            r.replayed
                ? 'This purchase was already recorded.'
                : 'Purchase $invoiceNo recorded: $n item${n == 1 ? '' : 's'} added to stock',
          ),
        ),
      );
  }

  void _openUpgrade() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const UpgradeScreen()));
  }

  Future<bool> _confirmDuplicates(int count) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Already in stock?'),
        content: Text(
          count == 1
              ? 'One item has a batch number that is already in your stock. '
                    'This invoice may have been added before. Add it anyway?'
              : '$count items have batch numbers that are already in your stock. '
                    'This invoice may have been added before. Add them anyway?',
        ),
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
    return ok ?? false;
  }

  Future<bool> _confirmDiscard() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Discard this invoice?'),
        content: const Text("Its items haven't been added to your stock."),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep reviewing'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.statusRed),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _leaveAfterConfirm() async {
    if (await _confirmDiscard() && mounted) Navigator.of(context).pop();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ---- UI ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final bool saving = _stage == _Stage.saving;
    final bool reviewing = _stage == _Stage.review;
    return PopScope(
      // Leaving the review would lose the checked items: ask first.
      canPop: !saving && !reviewing,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop && !saving) _leaveAfterConfirm();
      },
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: AppBar(title: const Text('Scan purchase invoice')),
        body: SafeArea(top: false, child: _readable(_body())),
        bottomNavigationBar: reviewing || saving ? _reviewBar() : null,
      ),
    );
  }

  /// Keeps lines a readable length on a wide desktop window ([fitHeight]:
  /// only as tall as [child], for the bottom bar).
  static Widget _readable(Widget child, {bool fitHeight = false}) => Align(
    alignment: Alignment.topCenter,
    heightFactor: fitHeight ? 1 : null,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: child,
    ),
  );

  Widget _body() {
    switch (_stage) {
      case _Stage.pick:
        return _pickView();
      case _Stage.uploading:
        return const _Waiting(
          title: 'Uploading the invoice…',
          text: 'Keep this screen open.',
        );
      case _Stage.reading:
        return _readingView();
      case _Stage.review:
      case _Stage.saving:
        return _reviewView();
    }
  }

  Widget _pickView() {
    final SyncEngine sync = context.watch<SyncEngine>();
    final bool offline = _offline || sync.status == SyncStatus.offline;
    void Function()? pick(_Source s) => offline ? null : () => _pick(s);
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
      children: <Widget>[
        const _Notice(
          icon: Icons.document_scanner_outlined,
          color: AppColors.green,
          bg: AppColors.card,
          title: 'Add stock from a supplier bill',
          text:
              'Photograph the purchase invoice or pick a PDF. Meddata reads '
              'the medicines, batches, expiry dates and rates; you check '
              'every item before anything is added.',
        ),
        const SizedBox(height: 14),
        if (offline) ...<Widget>[
          _Notice(
            icon: Icons.wifi_off_rounded,
            color: AppColors.statusAmber,
            bg: AppColors.statusAmberBg,
            title: "You're offline",
            text:
                'Reading an invoice needs an internet connection. '
                'Connect, then try again.',
            action: TextButton(
              onPressed: sync.status == SyncStatus.syncing
                  ? null
                  : () {
                      setState(() => _offline = false);
                      sync.syncNow();
                    },
              child: const Text('Try again'),
            ),
          ),
          const SizedBox(height: 14),
        ] else if (_error != null) ...<Widget>[
          _Notice(
            icon: Icons.error_outline,
            color: AppColors.statusRed,
            bg: AppColors.statusRedBg,
            title: "Couldn't read the invoice",
            text: _error!,
          ),
          const SizedBox(height: 14),
        ],
        if (AppPlatform.supportsCamera) ...<Widget>[
          PrimaryButton(
            label: 'Take a photo',
            icon: Icons.photo_camera_outlined,
            onPressed: pick(_Source.camera),
          ),
          const SizedBox(height: 12),
          SecondaryButton(
            label: 'Choose from gallery',
            icon: Icons.photo_library_outlined,
            onPressed: pick(_Source.gallery),
          ),
          const SizedBox(height: 12),
          SecondaryButton(
            label: 'Choose a PDF',
            icon: Icons.picture_as_pdf_outlined,
            onPressed: pick(_Source.file),
          ),
        ] else
          PrimaryButton(
            label: 'Choose a photo or PDF',
            icon: Icons.upload_file_outlined,
            onPressed: pick(_Source.file),
          ),
        const SizedBox(height: 20),
        const _Tips(),
      ],
    );
  }

  Widget _readingView() {
    final String? problem = _pollProblem;
    if (problem == null) {
      return _Waiting(
        title: _scanStatus == 'processing'
            ? 'Reading the invoice…'
            : 'Waiting to read the invoice…',
        text: 'This usually takes under a minute.',
        action: TextButton(onPressed: _startOver, child: const Text('Cancel')),
      );
    }
    return _Waiting(
      icon: Icons.cloud_off_outlined,
      title: 'Still waiting for the result',
      text: problem,
      action: Column(
        children: <Widget>[
          PrimaryButton(
            label: 'Check again',
            expand: false,
            onPressed: _checkAgain,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _startOver,
            child: const Text('Scan a different invoice'),
          ),
        ],
      ),
    );
  }

  Widget _reviewView() {
    final InvoiceDraft draft = _draft!;
    final MedicineProvider mp = context.watch<MedicineProvider>();
    final DateTime today = DateTime.now();
    final int newMedicines = mp.countNewProducts(
      draft.lines.map(
        (InvoiceDraftLine l) => l.toMedicine(id: l.id, now: today),
      ),
    );
    final int toFix = draft.lines
        .where((InvoiceDraftLine l) => !l.isValid)
        .length;
    final List<String> header = <String>[
      if (draft.invoiceNo.isNotEmpty) 'Invoice ${draft.invoiceNo}',
      if (draft.invoiceDate != null) Fmt.date(draft.invoiceDate!),
    ];
    final List<String> counts = <String>[
      '${draft.lines.length} item${draft.lines.length == 1 ? '' : 's'}',
      if (newMedicines > 0)
        '$newMedicines new medicine${newMedicines == 1 ? '' : 's'}',
      if (toFix > 0) '$toFix to fix',
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                draft.supplierName.isEmpty
                    ? 'Supplier not found on the bill'
                    : draft.supplierName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              if (draft.supplierGstin.isNotEmpty)
                Text(
                  'GSTIN ${draft.supplierGstin}',
                  style: const TextStyle(color: AppColors.muted),
                ),
              if (header.isNotEmpty)
                Text(
                  header.join(' · '),
                  style: const TextStyle(color: AppColors.muted),
                ),
              const SizedBox(height: 8),
              Text(
                counts.join(' · '),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: toFix > 0 ? AppColors.statusRed : AppColors.green,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Check each item against the bill. Tap an item to fix it.',
                style: TextStyle(fontSize: 12.5, color: AppColors.muted),
              ),
            ],
          ),
        ),
        // Online: record the bill in a supplier's account. Offline the
        // items are only added to stock, as before.
        if (_accountsOnline || _supplier != null) ...<Widget>[
          const SizedBox(height: 10),
          _purchaseCard(),
        ],
        if (draft.notes.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          _Notice(
            icon: Icons.info_outline,
            color: AppColors.statusAmber,
            bg: AppColors.statusAmberBg,
            title: 'Double-check',
            text: draft.notes,
          ),
        ],
        if (!mp.canAddProducts(newMedicines)) ...<Widget>[
          const SizedBox(height: 10),
          _Notice(
            icon: Icons.lock_outline,
            color: AppColors.statusRed,
            bg: AppColors.statusRedBg,
            title: 'Free plan limit',
            text:
                'The free plan holds ${AppConstants.freeTierMedicineLimit} '
                'medicines, so there is room for '
                '${(AppConstants.freeTierMedicineLimit - mp.productCount).clamp(0, AppConstants.freeTierMedicineLimit)} '
                'more; this invoice adds $newMedicines. Upgrade, or remove '
                'some new medicines.',
            action: TextButton(
              onPressed: _openUpgrade,
              child: const Text('Upgrade'),
            ),
          ),
        ],
        const SizedBox(height: 12),
        for (final InvoiceDraftLine line in draft.lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _LineCard(
              key: ValueKey<String>(line.id),
              line: line,
              duplicate: _duplicates.contains(line.id),
              today: today,
              onEdit: _stage == _Stage.review ? () => _edit(line) : null,
              onRemove: _stage == _Stage.review ? () => _remove(line) : null,
            ),
          ),
        if (draft.lines.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'All items removed. Scan another invoice, or go back.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted),
            ),
          ),
      ],
    );
  }

  /// Record the bill as a purchase from a supplier (online), or only add
  /// the items to stock.
  Widget _purchaseCard() {
    final Party? supplier = _supplier;
    final bool editable = _stage == _Stage.review;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Purchase entry',
            style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink),
          ),
          const SizedBox(height: 4),
          if (supplier == null) ...<Widget>[
            Text(
              _accountsOnline
                  ? 'Choose the supplier to record this bill in their account '
                        '(stock is added on the server for all devices). '
                        'Without one, the items are only added to stock.'
                  : 'Items will only be added to stock. Recording the bill '
                        "in a supplier's account needs internet.",
              style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
            ),
            if (_accountsOnline)
              TextButton.icon(
                onPressed: editable ? _chooseSupplier : null,
                icon: const Icon(Icons.local_shipping_outlined, size: 18),
                label: const Text('Choose supplier'),
              ),
          ] else ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Supplier: ${supplier.name}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: editable ? _chooseSupplier : null,
                  child: const Text('Change'),
                ),
                IconButton(
                  tooltip: 'Only add to stock',
                  onPressed: editable
                      ? () => setState(() => _supplier = null)
                      : null,
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextField(
                controller: _invoiceNo,
                enabled: editable,
                maxLength: 32,
                decoration: const InputDecoration(
                  labelText: "Supplier's invoice no.",
                  counterText: '',
                ),
              ),
            ),
            Material(
              type: MaterialType.transparency,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                enabled: editable,
                leading: const Icon(
                  Icons.event_outlined,
                  color: AppColors.green,
                ),
                title: const Text('Invoice date'),
                subtitle: Text(
                  _invoiceDate == null ? 'Not set' : Fmt.date(_invoiceDate!),
                ),
                onTap: _pickInvoiceDate,
              ),
            ),
            const Text(
              'Stock is added once, on the server, and reaches every device '
              "by sync. The bill goes into the supplier's account with its input GST.",
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _reviewBar() {
    final int count = _draft?.lines.length ?? 0;
    final bool saving = _stage == _Stage.saving;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      padding: EdgeInsets.fromLTRB(
        18,
        12,
        18,
        MediaQuery.paddingOf(context).bottom + 12,
      ),
      child: _readable(
        Row(
          children: <Widget>[
            Expanded(
              child: SecondaryButton(
                label: 'Start over',
                onPressed: saving
                    ? null
                    : () async {
                        if (await _confirmDiscard() && mounted) _startOver();
                      },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: PrimaryButton(
                label: saving
                    ? (_supplier != null ? 'Recording…' : 'Adding…')
                    : _supplier != null
                    ? 'Record purchase ($count)'
                    : 'Add $count item${count == 1 ? '' : 's'}',
                onPressed: saving || count == 0
                    ? null
                    : (_supplier != null ? _recordPurchase : _addToStock),
              ),
            ),
          ],
        ),
        fitHeight: true,
      ),
    );
  }
}

/// A full-screen wait state: spinner (or icon), title, text, optional action.
class _Waiting extends StatelessWidget {
  const _Waiting({
    required this.title,
    required this.text,
    this.icon,
    this.action,
  });

  final String title;
  final String text;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon == null)
              const CircularProgressIndicator()
            else
              Icon(icon, size: 48, color: AppColors.muted),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted),
            ),
            if (action != null) ...<Widget>[
              const SizedBox(height: 20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// A tinted card with an icon, a title, a message and an optional action.
class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.color,
    required this.bg,
    required this.title,
    required this.text,
    this.action,
  });

  final IconData icon;
  final Color color;
  final Color bg;
  final String title;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(text, style: const TextStyle(color: AppColors.ink)),
                if (action != null)
                  Align(alignment: Alignment.centerRight, child: action),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tips extends StatelessWidget {
  const _Tips();

  static const List<String> _tips = <String>[
    'Lay the bill flat in good light, with the whole page in the photo.',
    'One invoice per scan. For a bill with several pages, use its PDF.',
    'Nothing is added until you check the items and tap Add.',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Tips',
          style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink),
        ),
        const SizedBox(height: 6),
        for (final String tip in _tips)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const ExcludeSemantics(
                  child: Text('•  ', style: TextStyle(color: AppColors.muted)),
                ),
                Expanded(
                  child: Text(
                    tip,
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One invoice line in the review list.
class _LineCard extends StatelessWidget {
  const _LineCard({
    super.key,
    required this.line,
    required this.duplicate,
    required this.today,
    this.onEdit,
    this.onRemove,
  });

  final InvoiceDraftLine line;
  final bool duplicate;
  final DateTime today;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  static String pct(double v) => v == v.roundToDouble()
      ? v.toStringAsFixed(0)
      : v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');

  @override
  Widget build(BuildContext context) {
    final List<String> problems = line.problems;
    final List<String> warnings = <String>[
      ...line.warnings(today),
      if (duplicate) 'Batch already in stock',
    ];
    final ProductStock? product = line.target;
    final String title =
        product?.name ?? (line.name.isEmpty ? 'No name' : line.name);
    final String unit = line.stockUnit;
    final String qty = <String>[
      'Qty ${line.quantity}'
          '${line.freeQuantity > 0 ? ' + ${line.freeQuantity} free' : ''}',
      if (line.pack.isNotEmpty) 'pack ${line.pack}',
    ].join(' · ');
    final String price = <String>[
      'MRP ${line.mrp > 0 ? Fmt.money(line.mrp) : '—'}',
      'Rate ${line.rate > 0 ? Fmt.money(line.rate) : '—'}'
          '${line.discountPercent > 0 ? ' (−${pct(line.discountPercent)}%)' : ''}',
      if (line.gstPercent != null) 'GST ${pct(line.gstPercent!)}%',
    ].join(' · ');
    const TextStyle body = TextStyle(fontSize: 13, color: AppColors.ink);

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.card),
        onTap: onEdit,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(
              color: problems.isEmpty ? AppColors.border : AppColors.statusRed,
              width: problems.isEmpty ? 1 : 1.5,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    if (product != null &&
                        product.name.toLowerCase() != line.name.toLowerCase())
                      Text(
                        'On the bill: ${line.name}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                    const SizedBox(height: 6),
                    product == null
                        ? const StatusPill(
                            text: 'New medicine',
                            color: AppColors.orange,
                            bg: Color(0x1FFF6B2C),
                          )
                        : StatusPill.inStock('New batch'),
                    const SizedBox(height: 8),
                    Text(
                      'Batch ${line.batchNo.isEmpty ? '—' : line.batchNo}'
                      ' · Exp ${line.expiry == null ? '—' : Fmt.date(line.expiry!)}',
                      style: body,
                    ),
                    Text('$qty → ${line.stockQuantity} $unit', style: body),
                    Text(price, style: body),
                    if (line.countsPieces && line.pricePack != line.unitsPerPack)
                      Text(
                        'Per ${line.pricePack > 1 ? '${PackSize.packNoun(unit)} of ${line.pricePack}' : unit.toLowerCase()}: '
                        'MRP ${Fmt.money(line.mrpPerUnit)}'
                        ' · cost ${Fmt.money(line.costPerUnit)}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.muted,
                        ),
                      ),
                    for (final String p in problems)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          p,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.statusRed,
                          ),
                        ),
                      ),
                    if (warnings.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          warnings.join(' · '),
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.statusAmber,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Column(
                children: <Widget>[
                  IconButton(
                    tooltip: 'Edit $title',
                    icon: const Icon(
                      Icons.edit_outlined,
                      color: AppColors.muted,
                    ),
                    onPressed: onEdit,
                  ),
                  IconButton(
                    tooltip: 'Remove $title',
                    icon: const Icon(
                      Icons.delete_outline,
                      color: AppColors.statusRed,
                    ),
                    onPressed: onRemove,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet to fix one line. Returns the edited line (or null).
class _LineEditor extends StatefulWidget {
  const _LineEditor({required this.line});

  final InvoiceDraftLine line;

  @override
  State<_LineEditor> createState() => _LineEditorState();
}

class _LineEditorState extends State<_LineEditor> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _maker;
  late final TextEditingController _batch;
  late final TextEditingController _qty;
  late final TextEditingController _free;
  late final TextEditingController _perPack;
  late final TextEditingController _mrp;
  late final TextEditingController _rate;
  late final TextEditingController _discount;
  late DateTime? _expiry;
  late DateTime? _mfg;
  late String _unit;

  /// Add as a batch of the matched product (false = as a new medicine).
  late bool _linked;
  String? _problem;

  @override
  void initState() {
    super.initState();
    final InvoiceDraftLine l = widget.line;
    String money(double v) => v > 0 ? v.toStringAsFixed(2) : '';
    _name = TextEditingController(text: l.name);
    _maker = TextEditingController(text: l.manufacturer);
    _batch = TextEditingController(text: l.batchNo);
    _qty = TextEditingController(text: l.quantity > 0 ? '${l.quantity}' : '');
    _free = TextEditingController(
      text: l.freeQuantity > 0 ? '${l.freeQuantity}' : '',
    );
    _perPack = TextEditingController(text: '${l.unitsPerPack}');
    _mrp = TextEditingController(text: money(l.mrp));
    _rate = TextEditingController(text: money(l.rate));
    _discount = TextEditingController(
      text: l.discountPercent > 0 ? _LineCard.pct(l.discountPercent) : '',
    );
    _expiry = l.expiry;
    _mfg = l.mfgDate;
    _unit = l.unit;
    _linked = l.target != null;
  }

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _name,
      _maker,
      _batch,
      _qty,
      _free,
      _perPack,
      _mrp,
      _rate,
      _discount,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  int _int(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;
  double _double(TextEditingController c) =>
      double.tryParse(c.text.trim()) ?? 0;

  /// The line as currently edited.
  InvoiceDraftLine get _edited => widget.line.copyWith(
    name: _name.text.trim(),
    manufacturer: _maker.text.trim(),
    batchNo: _batch.text.trim(),
    expiry: _expiry,
    mfgDate: _mfg,
    clearMfgDate: _mfg == null,
    quantity: _int(_qty),
    freeQuantity: _int(_free),
    mrp: _double(_mrp),
    rate: _double(_rate),
    discountPercent: _double(_discount).clamp(0.0, 100.0).toDouble(),
    unit: _unit,
    unitsPerPack: _int(_perPack) < 1 ? 1 : _int(_perPack),
    asNew: widget.line.product != null && !_linked,
  );

  Future<void> _pickDate({required bool expiry}) async {
    final DateTime now = DateTime.now();
    final DateTime initial =
        (expiry ? _expiry : _mfg) ??
        (expiry ? DateTime(now.year + 1, now.month, now.day) : now);
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: expiry ? 'Expiry date' : 'Manufacture date',
    );
    if (picked == null) return;
    setState(() {
      if (expiry) {
        _expiry = picked;
      } else {
        _mfg = picked;
      }
      _problem = null;
    });
  }

  void _save() {
    final bool fieldsOk = _form.currentState!.validate();
    final InvoiceDraftLine line = _edited;
    // The form checks the fields; the line itself checks the dates too.
    final List<String> problems = line.problems;
    setState(() => _problem = problems.isEmpty ? null : problems.first);
    if (!fieldsOk || problems.isNotEmpty) return;
    Navigator.of(context).pop(line);
  }

  @override
  Widget build(BuildContext context) {
    final InvoiceDraftLine preview = _edited;
    final ProductStock? product = widget.line.product;
    final String unit = preview.stockUnit;
    // Title and buttons stay put; only the fields scroll (a plain scroll
    // view, so every field stays built and is validated).
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _form,
        onChanged: () => setState(() {}),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 6, 0),
              child: Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      'Edit item',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (product != null) ...<Widget>[
                      _Notice(
                        icon: _linked
                            ? Icons.inventory_2_outlined
                            : Icons.add_box_outlined,
                        color: AppColors.green,
                        bg: AppColors.statusGreenBg,
                        title: _linked
                            ? 'New batch of ${product.name}'
                            : 'New medicine',
                        text: _linked
                            ? 'Counted in ${product.unit.toLowerCase()}, like '
                                  'your other batches of it.'
                            : 'Added as a separate medicine.',
                        action: TextButton(
                          onPressed: () => setState(() => _linked = !_linked),
                          child: Text(
                            _linked
                                ? 'Add as a new medicine instead'
                                : 'Add as a batch of ${product.name}',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (!_linked) ...<Widget>[
                      _field(
                        _name,
                        'Medicine name *',
                        validator: (String? v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      _field(_maker, 'Manufacturer'),
                      const SizedBox(height: 12),
                    ],
                    _field(_batch, 'Batch no.'),
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _dateButton(
                            label: 'Expiry *',
                            value: _expiry,
                            onTap: () => _pickDate(expiry: true),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _dateButton(
                            label: 'Mfg date',
                            value: _mfg,
                            onTap: () => _pickDate(expiry: false),
                            onClear: _mfg == null
                                ? null
                                : () => setState(() => _mfg = null),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: _field(
                            _qty,
                            'Qty (packs) *',
                            number: true,
                            validator: (_) => _int(_qty) + _int(_free) <= 0
                                ? 'Required'
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: _field(_free, 'Free', number: true)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: _linked
                              ? _readOnly('Counted in', unit)
                              : _unitDropdown(),
                        ),
                        if (kPieceUnits.contains(unit)) ...<Widget>[
                          const SizedBox(width: 12),
                          Expanded(
                            child: _field(
                              _perPack,
                              '$unit per pack',
                              number: true,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: _field(_mrp, 'MRP / pack', decimal: true),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _field(_rate, 'Rate / pack', decimal: true),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _field(_discount, 'Disc %', decimal: true),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Adds ${preview.stockQuantity} $unit · MRP '
                      '${Fmt.money(preview.mrpPerUnit)} · cost '
                      '${Fmt.money(preview.costPerUnit)} per '
                      '${preview.countsPieces ? unit.toLowerCase() : 'pack'}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.green,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.divider)),
              ),
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (_problem != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _problem!,
                        style: const TextStyle(
                          color: AppColors.statusRed,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: SecondaryButton(
                          label: 'Cancel',
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: PrimaryButton(label: 'Save', onPressed: _save),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6, left: 2),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: AppColors.muted,
      ),
    ),
  );

  Widget _field(
    TextEditingController c,
    String label, {
    bool number = false,
    bool decimal = false,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _label(label),
        TextFormField(
          controller: c,
          keyboardType: number || decimal
              ? TextInputType.numberWithOptions(decimal: decimal)
              : TextInputType.text,
          inputFormatters: number || decimal
              ? <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(
                    RegExp(decimal ? r'[0-9.]' : r'[0-9]'),
                  ),
                ]
              : null,
          textCapitalization: number || decimal
              ? TextCapitalization.none
              : TextCapitalization.characters,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: validator,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
      ],
    );
  }

  Widget _readOnly(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _label(label),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
          decoration: BoxDecoration(
            color: AppColors.canvas,
            borderRadius: BorderRadius.circular(AppRadii.input),
          ),
          child: Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
        ),
      ],
    );
  }

  Widget _unitDropdown() {
    final List<String> units = AppConstants.units.contains(_unit)
        ? AppConstants.units
        : <String>[_unit, ...AppConstants.units];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _label('Unit'),
        DropdownButtonFormField<String>(
          initialValue: _unit,
          isExpanded: true,
          items: units
              .map(
                (String u) =>
                    DropdownMenuItem<String>(value: u, child: Text(u)),
              )
              .toList(),
          onChanged: (String? v) => setState(() => _unit = v ?? _unit),
        ),
      ],
    );
  }

  Widget _dateButton({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _label(label),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.input),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.input),
              border: Border.all(color: AppColors.border, width: 1.5),
            ),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.calendar_today_outlined,
                  size: 16,
                  color: AppColors.muted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    value == null ? 'Not set' : Fmt.date(value),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: value == null ? AppColors.muted : AppColors.ink,
                    ),
                  ),
                ),
                if (onClear != null)
                  InkWell(
                    onTap: onClear,
                    borderRadius: BorderRadius.circular(20),
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(
                        Icons.close,
                        size: 16,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
