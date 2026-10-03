/// Audit record for a change in stock quantity.
enum StockReason { add, sell, adjust, restock }

class StockMovement {
  final String id;
  final String medicineId;
  final int change; // positive or negative
  final StockReason reason;
  final DateTime createdAt;

  const StockMovement({
    required this.id,
    required this.medicineId,
    required this.change,
    required this.reason,
    required this.createdAt,
  });

  /// Maps both the old local reasons and the synced ledger's reasons onto
  /// the labels the UI shows.
  static StockReason reasonFrom(String? r) {
    switch (r) {
      case 'add':
      case 'opening':
      case 'purchase':
      case 'purchase_free':
        return StockReason.add;
      case 'restock':
      case 'sale_return':
        return StockReason.restock;
      case 'sell':
      case 'sale':
        return StockReason.sell;
      default:
        return StockReason.adjust;
    }
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'medicine_id': medicineId,
        'change': change,
        'reason': reason.name,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory StockMovement.fromMap(Map<String, Object?> map) => StockMovement(
        id: map['id'] as String,
        medicineId: map['medicine_id'] as String,
        change: (map['change'] as int?) ?? 0,
        reason: reasonFrom(map['reason'] as String?),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            (map['created_at'] as int?) ?? 0),
      );
}
