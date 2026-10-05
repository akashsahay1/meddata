import 'medicine.dart';

/// One row of a spreadsheet import, ready to save with
/// `MedicineRepository.importStock`.
class StockImportRow {
  /// The row as a new batch (fresh id) carrying its product's details.
  final Medicine medicine;

  /// Existing product the batch joins. Null: a new product, created once for
  /// all rows with the same [productKey] from the first such row.
  final String? productId;

  /// Groups the rows of one product within the import.
  final String productKey;

  /// Add [Medicine.quantity] to this existing batch instead of creating a
  /// new batch (the same medicine and batch was already in stock).
  final String? addToBatchId;

  const StockImportRow({
    required this.medicine,
    required this.productKey,
    this.productId,
    this.addToBatchId,
  });
}

/// What an import saved.
class StockImportResult {
  final int medicinesAdded;
  final int batchesAdded;
  final int batchesToppedUp;
  final int unitsAdded;

  const StockImportResult({
    this.medicinesAdded = 0,
    this.batchesAdded = 0,
    this.batchesToppedUp = 0,
    this.unitsAdded = 0,
  });
}
