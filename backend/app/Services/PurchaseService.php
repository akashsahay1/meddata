<?php

namespace App\Services;

use App\Exceptions\ApiRefused;
use App\Models\Batch;
use App\Models\Party;
use App\Models\PartyPayment;
use App\Models\Product;
use App\Models\Purchase;
use App\Models\PurchaseItem;
use App\Models\Shop;
use App\Models\User;
use App\Support\GstMath;
use App\Support\StockLedger;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Supplier bills (purchase entries), online-only.
 *
 * Stock is counted once, on the server: a purchase creates the batch (or
 * adds to an existing batch of the same product, batch no. and expiry) and
 * records 'purchase' / 'purchase_free' stock movements, which every device
 * receives through the normal sync pull. Devices never add a movement of
 * their own for a purchase entry. A medicine new to the shop can come with
 * the line; it is created through the same path as a synced device insert
 * (validation, free-plan limit, catalog link).
 *
 * Everything runs in one transaction under the shop row lock; a refusal
 * writes nothing. A retry with the same purchase id returns that purchase,
 * and the same supplier invoice number can't be entered twice.
 */
class PurchaseService
{
    public function __construct(private readonly SyncService $sync) {}

    /** @return array{0: Purchase, 1: bool, 2: list<array{batch_id: string, qty_units: int}>} */
    public function create(Shop $shop, User $user, array $data): array
    {
        return DB::transaction(fn () => $this->createLocked($shop, $user, $data));
    }

    /**
     * Cancel a purchase: its stock goes back out ('purchase_cancel'
     * movements) and it leaves the supplier's ledger. Refused while it has
     * returns or payments, or when its stock has already been sold.
     *
     * @return array{0: Purchase, 1: list<array{batch_id: string, qty_units: int}>}
     */
    public function cancel(Shop $shop, User $user, Purchase $purchase, ?string $reason, ?string $deviceId): array
    {
        return DB::transaction(function () use ($shop, $user, $purchase, $reason, $deviceId) {
            $shop = Shop::whereKey($shop->id)->lockForUpdate()->firstOrFail();
            /** @var Purchase $purchase */
            $purchase = Purchase::with('items')->whereKey($purchase->id)->lockForUpdate()->firstOrFail();
            if ($purchase->isCancelled()) {
                return [$purchase, []];
            }
            if (DB::table('purchase_returns')->where('purchase_id', $purchase->id)->exists()) {
                throw new ApiRefused(422, 'has_returns', 'This purchase has a debit note, so it can’t be cancelled.');
            }
            if (PartyPayment::where('purchase_id', $purchase->id)->where('status', PartyPayment::STATUS_ACTIVE)->exists()) {
                throw new ApiRefused(422, 'has_payments', 'Cancel the payments made against this purchase first.');
            }

            $need = [];
            foreach ($purchase->items as $item) {
                $need[$item->batch_id] = ($need[$item->batch_id] ?? 0) + $item->stockUnits();
            }
            $batches = Batch::withTrashed()->whereIn('id', array_keys($need))->lockForUpdate()->get()->keyBy('id');
            $short = [];
            foreach ($need as $batchId => $units) {
                $left = (int) ($batches[$batchId]->qty_units ?? 0);
                if ($left < $units) {
                    $short[] = ['batch_id' => $batchId, 'batch_no' => $batches[$batchId]->batch_no ?? null,
                        'requested_units' => $units, 'available_units' => max(0, $left)];
                }
            }
            if ($short) {
                throw new ApiRefused(422, 'insufficient_stock',
                    'Some of this stock has already been sold, so the purchase can’t be cancelled. Use a purchase return for what is left.',
                    ['lines' => $short]);
            }

            foreach ($purchase->items as $item) {
                StockLedger::move($shop, $user, $deviceId, $item->batch_id, $item->product_id,
                    -$item->stockUnits(), 'purchase_cancel', 'purchase', $purchase->id);
            }
            $stock = StockLedger::refresh($shop, array_keys($need));
            $purchase->forceFill([
                'status' => Purchase::STATUS_CANCELLED,
                'cancelled_at' => now(),
                'cancel_reason' => $reason,
            ])->save();

            return [$purchase, $stock];
        });
    }

    // ---------------------------------------------------------------------

    private function createLocked(Shop $shop, User $user, array $data): array
    {
        $shop = Shop::whereKey($shop->id)->lockForUpdate()->firstOrFail();
        $deviceId = $data['device_id'] ?? null;

        $existing = Purchase::with('items')->find($data['id']);
        if ($existing) {
            if ((int) $existing->shop_id !== (int) $shop->id) {
                throw new ApiRefused(422, 'id_conflict', 'This purchase id is already in use.');
            }

            return [$existing, false, []];
        }

        $party = Party::where('shop_id', $shop->id)->find($data['party_id']);
        if (! $party || ! $party->isSupplier()) {
            throw new ApiRefused(422, 'party_not_supplier', 'Choose one of your suppliers for this purchase.');
        }

        $invoiceNo = trim($data['supplier_invoice_no']);
        $duplicate = Purchase::where('shop_id', $shop->id)->where('party_id', $party->id)
            ->where('status', Purchase::STATUS_FINAL)
            ->whereRaw('LOWER(supplier_invoice_no) = ?', [mb_strtolower($invoiceNo)])
            ->first();
        if ($duplicate) {
            throw new ApiRefused(422, 'duplicate_invoice',
                "Invoice {$invoiceNo} from {$party->name} is already entered.", ['purchase_id' => $duplicate->id]);
        }

        $supplierState = $party->state_code ?: ($party->gstin ? substr($party->gstin, 0, 2) : null);
        $interState = $shop->state_code !== null && $supplierState !== null && $supplierState !== $shop->state_code;

        $items = [];
        $calcs = [];
        $batchIds = [];
        $movements = [];
        foreach (array_values($data['lines']) as $i => $line) {
            $product = $this->product($shop, $user, $deviceId, $line, $i);
            $upp = max(1, (int) ($line['units_per_pack'] ?? 1));
            $qty = (int) ($line['qty'] ?? 0);
            $free = (int) ($line['free_qty'] ?? 0);
            $rate = (int) $line['rate_paise'];
            $discountBp = (int) ($line['discount_bp'] ?? 0);
            $gstRate = (int) ($line['gst_rate_bp'] ?? $product->gst_rate_bp ?? $shop->default_gst_rate_bp);
            $hsn = ($line['hsn'] ?? null) ?: $product->hsn;

            [$batch, $isNew] = $this->batch($shop, $user, $deviceId, $product, $line, $i, $upp, $rate, $discountBp);
            $this->fillProductTax($shop, $product, $line);

            $calc = GstMath::purchaseLine($rate, $qty, $discountBp, $gstRate, $interState);
            $calcs[] = $calc;
            $items[] = [
                'line_no' => $i + 1,
                'product_id' => $product->id,
                'batch_id' => $batch->id,
                'name' => $product->name,
                'hsn' => $hsn,
                'batch_no' => $batch->batch_no,
                'expiry_date' => $batch->expiry_date?->format('Y-m-d'),
                'mfg_date' => $batch->mfg_date?->format('Y-m-d'),
                'qty' => $qty,
                'free_qty' => $free,
                'units_per_pack' => $upp,
                'rate_paise' => $rate,
                'mrp_paise' => (int) ($line['mrp_paise'] ?? 0),
                'discount_bp' => $discountBp,
                'gst_rate_bp' => $gstRate,
                'new_batch' => $isNew,
            ] + array_intersect_key($calc, array_flip(['discount_paise', 'taxable_paise', 'cgst_paise', 'sgst_paise', 'igst_paise', 'total_paise']));
            $batchIds[] = $batch->id;
            if ($qty > 0) {
                $movements[] = [$batch->id, $product->id, $qty * $upp, 'purchase'];
            }
            if ($free > 0) {
                $movements[] = [$batch->id, $product->id, $free * $upp, 'purchase_free'];
            }
        }
        $totals = GstMath::totals($calcs);

        $purchase = new Purchase;
        $purchase->id = $data['id'];
        $purchase->forceFill([
            'shop_id' => $shop->id,
            'party_id' => $party->id,
            'user_id' => $user->id,
            'device_id' => $deviceId,
            'invoice_scan_id' => $data['invoice_scan_id'] ?? null,
            'supplier_name' => $party->name,
            'supplier_gstin' => $party->gstin,
            'supplier_state_code' => $supplierState,
            'supplier_invoice_no' => $invoiceNo,
            'invoice_date' => $data['invoice_date'],
            'entry_date' => now(BillingService::TIMEZONE)->toDateString(),
            'is_inter_state' => $interState,
            'notes' => $data['notes'] ?? null,
            'status' => Purchase::STATUS_FINAL,
        ] + $totals)->save();

        foreach ($items as $item) {
            PurchaseItem::create(['purchase_id' => $purchase->id] + $item);
        }
        foreach ($movements as [$batchId, $productId, $units, $reason]) {
            StockLedger::move($shop, $user, $deviceId, $batchId, $productId, $units, $reason, 'purchase', $purchase->id);
        }
        $stock = StockLedger::refresh($shop, $batchIds);

        return [$purchase->load('items'), true, $stock];
    }

    /** The line's product: the shop's, or created from `line.product` (a medicine new to the shop). */
    private function product(Shop $shop, User $user, ?string $deviceId, array $line, int $i): Product
    {
        $id = strtolower($line['product_id']);
        $product = Product::withTrashed()->find($id);
        if ($product && (int) $product->shop_id !== (int) $shop->id) {
            throw new ApiRefused(422, 'id_conflict', 'A medicine id on this purchase is already in use.', ['index' => $i]);
        }
        if ($product && $product->trashed()) {
            throw new ApiRefused(422, 'product_deleted', "{$product->name} was deleted. Add it again to buy it.", ['index' => $i]);
        }
        if ($product) {
            return $product;
        }
        if (empty($line['product']['name'])) {
            throw new ApiRefused(422, 'product_not_found', 'A medicine on this purchase is not in your inventory.', ['index' => $i]);
        }

        $fields = array_intersect_key($line['product'], array_flip(Product::clientFields()));
        $fields['hsn'] ??= $line['hsn'] ?? null;
        $fields['gst_rate_bp'] ??= $line['gst_rate_bp'] ?? null;
        $result = $this->sync->push($shop, $user, $deviceId ?? 'server', [[
            'mutation_id' => (string) Str::uuid(),
            'table' => 'products',
            'op' => 'upsert',
            'id' => $id,
            'data' => array_filter($fields, fn ($v) => $v !== null),
        ]])[0];
        if (($result['status'] ?? null) !== 'ok') {
            $reason = $result['reason'] ?? 'invalid';
            throw new ApiRefused(422, $reason === 'plan_limit' ? 'plan_limit' : 'product_rejected',
                $reason === 'plan_limit'
                    ? 'The free plan’s medicine limit is reached. Upgrade to add new medicines.'
                    : 'A new medicine on this purchase could not be added.',
                ['index' => $i, 'errors' => $result['errors'] ?? null]);
        }

        return Product::findOrFail($id);
    }

    /**
     * The batch the line's stock goes into: the given batch, else the
     * product's batch with the same batch no. and expiry, else a new one
     * (prices per stock unit from the per-pack rates).
     *
     * @return array{0: Batch, 1: bool}
     */
    private function batch(Shop $shop, User $user, ?string $deviceId, Product $product, array $line, int $i,
        int $upp, int $rate, int $discountBp): array
    {
        $batchNo = trim((string) ($line['batch_no'] ?? '')) ?: null;
        $id = isset($line['batch_id']) ? strtolower($line['batch_id']) : null;

        $batch = $id ? Batch::withTrashed()->lockForUpdate()->find($id) : null;
        if ($batch) {
            if ((int) $batch->shop_id !== (int) $shop->id || $batch->product_id !== $product->id) {
                throw new ApiRefused(422, 'batch_mismatch', 'A batch on this purchase belongs to another medicine.', ['index' => $i]);
            }
            if ($batch->trashed()) {
                throw new ApiRefused(422, 'batch_deleted', "Batch {$batch->batch_no} of {$product->name} was deleted.", ['index' => $i]);
            }

            return [$batch, false];
        }
        if (! $id && $batchNo !== null) {
            $batch = Batch::where('shop_id', $shop->id)->where('product_id', $product->id)
                ->whereRaw('LOWER(batch_no) = ?', [mb_strtolower($batchNo)])
                ->whereDate('expiry_date', $line['expiry_date'])
                ->lockForUpdate()
                ->first();
            if ($batch) {
                return [$batch, false];
            }
        }

        $net = $rate - GstMath::roundDiv($rate * $discountBp, 10000);
        // The bill's prices are per printed pack of $upp units; the batch
        // keeps them per the product's own price pack (its strip, or one
        // unit) - the same number when the two packs agree.
        $pack = $product->pricePack();
        $batch = new Batch;
        $batch->id = $id ?? (string) Str::uuid();
        $batch->fill([
            'product_id' => $product->id,
            'batch_no' => $batchNo,
            'expiry_date' => $line['expiry_date'],
            'mfg_date' => $line['mfg_date'] ?? null,
            'mrp_paise' => GstMath::roundDiv((int) ($line['mrp_paise'] ?? 0) * $pack, $upp),
            'purchase_rate_paise' => GstMath::roundDiv($net * $pack, $upp),
        ]);
        $batch->shop_id = $shop->id;
        $batch->created_by = $user->id;
        $batch->device_id = $deviceId;
        $batch->version = $shop->nextVersion();
        $batch->edit_version = $batch->version;
        $batch->save();

        return [$batch, true];
    }

    /** A product without HSN / GST rate takes them from the supplier's bill. */
    private function fillProductTax(Shop $shop, Product $product, array $line): void
    {
        $changes = [];
        if ($product->hsn === null && ! empty($line['hsn'])) {
            $changes['hsn'] = $line['hsn'];
        }
        if ($product->gst_rate_bp === null && isset($line['gst_rate_bp'])) {
            $changes['gst_rate_bp'] = (int) $line['gst_rate_bp'];
        }
        if ($changes) {
            $product->fill($changes);
            $product->version = $shop->nextVersion();
            $product->edit_version = $product->version;
            $product->save();
        }
    }
}
