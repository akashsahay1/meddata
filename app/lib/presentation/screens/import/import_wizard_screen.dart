import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants.dart';
import '../../../core/formatters.dart';
import '../../../data/models/medicine.dart';
import '../../../data/models/stock_import.dart';
import '../../../domain/medicine_status.dart';
import '../../../domain/product_stock.dart';
import '../../../services/import/import_columns.dart';
import '../../../services/import/import_values.dart';
import '../../../services/import/sheet_table.dart';
import '../../../services/import/spreadsheet_reader.dart';
import '../../../services/import/stock_import_planner.dart';
import '../../../state/medicine_provider.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/ui_kit.dart';
import '../upgrade_screen.dart';

/// Reads a picked file (in a background isolate).
({List<SheetTable>? sheets, String? error}) _readFile(
    ({Uint8List bytes, String name}) file) {
  try {
    return (
      sheets: SpreadsheetReader.read(file.bytes, fileName: file.name),
      error: null,
    );
  } on ImportFileException catch (e) {
    return (sheets: null, error: e.message);
  } catch (e) {
    return (sheets: null, error: 'This file could not be read.');
  }
}

/// Checks every row (in a background isolate; big files take a moment).
ImportPlan _planRows(
        ({SheetTable sheet, ImportSettings settings, List<Medicine> stock}) job) =>
    StockImportPlanner.plan(job.sheet, job.settings, inventory: job.stock);

enum _Step { file, header, columns, check, saving, done }

enum _Filter { all, importing, skipped, warnings }

/// A chosen file's name and content.
typedef PickedSpreadsheet = ({String name, Uint8List bytes});

const XTypeGroup _fileTypes = XTypeGroup(
  label: 'Excel or CSV',
  extensions: <String>['xlsx', 'csv', 'xls'],
  // Phones label CSVs in many ways; whatever is picked is checked by content.
  mimeTypes: <String>[
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'text/csv',
    'text/comma-separated-values',
    'application/csv',
    'text/plain',
    'application/vnd.ms-excel',
    'application/octet-stream',
  ],
  uniformTypeIdentifiers: <String>[
    'org.openxmlformats.spreadsheetml.sheet',
    'public.comma-separated-values-text',
    'public.plain-text',
    'com.microsoft.excel.xls',
  ],
);

/// The system file picker (phones and Windows); null when cancelled.
Future<PickedSpreadsheet?> pickSpreadsheet() async {
  final XFile? file = await openFile(acceptedTypeGroups: <XTypeGroup>[_fileTypes]);
  if (file == null) return null;
  if (await file.length() > SpreadsheetReader.maxBytes) {
    throw const ImportFileException(
        'The file is too large (over 25 MB). Split it into smaller files.');
  }
  return (name: file.name, bytes: await file.readAsBytes());
}

/// Excel / CSV stock import: pick a file → choose the sheet and its header
/// row → match columns to medicine details → check every row (what will be
/// imported, what is skipped and why) → save in one go. Rows are saved
/// through the repository like medicines added by hand, so they sync.
class ImportWizardScreen extends StatefulWidget {
  const ImportWizardScreen({super.key, this.pickFile = pickSpreadsheet});

  /// Lets the user choose a file (replaceable in tests).
  final Future<PickedSpreadsheet?> Function() pickFile;

  @override
  State<ImportWizardScreen> createState() => _ImportWizardScreenState();
}

class _ImportWizardScreenState extends State<ImportWizardScreen> {
  static const List<String> _stepTitles = <String>[
    'Choose a file',
    'Find the column names',
    'Match the columns',
    'Check the rows',
  ];

  _Step _step = _Step.file;
  bool _busy = false;
  String? _error;
  String _fileName = '';
  List<SheetTable> _sheets = const <SheetTable>[];
  int _sheetIndex = 0;
  int _headerRow = -1;
  Map<ImportField, int> _columns = <ImportField, int>{};
  DateOrder _dateOrder = DateOrder.dayFirst;
  String _defaultUnit = AppConstants.units.first;
  DuplicatePolicy _duplicates = DuplicatePolicy.skip;
  bool _skipZero = true;
  ImportPlan? _plan;
  _Filter _filter = _Filter.all;
  int _planRun = 0;
  int _saved = 0;
  int _toSave = 0;
  StockImportResult? _result;

  SheetTable get _sheet => _sheets[_sheetIndex];

  // ---- actions --------------------------------------------------------------

  Future<void> _pickFile() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    PickedSpreadsheet? file;
    ({List<SheetTable>? sheets, String? error}) read;
    try {
      file = await widget.pickFile();
      read = file == null
          ? (sheets: null, error: null)
          : await compute(_readFile, (bytes: file.bytes, name: file.name));
    } on ImportFileException catch (e) {
      read = (sheets: null, error: e.message);
    } catch (e) {
      debugPrint('[Import] could not open the file: $e');
      read = (sheets: null, error: 'This file could not be opened.');
    }
    if (!mounted) return;
    if (file == null && read.error == null) {
      setState(() => _busy = false); // cancelled
      return;
    }
    final String name = file?.name ?? '';
    final List<SheetTable> sheets = <SheetTable>[
      for (final SheetTable s in read.sheets ?? const <SheetTable>[])
        if (s.filledRowCount > 0) s,
    ];
    setState(() {
      _busy = false;
      if (read.error != null || sheets.isEmpty) {
        _error = read.error ?? 'This file has no rows to import.';
        return;
      }
      _fileName = name;
      _sheets = sheets;
      _selectSheet(0);
      _step = _Step.header;
    });
  }

  void _selectSheet(int index) {
    _sheetIndex = index;
    _setHeaderRow(ColumnGuesser.guessHeaderRow(_sheet));
  }

  void _setHeaderRow(int row) {
    _headerRow = row;
    _columns = ColumnGuesser.guessColumns(_sheet, row);
    _dateOrder = _detectDateOrder();
  }

  /// A column holds one detail: picking it for one field frees it elsewhere.
  void _setColumn(ImportField field, int? col) {
    setState(() {
      if (col == null) {
        _columns.remove(field);
      } else {
        _columns.removeWhere((ImportField f, int c) => c == col);
        _columns[field] = col;
      }
      if (field == ImportField.expiryDate || field == ImportField.mfgDate) {
        _dateOrder = _detectDateOrder();
      }
    });
  }

  DateOrder _detectDateOrder() => ImportValues.detectDateOrder(<Object?>[
        for (final ImportField f in <ImportField>[
          ImportField.expiryDate,
          ImportField.mfgDate,
        ])
          if (_columns[f] != null)
            ...ColumnGuesser.sampleValues(_sheet, _headerRow, _columns[f]!,
                max: 1000),
      ]);

  Future<void> _check() async {
    final MedicineProvider mp = context.read<MedicineProvider>();
    final int run = ++_planRun;
    setState(() => _busy = true);
    final ImportSettings settings = ImportSettings(
      headerRow: _headerRow,
      columns: Map<ImportField, int>.of(_columns),
      dateOrder: _dateOrder,
      duplicates: _duplicates,
      skipZeroQuantity: _skipZero,
      defaultUnit: _defaultUnit,
      newMedicineRoom: mp.newMedicineRoom,
    );
    ImportPlan? plan;
    try {
      plan = await compute(_planRows, (
        sheet: _sheet,
        settings: settings,
        stock: <Medicine>[for (final ProductStock p in mp.products) ...p.batches],
      ));
    } catch (e) {
      debugPrint('[Import] check failed: $e');
    }
    if (!mounted || run != _planRun) return;
    if (plan == null) {
      setState(() => _busy = false);
      _toast('Could not check the rows. Please try again.');
      return;
    }
    setState(() {
      _busy = false;
      _plan = plan;
      _step = _Step.check;
    });
  }

  Future<void> _import() async {
    final ImportPlan? plan = _plan;
    if (plan == null || plan.toSave.isEmpty || _busy) return;
    final MedicineProvider mp = context.read<MedicineProvider>();
    if (plan.overLimit > 0 && !await _confirmFreeLimit(plan, mp)) return;
    if (!mounted) return;
    setState(() {
      _step = _Step.saving;
      _saved = 0;
      _toSave = plan.toSave.length;
    });
    try {
      final StockImportResult result = await mp.importStock(plan.toSave,
          onProgress: (int done, int total) {
        if (mounted) {
          setState(() {
            _saved = done;
            _toSave = total;
          });
        }
      });
      if (!mounted) return;
      setState(() {
        _result = result;
        _step = _Step.done;
      });
    } catch (e) {
      debugPrint('[Import] save failed: $e');
      if (!mounted) return;
      setState(() => _step = _Step.check);
      _toast('Import failed and nothing was saved. Please try again.');
    }
  }

  Future<bool> _confirmFreeLimit(ImportPlan plan, MedicineProvider mp) async {
    final int room = mp.newMedicineRoom ?? 0;
    final String? choice = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Free plan limit'),
        content: Text(
          'The free plan keeps up to ${Entitlement.free.freeLimit} medicines '
          'and you have ${mp.productCount}. This file has '
          '${plan.newMedicinesInFile} new medicines, so '
          '${room == 0 ? 'none of them fit' : 'only $room can be added'} '
          'and ${plan.overLimit} rows will be skipped.\n\n'
          'Upgrade to import everything.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('upgrade'),
            child: const Text('Upgrade'),
          ),
          if (plan.importable > 0)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('import'),
              child: Text('Import ${plan.importable}'),
            ),
        ],
      ),
    );
    if (choice == 'upgrade' && mounted) await _upgrade();
    return choice == 'import';
  }

  Future<void> _upgrade() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const UpgradeScreen()),
    );
    // The plan may have changed (e.g. now unlimited).
    if (mounted && _step == _Step.check) await _check();
  }

  void _back() {
    setState(() {
      _planRun++; // a check still running must not move us forward again
      _busy = false;
      switch (_step) {
        case _Step.header:
          _step = _Step.file;
        case _Step.columns:
          _step = _Step.header;
        case _Step.check:
          _step = _Step.columns;
        case _Step.file:
        case _Step.saving:
        case _Step.done:
          break;
      }
    });
  }

  void _restart() {
    setState(() {
      _step = _Step.file;
      _error = null;
      _fileName = '';
      _sheets = const <SheetTable>[];
      _plan = null;
      _result = null;
      _filter = _Filter.all;
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ---- layout ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final int? stepIndex = switch (_step) {
      _Step.file => 0,
      _Step.header => 1,
      _Step.columns => 2,
      _Step.check => 3,
      _ => null,
    };
    final Widget? bar = _bottomBar();
    return PopScope(
      canPop: _step == _Step.file || _step == _Step.done,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop && _step != _Step.saving) _back();
      },
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: AppBar(
          title: const Text('Import stock'),
          automaticallyImplyLeading: _step != _Step.saving,
        ),
        body: Column(
          children: <Widget>[
            Expanded(
              child: SafeArea(
                top: false,
                bottom: bar == null,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _maxWidth),
                    child: Column(
                      children: <Widget>[
                        if (stepIndex != null)
                          _StepBar(
                            index: stepIndex,
                            title: _stepTitles[stepIndex],
                            fileName: stepIndex > 0 ? _fileLabel() : null,
                          ),
                        SizedBox(
                          height: 3,
                          child: _busy && _step != _Step.file
                              ? const LinearProgressIndicator()
                              : null,
                        ),
                        Expanded(child: _body()),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            ?bar,
          ],
        ),
      ),
    );
  }

  /// Content width on wide windows (Windows PC, tablets).
  static const double _maxWidth = 760;

  /// Selected segments in brand green, like the other choices in the app.
  static final ButtonStyle _segmentStyle = SegmentedButton.styleFrom(
    selectedBackgroundColor: AppColors.green,
    selectedForegroundColor: Colors.white,
    foregroundColor: AppColors.ink,
    backgroundColor: AppColors.card,
    side: const BorderSide(color: AppColors.border),
  );

  String _fileLabel() {
    final List<String> parts = <String>[
      _fileName,
      if (_sheets.length > 1) _sheet.name,
    ];
    return parts.where((String p) => p.isNotEmpty).join(' · ');
  }

  Widget _body() {
    switch (_step) {
      case _Step.file:
        return _fileStep();
      case _Step.header:
        return _headerStep();
      case _Step.columns:
        return _columnsStep();
      case _Step.check:
        return _checkStep();
      case _Step.saving:
        return _savingStep();
      case _Step.done:
        return _doneStep();
    }
  }

  Widget? _bottomBar() {
    final Widget? back = switch (_step) {
      _Step.header || _Step.columns || _Step.check =>
        SecondaryButton(label: 'Back', onPressed: _busy ? null : _back),
      _Step.done => SecondaryButton(label: 'Import more', onPressed: _restart),
      _ => null,
    };
    final List<ImportField> missing = <ImportField>[
      for (final ImportField f in ImportField.values)
        if (f.required && !_columns.containsKey(f)) f,
    ];
    final Widget? next = switch (_step) {
      _Step.file => PrimaryButton(
          label: _busy ? 'Opening file…' : 'Choose file',
          icon: Icons.folder_open_outlined,
          onPressed: _busy ? null : _pickFile,
        ),
      _Step.header => PrimaryButton(
          label: 'Match columns',
          onPressed: () => setState(() => _step = _Step.columns),
        ),
      _Step.columns => PrimaryButton(
          label: 'Check rows',
          onPressed: missing.isEmpty && !_busy ? _check : null,
        ),
      _Step.check => PrimaryButton(
          label: (_plan?.importable ?? 0) == 0
              ? 'Nothing to import'
              : 'Import ${_plan!.importable} '
                  '${_plan!.importable == 1 ? 'row' : 'rows'}',
          onPressed: (_plan?.importable ?? 0) > 0 && !_busy ? _import : null,
        ),
      _Step.done => PrimaryButton(
          label: 'Done',
          onPressed: () => Navigator.of(context).pop(),
        ),
      _Step.saving => null,
    };
    if (next == null) return null;
    final EdgeInsets inset = MediaQuery.paddingOf(context);
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      padding: EdgeInsets.fromLTRB(
          18 + inset.left, 12, 18 + inset.right, 14 + inset.bottom),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth - 36),
          child: Row(
            children: <Widget>[
              if (back != null) ...<Widget>[
                Expanded(child: back),
                const SizedBox(width: 12),
              ],
              Expanded(flex: _step == _Step.done ? 1 : 2, child: next),
            ],
          ),
        ),
      ),
    );
  }

  // ---- step 1: file ---------------------------------------------------------

  Widget _fileStep() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
      children: <Widget>[
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.canvas,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.upload_file_outlined,
                    size: 26, color: AppColors.green),
              ),
              const SizedBox(height: 14),
              const Text(
                'Bring in your stock from a spreadsheet',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                "Use the stock list from your old billing software, a "
                "distributor's file or your own Excel sheet. You match the "
                'columns and check every row before anything is saved.',
                style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const _Panel(
          child: Column(
            children: <Widget>[
              _Point(Icons.description_outlined, 'Excel (.xlsx) or CSV files'),
              _Point(Icons.rule,
                  'Each row needs a medicine name, quantity and expiry date'),
              _Point(Icons.auto_awesome_outlined,
                  'Columns like Item Name, Batch, Exp, Qty, MRP, Rate, Pack '
                  'and Mfr are matched for you'),
              _Point(Icons.cloud_sync_outlined,
                  'Imported stock syncs to all your devices', last: true),
            ],
          ),
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 12),
          _Notice(
            icon: Icons.error_outline,
            color: AppColors.statusRed,
            text: _error!,
          ),
        ],
      ],
    );
  }

  // ---- step 2: sheet and header row ----------------------------------------

  Widget _headerStep() {
    final SheetTable sheet = _sheet;
    final int shown = math.min(sheet.rows.length, 30);
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
      children: <Widget>[
        if (_sheets.length > 1) ...<Widget>[
          const _Label('Sheet'),
          DropdownButtonFormField<int>(
            key: ValueKey<String>('sheet-$_sheetIndex'),
            initialValue: _sheetIndex,
            isExpanded: true,
            items: <DropdownMenuItem<int>>[
              for (int i = 0; i < _sheets.length; i++)
                DropdownMenuItem<int>(
                  value: i,
                  child: Text(
                    '${_sheets[i].name} (${_sheets[i].filledRowCount} rows)',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (int? i) {
              if (i != null) setState(() => _selectSheet(i));
            },
          ),
          const SizedBox(height: 18),
        ],
        const Text(
          'Which row has the column names?',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _headerRow >= 0
              ? "It looks like row ${_headerRow + 1}. Tap another row if "
                  "that's not right."
              : "We couldn't find column names. Tap the row that has them, "
                  'or keep "No header row".',
          style: const TextStyle(fontSize: 13, color: AppColors.muted),
        ),
        const SizedBox(height: 12),
        _ChoiceTile(
          selected: _headerRow == -1,
          leading: '–',
          title: 'No header row',
          subtitle: 'The first row is already medicine data',
          onTap: () => setState(() => _setHeaderRow(-1)),
        ),
        for (int r = 0; r < shown; r++)
          if (SheetTable.rowHasData(sheet.rows[r]))
            _ChoiceTile(
              selected: _headerRow == r,
              leading: '${r + 1}',
              title: sheet.rows[r]
                  .map(ImportValues.text)
                  .where((String t) => t.isNotEmpty)
                  .join('  ·  '),
              onTap: () => setState(() => _setHeaderRow(r)),
            ),
      ],
    );
  }

  // ---- step 3: columns ------------------------------------------------------

  /// Columns that have a name or any value, as "B · Batch" / "Column B".
  List<(int, String)> _columnChoices() {
    final SheetTable sheet = _sheet;
    final List<(int, String)> out = <(int, String)>[];
    for (int c = 0; c < sheet.columnCount; c++) {
      final String name =
          _headerRow >= 0 ? ImportValues.text(sheet.cell(_headerRow, c)) : '';
      final List<Object?> sample =
          ColumnGuesser.sampleValues(sheet, _headerRow, c, max: 1);
      if (name.isEmpty && sample.isEmpty) continue;
      final String letter = ColumnGuesser.columnLetter(c);
      out.add((
        c,
        name.isNotEmpty
            ? '$letter · $name'
            : 'Column $letter · e.g. ${ImportValues.text(sample.first)}',
      ));
    }
    return out;
  }

  Widget _columnsStep() {
    final List<(int, String)> choices = _columnChoices();
    final List<ImportField> missing = <ImportField>[
      for (final ImportField f in ImportField.values)
        if (f.required && !_columns.containsKey(f)) f,
    ];
    final bool hasDates = _columns.containsKey(ImportField.expiryDate) ||
        _columns.containsKey(ImportField.mfgDate);
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
      children: <Widget>[
        const Text(
          'Pick the column that holds each detail. We filled in our best '
          'guesses — please check them. Details marked * are needed.',
          style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.muted),
        ),
        const SizedBox(height: 12),
        _Panel(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Column(
            children: <Widget>[
              for (final ImportField f in ImportField.values)
                _fieldRow(f, choices, last: f == ImportField.values.last),
            ],
          ),
        ),
        if (missing.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          _Notice(
            icon: Icons.info_outline,
            color: AppColors.statusAmber,
            text: 'Choose a column for: '
                '${missing.map((ImportField f) => f.label).join(', ')}',
          ),
        ],
        const SizedBox(height: 16),
        if (hasDates) ...<Widget>[
          const _Label('Dates in this file are written'),
          SegmentedButton<DateOrder>(
            showSelectedIcon: false,
            style: _segmentStyle,
            segments: const <ButtonSegment<DateOrder>>[
              ButtonSegment<DateOrder>(
                value: DateOrder.dayFirst,
                label: Text('Day first · 31/12'),
              ),
              ButtonSegment<DateOrder>(
                value: DateOrder.monthFirst,
                label: Text('Month first · 12/31'),
              ),
            ],
            selected: <DateOrder>{_dateOrder},
            onSelectionChanged: (Set<DateOrder> s) =>
                setState(() => _dateOrder = s.first),
          ),
          const SizedBox(height: 16),
        ],
        const _Label('Unit for rows that have none'),
        DropdownButtonFormField<String>(
          initialValue: _defaultUnit,
          isExpanded: true,
          items: <DropdownMenuItem<String>>[
            for (final String u in AppConstants.units)
              DropdownMenuItem<String>(value: u, child: Text(u)),
          ],
          onChanged: (String? u) {
            if (u != null) setState(() => _defaultUnit = u);
          },
        ),
      ],
    );
  }

  Widget _fieldRow(ImportField f, List<(int, String)> choices,
      {required bool last}) {
    final int? col = _columns[f];
    final List<Object?> sample = col == null
        ? const <Object?>[]
        : ColumnGuesser.sampleValues(_sheet, _headerRow, col, max: 1);
    final Widget label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          f.required ? '${f.label} *' : f.label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        if (sample.isNotEmpty)
          Text(
            'e.g. ${ImportValues.text(sample.first)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
      ],
    );
    final Widget picker = DropdownButtonFormField<int>(
      key: ValueKey<String>('${f.name}-$col'),
      initialValue: col ?? -1,
      isExpanded: true,
      items: <DropdownMenuItem<int>>[
        const DropdownMenuItem<int>(
          value: -1,
          child: Text('Not in file', style: TextStyle(color: AppColors.muted)),
        ),
        for (final (int c, String name) in choices)
          DropdownMenuItem<int>(
            value: c,
            child: Text(name, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (int? c) => _setColumn(f, c == null || c < 0 ? null : c),
    );
    return Container(
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) => box.maxWidth >= 520
            ? Row(
                children: <Widget>[
                  Expanded(flex: 5, child: label),
                  const SizedBox(width: 12),
                  Expanded(flex: 6, child: picker),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[label, const SizedBox(height: 8), picker],
              ),
      ),
    );
  }

  // ---- step 4: check --------------------------------------------------------

  bool _shows(ImportRow r) {
    switch (_filter) {
      case _Filter.all:
        return true;
      case _Filter.importing:
        return r.imported;
      case _Filter.skipped:
        return !r.imported;
      case _Filter.warnings:
        return r.imported && r.warnings.isNotEmpty;
    }
  }

  Widget _checkStep() {
    final ImportPlan plan = _plan!;
    final List<ImportRow> rows = plan.rows.where(_shows).toList();
    final int? room = context.read<MedicineProvider>().newMedicineRoom;
    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
          sliver: SliverList.list(
            children: <Widget>[
              _Summary(plan: plan),
              if (plan.truncated) ...<Widget>[
                const SizedBox(height: 10),
                _Notice(
                  icon: Icons.content_cut,
                  color: AppColors.statusAmber,
                  text: 'Only the first ${StockImportPlanner.maxRows} rows '
                      'were read. Import the rest from a second file.',
                ),
              ],
              if (plan.overLimit > 0) ...<Widget>[
                const SizedBox(height: 10),
                _Notice(
                  icon: Icons.workspace_premium_outlined,
                  color: AppColors.statusAmber,
                  text: 'Free plan: ${room == 0 ? 'no more medicines fit' : 'only $room more medicines fit'}, '
                      'so ${plan.overLimit} rows are skipped.',
                  action: 'Upgrade',
                  onAction: _upgrade,
                ),
              ],
              if (plan.duplicates > 0) ...<Widget>[
                const SizedBox(height: 10),
                _Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '${plan.duplicates} ${plan.duplicates == 1 ? 'row has' : 'rows have'} '
                        'a medicine and batch already in stock or on an '
                        'earlier row',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SegmentedButton<DuplicatePolicy>(
                        showSelectedIcon: false,
                        style: _segmentStyle,
                        segments: const <ButtonSegment<DuplicatePolicy>>[
                          ButtonSegment<DuplicatePolicy>(
                            value: DuplicatePolicy.skip,
                            label: Text('Skip them'),
                          ),
                          ButtonSegment<DuplicatePolicy>(
                            value: DuplicatePolicy.addQuantity,
                            label: Text('Add quantity'),
                          ),
                        ],
                        selected: <DuplicatePolicy>{_duplicates},
                        onSelectionChanged: _busy
                            ? null
                            : (Set<DuplicatePolicy> s) {
                                setState(() => _duplicates = s.first);
                                _check();
                              },
                      ),
                    ],
                  ),
                ),
              ],
              if (plan.zeroQuantity > 0) ...<Widget>[
                const SizedBox(height: 10),
                _Panel(
                  padding: const EdgeInsets.fromLTRB(16, 6, 10, 6),
                  child: MergeSemantics(
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            'Skip rows with quantity 0 (${plan.zeroQuantity})',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        Switch(
                          value: _skipZero,
                          onChanged: _busy
                              ? null
                              : (bool v) {
                                  setState(() => _skipZero = v);
                                  _check();
                                },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              _filterChips(plan),
              const SizedBox(height: 10),
            ],
          ),
        ),
        if (rows.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'No rows here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            sliver: SliverList.separated(
              itemCount: rows.length,
              itemBuilder: (BuildContext context, int i) => _RowTile(row: rows[i]),
              separatorBuilder: (BuildContext context, int i) =>
                  const SizedBox(height: 8),
            ),
          ),
      ],
    );
  }

  Widget _filterChips(ImportPlan plan) {
    final List<(_Filter, String, int)> options = <(_Filter, String, int)>[
      (_Filter.all, 'All', plan.rows.length),
      (_Filter.importing, 'To import', plan.importable),
      (_Filter.skipped, 'Skipped', plan.skipped),
      (_Filter.warnings, 'Warnings', plan.withWarnings),
    ];
    return Wrap(
      spacing: 8,
      children: <Widget>[
        for (final (_Filter f, String label, int count) in options)
          _FilterChip(
            label: '$label · $count',
            selected: _filter == f,
            onTap: () => setState(() => _filter = f),
          ),
      ],
    );
  }

  // ---- saving and done ------------------------------------------------------

  Widget _savingStep() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              'Saving your stock…',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.pill),
              child: LinearProgressIndicator(
                minHeight: 8,
                value: _toSave == 0 ? null : _saved / _toSave,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '$_saved of $_toSave rows',
              style: const TextStyle(color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _doneStep() {
    final StockImportResult r = _result!;
    final int skipped = _plan?.skipped ?? 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      children: <Widget>[
        _Panel(
          child: Column(
            children: <Widget>[
              const Icon(Icons.check_circle_outline,
                  size: 56, color: AppColors.statusGreen),
              const SizedBox(height: 10),
              const Text(
                'Import complete',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Your stock is saved and syncs to your other devices.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 16),
              _ResultLine('Medicines added', r.medicinesAdded),
              _ResultLine('Batches added', r.batchesAdded),
              if (r.batchesToppedUp > 0)
                _ResultLine('Batches with stock added', r.batchesToppedUp),
              _ResultLine('Units added', r.unitsAdded),
              if (skipped > 0)
                _ResultLine('Rows skipped', skipped, color: AppColors.statusRed),
            ],
          ),
        ),
      ],
    );
  }
}

// ---- small pieces -------------------------------------------------------------

class _StepBar extends StatelessWidget {
  final int index;
  final String title;
  final String? fileName;

  const _StepBar({required this.index, required this.title, this.fileName});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 2, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              for (int i = 0; i < 4; i++)
                Expanded(
                  child: Container(
                    height: 4,
                    margin: EdgeInsets.only(right: i == 3 ? 0 : 6),
                    decoration: BoxDecoration(
                      color: i <= index ? AppColors.green : AppColors.border,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Semantics(
            header: true,
            child: Text(
              'Step ${index + 1} of 4 · $title',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.muted,
              ),
            ),
          ),
          if (fileName != null && fileName!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                fileName!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _Panel({required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
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
}

class _Point extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool last;

  const _Point(this.icon, this.text, {this.last = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 20, color: AppColors.green),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A tinted message with an optional action ("Upgrade").
class _Notice extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final String? action;
  final VoidCallback? onAction;

  const _Notice({
    required this.icon,
    required this.color,
    required this.text,
    this.action,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withValues(alpha: 0.10), AppColors.card),
        borderRadius: BorderRadius.circular(AppRadii.input),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
          ),
          if (action != null)
            TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    );
  }
}

/// A selectable row (the header row choice).
class _ChoiceTile extends StatelessWidget {
  final bool selected;
  final String leading;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _ChoiceTile({
    required this.selected,
    required this.leading,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadii.input),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadii.input),
            child: Container(
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadii.input),
                border: Border.all(
                  color: selected ? AppColors.green : AppColors.border,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    constraints: const BoxConstraints(minWidth: 30),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? AppColors.green : AppColors.canvas,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      leading,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: selected ? Colors.white : AppColors.muted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.muted),
                          ),
                      ],
                    ),
                  ),
                  if (selected) ...<Widget>[
                    const SizedBox(width: 8),
                    const Icon(Icons.check_circle,
                        size: 20, color: AppColors.green),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A row filter, styled like the Inventory status chips.
class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // A 40px chip inside a 48px touch target.
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: selected ? AppColors.green : AppColors.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: selected ? AppColors.green : AppColors.border),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppColors.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What the import will do, in numbers.
class _Summary extends StatelessWidget {
  final ImportPlan plan;
  const _Summary({required this.plan});

  @override
  Widget build(BuildContext context) {
    final List<String> parts = <String>[
      if (plan.newMedicines > 0)
        '${plan.newMedicines} new ${plan.newMedicines == 1 ? 'medicine' : 'medicines'}',
      if (plan.newBatches > 0)
        '${plan.newBatches} new ${plan.newBatches == 1 ? 'batch' : 'batches'} '
            'of known medicines',
      if (plan.addStock > 0)
        '${plan.addStock} stock ${plan.addStock == 1 ? 'addition' : 'additions'}',
    ];
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _Count(
                  count: plan.importable,
                  label: 'will be imported',
                  color: AppColors.statusGreen,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Count(
                  count: plan.skipped,
                  label: 'will be skipped',
                  color: plan.skipped > 0 ? AppColors.statusRed : AppColors.muted,
                ),
              ),
            ],
          ),
          if (parts.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              parts.join(' · '),
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  final int count;
  final String label;
  final Color color;

  const _Count({required this.count, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '$count',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        Text(
          '${count == 1 ? 'row' : 'rows'} $label',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.muted,
          ),
        ),
      ],
    );
  }
}

/// One checked row: what it is, what happens to it, and why.
class _RowTile extends StatelessWidget {
  final ImportRow row;
  const _RowTile({required this.row});

  @override
  Widget build(BuildContext context) {
    final StatusPill pill = switch (row.action) {
      RowAction.newMedicine => StatusPill.inStock('New medicine'),
      RowAction.newBatch => StatusPill.inStock('New batch'),
      RowAction.addStock => StatusPill.inStock('Add stock'),
      RowAction.skip => StatusPill.danger('Skipped'),
    };
    final List<String> facts = <String>[
      if (row.brand.isNotEmpty) row.brand,
      if (row.batchNo.isNotEmpty) 'Batch ${row.batchNo}',
      if (row.quantity != null)
        row.unit.isEmpty ? 'Qty ${row.quantity}' : '${row.quantity} ${row.unit}',
      if (row.expiry != null) 'Exp ${Fmt.date(row.expiry!)}',
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.input),
        border: Border.all(
          color: row.imported
              ? AppColors.border
              : AppColors.statusRed.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                'Row ${row.rowNumber}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.muted,
                ),
              ),
              const Spacer(),
              pill,
            ],
          ),
          const SizedBox(height: 4),
          Text(
            row.name.isEmpty ? '(no name)' : row.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          if (facts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                facts.join(' · '),
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
          if (row.imported && row.detail != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                row.detail!,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.greenMid,
                ),
              ),
            ),
          for (final String e in row.errors)
            _Message(icon: Icons.block, text: e, color: AppColors.statusRed),
          for (final String w in row.warnings)
            _Message(
                icon: Icons.warning_amber_rounded,
                text: w,
                color: AppColors.statusAmber),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _Message({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultLine extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _ResultLine(this.label, this.value, {this.color = AppColors.ink});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, color: AppColors.muted),
            ),
          ),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
