import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/models/accounting.dart';
import '../data/models/bill.dart';
import '../domain/fefo.dart';
import '../domain/gst.dart';
import '../services/billing_api.dart';

/// One medicine on the bill being made. Its quantity is split over the
/// product's batches FEFO (or starting from the batch the user picked).
class CartItem {
  CartItem({
    required this.productId,
    required this.name,
    required this.unit,
    this.packSize = 1,
    required this.qty,
    this.discountBp = 0,
  });

  final String productId;
  final String name;
  final String unit;

  /// Pieces per pack (tablets per strip); 1 when not set.
  final int packSize;

  /// Units (pieces) of the product on the bill.
  int qty;
  int discountBp;

  /// The batch the user chose to sell from first (null = earliest expiry).
  String? pinnedBatchId;
}

/// One line of the bill as it is sent: units of one batch.
class CartLine {
  const CartLine(this.item, this.batch, this.qty, this.gstRateBp, this.gst);

  final CartItem item;
  final SaleBatch batch;
  final int qty;
  final int gstRateBp;
  final GstLine gst;
}

enum AddOutcome { added, outOfStock, onlyExpired, notFound }

/// The bill being made at the counter. Prices are what the screen showed
/// when the medicine was added: they only change when the server says a
/// price is stale and the user accepts the new one, so a bill never goes
/// through at a price nobody saw. The totals preview uses the same maths as
/// the server ([GstMath]); the server's bill is the one that counts.
class BillCart extends ChangeNotifier {
  BillCart({required this.loadBatches, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  /// Reads a product's batches (from the device's inventory).
  final Future<List<SaleBatch>> Function(String productId) loadBatches;
  final DateTime Function() _clock;
  static const Uuid _uuid = Uuid();

  /// Idempotency key: the same id is sent until the server has answered
  /// (a retry after a lost response returns the bill instead of a second
  /// one). A fresh id only after a bill is made.
  String _billId = _uuid.v4();
  String get billId => _billId;

  ShopProfile? _shop;
  ShopProfile? get shop => _shop;
  set shop(ShopProfile? s) {
    _shop = s;
    notifyListeners();
  }

  final List<CartItem> items = <CartItem>[];
  final Map<String, List<SaleBatch>> _batches = <String, List<SaleBatch>>{};

  /// The customer's account (needed for a credit bill). Choosing one fills
  /// in the customer fields; they can still be changed for this bill.
  Party? party;

  String customerName = '';
  String customerPhone = '';
  String customerGstin = '';
  String customerAddress = '';

  /// Place of supply chosen for the customer (null = from GSTIN / shop).
  String? customerStateCode;
  PaymentMode paymentMode = PaymentMode.cash;

  DateTime get today => _clock();
  bool get isEmpty => items.isEmpty;

  /// Change customer/payment fields and refresh listeners.
  void update(VoidCallback change) {
    change();
    notifyListeners();
  }

  /// Choose (or clear, with null) the customer's account.
  void setParty(Party? p) {
    party = p;
    if (p != null) {
      customerName = p.name;
      customerPhone = p.phone ?? '';
      customerGstin = p.gstin ?? '';
      customerAddress = p.address ?? '';
      customerStateCode = p.gstin == null ? p.stateCode : null;
    }
    notifyListeners();
  }

  // ---- items ----------------------------------------------------------------

  /// Add [qty] units of a product (more of it if it's already on the bill).
  Future<AddOutcome> addProduct(String productId, {int qty = 1}) async {
    for (final CartItem i in items) {
      if (i.productId == productId) {
        setQty(i, i.qty + qty);
        return AddOutcome.added;
      }
    }
    final List<SaleBatch> batches = await loadBatches(productId);
    if (batches.isEmpty) return AddOutcome.notFound;
    final List<SaleBatch> sellable = Fefo.sellable(batches, today);
    if (sellable.isEmpty) {
      return batches.any((SaleBatch b) => b.qty > 0)
          ? AddOutcome.onlyExpired
          : AddOutcome.outOfStock;
    }
    _batches[productId] = List<SaleBatch>.of(batches);
    final SaleBatch first = sellable.first;
    items.add(CartItem(
      productId: productId,
      name: first.productName,
      unit: first.unit,
      packSize: first.packSize,
      qty: qty,
      discountBp: first.discountBp,
    ));
    notifyListeners();
    return AddOutcome.added;
  }

  void setQty(CartItem item, int qty) {
    item.qty = qty < 1 ? 1 : qty;
    notifyListeners();
  }

  void setDiscount(CartItem item, int bp) {
    item.discountBp = bp.clamp(0, 10000);
    notifyListeners();
  }

  void pinBatch(CartItem item, String? batchId) {
    item.pinnedBatchId = batchId;
    notifyListeners();
  }

  void remove(CartItem item) {
    items.remove(item);
    _batches.remove(item.productId);
    notifyListeners();
  }

  /// All of the product's batches (incl. expired / empty), earliest first.
  List<SaleBatch> batchesOf(CartItem item) =>
      List<SaleBatch>.of(_batches[item.productId] ?? const <SaleBatch>[])
        ..sort((SaleBatch a, SaleBatch b) => a.expiryDate.compareTo(b.expiryDate));

  /// Units that can be sold from unexpired batches.
  int available(CartItem item) => Fefo.sellable(batchesOf(item), today)
      .fold(0, (int sum, SaleBatch b) => sum + b.qty);

  FefoAllocation allocation(CartItem item) => Fefo.allocate(
      batchesOf(item), item.qty,
      today: today, pinnedBatchId: item.pinnedBatchId);

  bool get hasShortfall => items.any((CartItem i) => !allocation(i).isComplete);

  // ---- tax ------------------------------------------------------------------

  int gstRateOf(SaleBatch b) => b.gstRateBp ?? _shop?.defaultGstRateBp ?? 500;

  /// Where the supply is taxed: the customer's state (chosen, or from the
  /// GSTIN), else the shop's own state.
  String? get placeOfSupply {
    if (customerStateCode != null) return customerStateCode;
    final String g = Gstin.normalize(customerGstin);
    if (Gstin.isValid(g)) return g.substring(0, 2);
    return _shop?.stateCode;
  }

  bool get isInterState {
    final String? home = _shop?.stateCode;
    final String? pos = placeOfSupply;
    return home != null && pos != null && pos != home;
  }

  List<CartLine> get lines {
    final bool inter = isInterState;
    return <CartLine>[
      for (final CartItem item in items)
        for (final BatchTake take in allocation(item).takes)
          CartLine(
            item,
            take.batch,
            take.qty,
            gstRateOf(take.batch),
            GstMath.line(
              mrpPaise: take.batch.mrpPaise,
              qty: take.qty,
              discountBp: item.discountBp,
              gstRateBp: gstRateOf(take.batch),
              interState: inter,
              packSize: take.batch.pricePack,
            ),
          ),
    ];
  }

  GstTotals get totals => GstMath.totals(lines.map((CartLine l) => l.gst));

  /// What stops the bill from being sent, or null if it can go.
  String? problem() {
    if (items.isEmpty) return 'Add at least one medicine.';
    for (final CartItem i in items) {
      if (!allocation(i).isComplete) {
        return 'Only ${available(i)} ${i.unit} of ${i.name} can be sold.';
      }
    }
    final String gstin = Gstin.normalize(customerGstin);
    if (gstin.isNotEmpty && !Gstin.isValid(gstin)) {
      return "The customer's GSTIN is not valid.";
    }
    final String phone = customerPhone.trim();
    if (phone.isNotEmpty && !RegExp(r'^[0-9+\-\s()]{6,20}$').hasMatch(phone)) {
      return "The customer's phone number is not valid.";
    }
    if (paymentMode == PaymentMode.credit && party == null) {
      return "Choose the customer's account for a credit bill.";
    }
    return null;
  }

  /// POST /bills body.
  Map<String, Object?> requestBody({String? deviceId}) {
    String? opt(String v) => v.trim().isEmpty ? null : v.trim();
    return <String, Object?>{
      'id': _billId,
      'device_id': deviceId,
      'payment_mode': paymentMode.name,
      'party_id': party?.id,
      'customer_name': opt(customerName),
      'customer_phone': opt(customerPhone),
      'customer_gstin': opt(Gstin.normalize(customerGstin)),
      'customer_state_code': customerStateCode,
      'customer_address': opt(customerAddress),
      'lines': <Map<String, Object?>>[
        for (final CartLine l in lines)
          <String, Object?>{
            'batch_id': l.batch.id,
            'qty_units': l.qty,
            'mrp_paise': l.batch.mrpPaise,
            'batch_version': l.batch.version,
            'discount_bp': l.item.discountBp,
          },
      ],
    };
  }

  // ---- what the server said ----------------------------------------------------

  /// The user accepted the server's current prices (after a 409).
  void acceptPrices(List<StalePrice> stale) {
    for (final StalePrice s in stale) {
      _updateBatch(s.batchId, (SaleBatch b) => b.copyWith(mrpPaise: s.mrpPaise, version: s.version));
    }
    notifyListeners();
  }

  /// Stock is lower than this device thought (422): use what's left; the
  /// allocation spills over to the next batch where it can.
  void applyStock(List<StockShort> short) {
    for (final StockShort s in short) {
      _updateBatch(s.batchId, (SaleBatch b) => b.copyWith(qty: s.available));
    }
    notifyListeners();
  }

  /// Batches that can't be sold any more (expired, deleted).
  void dropBatches(Iterable<String> batchIds) {
    final Set<String> ids = batchIds.toSet();
    for (final List<SaleBatch> list in _batches.values) {
      list.removeWhere((SaleBatch b) => ids.contains(b.id));
    }
    for (final CartItem i in items) {
      if (ids.contains(i.pinnedBatchId)) i.pinnedBatchId = null;
    }
    notifyListeners();
  }

  /// Re-read batches this device hadn't synced yet (version 0) once the
  /// sync has given them their server version.
  Future<void> refreshUnsynced() async {
    for (final String productId in _batches.keys.toList()) {
      final List<SaleBatch> mine = _batches[productId]!;
      if (!mine.any((SaleBatch b) => b.version == 0)) continue;
      final Map<String, SaleBatch> fresh = <String, SaleBatch>{
        for (final SaleBatch b in await loadBatches(productId)) b.id: b,
      };
      _batches[productId] = <SaleBatch>[
        for (final SaleBatch b in mine)
          if (b.version == 0 && fresh[b.id] != null) fresh[b.id]! else b,
      ];
    }
    notifyListeners();
  }

  bool get hasUnsyncedBatches =>
      lines.any((CartLine l) => l.batch.version == 0);

  /// Start a new bill.
  void reset() {
    items.clear();
    _batches.clear();
    customerName = customerPhone = customerGstin = customerAddress = '';
    party = null;
    customerStateCode = null;
    paymentMode = PaymentMode.cash;
    _billId = _uuid.v4();
    notifyListeners();
  }

  void _updateBatch(String batchId, SaleBatch Function(SaleBatch) change) {
    for (final List<SaleBatch> list in _batches.values) {
      for (int i = 0; i < list.length; i++) {
        if (list[i].id == batchId) list[i] = change(list[i]);
      }
    }
  }
}
