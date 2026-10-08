<?php

namespace App\Services;

use App\Exceptions\BillRefused;
use App\Models\Batch;
use App\Models\Bill;
use App\Models\BillItem;
use App\Models\Party;
use App\Models\PartyPayment;
use App\Models\Product;
use App\Models\SaleReturn;
use App\Models\Shop;
use App\Models\StockMovement;
use App\Models\User;
use App\Support\GstMath;
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Online GST billing. A bill is created in one transaction that holds the
 * shop row lock (the same lock every synced change takes for its version),
 * so prices, stock and the invoice counter can't move underneath it:
 *
 * 1. Same bill id as an earlier request -> that bill again (safe retries).
 * 2. Every batch must be this shop's, not deleted and not expired.
 * 3. Price check: the MRP and batch edit_version the device showed must be
 *    the current ones, else 409 with the current price per line.
 * 4. Stock check: enough units in each batch, else 422 with what's left.
 * 5. Tax from the server's product GST rates (GstMath), the next number in
 *    the shop's financial-year series, and a 'sale' stock movement per line,
 *    which devices receive through the normal sync pull.
 *
 * Any refusal throws before anything is written, so no number is used up.
 */
class BillingService
{
    /** Invoice dates and financial years are Indian time, whatever the server's timezone. */
    public const TIMEZONE = 'Asia/Kolkata';

    /**
     * Create a bill from validated POST /bills input. Returns the bill,
     * whether it was created now (false = a retry got the earlier one),
     * and the new stock of the batches sold.
     *
     * @return array{0: Bill, 1: bool, 2: list<array{batch_id: string, qty_units: int}>}
     */
    public function create(Shop $shop, User $user, array $data): array
    {
        try {
            return DB::transaction(fn () => $this->createLocked($shop, $user, $data));
        } catch (UniqueConstraintViolationException $e) {
            // Belt and braces for the retry race: the shop lock should make
            // the id check above it, but never create a second bill.
            $existing = Bill::with('items')->where('shop_id', $shop->id)->find($data['id']);
            if ($existing) {
                return [$existing, false, []];
            }
            throw $e;
        }
    }

    /**
     * Cancel a bill: its stock goes back (a 'sale_cancel' movement per line)
     * and its number stays used. Cancelling again changes nothing.
     *
     * @return array{0: Bill, 1: list<array{batch_id: string, qty_units: int}>}
     */
    public function cancel(Shop $shop, User $user, Bill $bill, ?string $reason, ?string $deviceId): array
    {
        return DB::transaction(function () use ($shop, $user, $bill, $reason, $deviceId) {
            $shop = Shop::whereKey($shop->id)->lockForUpdate()->firstOrFail();
            /** @var Bill $bill */
            $bill = Bill::with('items')->whereKey($bill->id)->lockForUpdate()->firstOrFail();
            if ($bill->isCancelled()) {
                return [$bill, []];
            }
            // A credit note or a payment refers to this bill; undo those first.
            if (SaleReturn::where('bill_id', $bill->id)->exists()) {
                throw new BillRefused(422, [
                    'message' => 'This bill has a sale return (credit note), so it can’t be cancelled.',
                    'error' => 'has_returns',
                ]);
            }
            if (PartyPayment::where('bill_id', $bill->id)->where('status', PartyPayment::STATUS_ACTIVE)->exists()) {
                throw new BillRefused(422, [
                    'message' => 'Cancel the payments received against this bill first.',
                    'error' => 'has_payments',
                ]);
            }

            foreach ($bill->items as $item) {
                $this->move($shop, $user, $deviceId, $item->batch_id, $item->product_id,
                    (int) $item->qty_units, 'sale_cancel', $bill->id);
            }
            $stock = $this->refreshBatches($shop, $bill->items->pluck('batch_id')->unique()->values());

            $bill->forceFill([
                'status' => Bill::STATUS_CANCELLED,
                'cancelled_at' => now(),
                'cancelled_by' => $user->id,
                'cancel_reason' => $reason,
            ])->save();

            return [$bill, $stock];
        });
    }

    // ---------------------------------------------------------------------

    private function createLocked(Shop $shop, User $user, array $data): array
    {
        $shop = Shop::whereKey($shop->id)->lockForUpdate()->firstOrFail();

        $existing = Bill::with('items')->find($data['id']);
        if ($existing) {
            if ((int) $existing->shop_id !== (int) $shop->id) {
                throw new BillRefused(422, [
                    'message' => 'This bill id is already in use.',
                    'error' => 'id_conflict',
                ]);
            }

            return [$existing, false, []];
        }

        $lines = array_values($data['lines']);
        $batches = Batch::withTrashed()
            ->where('shop_id', $shop->id)
            ->whereIn('id', array_unique(array_column($lines, 'batch_id')))
            ->lockForUpdate()
            ->get()
            ->keyBy('id');
        $products = Product::withTrashed()
            ->where('shop_id', $shop->id)
            ->whereIn('id', $batches->pluck('product_id')->unique()->values())
            ->get()
            ->keyBy('id');

        $this->checkAvailable($lines, $batches, $products);
        $this->checkPrices($lines, $batches, $products);
        $this->checkStock($lines, $batches, $products);

        // A chosen customer account fills in what the bill doesn't say.
        $party = $this->party($shop, $data['party_id'] ?? null);
        if ($party) {
            foreach (['name' => 'customer_name', 'phone' => 'customer_phone', 'gstin' => 'customer_gstin',
                'state_code' => 'customer_state_code', 'address' => 'customer_address'] as $from => $to) {
                if (($data[$to] ?? null) === null && $party->{$from} !== null) {
                    $data[$to] = $party->{$from};
                }
            }
        }

        $customerGstin = $data['customer_gstin'] ?? null;
        $placeOfSupply = ($data['customer_state_code'] ?? null)
            ?: ($customerGstin ? substr($customerGstin, 0, 2) : null)
            ?: $shop->state_code;
        $interState = $shop->state_code !== null && $placeOfSupply !== null
            && $placeOfSupply !== $shop->state_code;

        $items = [];
        $calcs = [];
        foreach ($lines as $i => $line) {
            $batch = $batches[$line['batch_id']];
            $product = $products[$batch->product_id];
            $gstRate = (int) ($product->gst_rate_bp ?? $shop->default_gst_rate_bp);
            $discountBp = (int) ($line['discount_bp'] ?? 0);
            $calc = GstMath::line((int) $batch->mrp_paise, (int) $line['qty_units'], $discountBp, $gstRate, $interState);
            $items[] = [
                'line_no' => $i + 1,
                'product_id' => $product->id,
                'batch_id' => $batch->id,
                'name' => $product->name,
                'hsn' => $product->hsn,
                'unit' => $product->unit,
                'pack_size' => max(1, (int) $product->pack_size),
                'batch_no' => $batch->batch_no,
                'expiry_date' => $batch->expiry_date?->format('Y-m-d'),
                'qty_units' => (int) $line['qty_units'],
                'mrp_paise' => (int) $batch->mrp_paise,
                'discount_bp' => $discountBp,
                'gst_rate_bp' => $gstRate,
            ] + array_diff_key($calc, ['gross_paise' => true]);
            $calcs[] = $calc;
        }
        $totals = GstMath::totals($calcs);

        $now = now(self::TIMEZONE);
        $fy = GstMath::financialYear($now);
        $seq = $this->nextInvoiceSeq($shop, $fy);

        $bill = new Bill;
        $bill->id = $data['id'];
        $bill->forceFill([
            'shop_id' => $shop->id,
            'user_id' => $user->id,
            'device_id' => $data['device_id'] ?? null,
            'invoice_no' => sprintf('%s/%s/%06d', $shop->invoicePrefix(), $fy, $seq),
            'fy' => $fy,
            'seq' => $seq,
            'bill_date' => $now->toDateString(),
            'party_id' => $party?->id,
            'customer_name' => $data['customer_name'] ?? null,
            'customer_phone' => $data['customer_phone'] ?? null,
            'customer_gstin' => $customerGstin,
            'customer_state_code' => $data['customer_state_code'] ?? ($customerGstin ? substr($customerGstin, 0, 2) : null),
            'customer_address' => $data['customer_address'] ?? null,
            'place_of_supply' => $placeOfSupply,
            'is_inter_state' => $interState,
            'seller' => $shop->invoiceDetails(),
            'payment_mode' => $data['payment_mode'],
            'status' => Bill::STATUS_FINAL,
        ] + $totals)->save();

        foreach ($items as $item) {
            BillItem::create(['bill_id' => $bill->id] + $item);
            $this->move($shop, $user, $data['device_id'] ?? null, $item['batch_id'], $item['product_id'],
                -$item['qty_units'], 'sale', $bill->id);
        }
        $stock = $this->refreshBatches($shop, $batches->keys());

        return [$bill->load('items'), true, $stock];
    }

    /** The bill's customer account: the shop's, not deleted, a customer. */
    private function party(Shop $shop, ?string $id): ?Party
    {
        if ($id === null) {
            return null;
        }
        $party = Party::where('shop_id', $shop->id)->find(strtolower($id));
        if (! $party || ! $party->isCustomer()) {
            throw new BillRefused(422, [
                'message' => 'The customer account was not found. Choose the customer again.',
                'error' => 'party_not_found',
            ]);
        }

        return $party;
    }

    /** Next number in the shop's series for this financial year (caller holds the shop lock). */
    private function nextInvoiceSeq(Shop $shop, string $fy): int
    {
        $row = DB::table('invoice_series')
            ->where('shop_id', $shop->id)
            ->where('fy', $fy)
            ->lockForUpdate()
            ->first();
        $seq = ($row ? (int) $row->last_seq : 0) + 1;

        if ($row) {
            DB::table('invoice_series')->where('id', $row->id)
                ->update(['last_seq' => $seq, 'updated_at' => now()]);
        } else {
            DB::table('invoice_series')->insert([
                'shop_id' => $shop->id,
                'fy' => $fy,
                'last_seq' => $seq,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        }

        return $seq;
    }

    private function move(Shop $shop, User $user, ?string $deviceId, string $batchId, string $productId,
        int $delta, string $reason, string $billId): void
    {
        $movement = new StockMovement;
        $movement->id = (string) Str::uuid();
        $movement->fill([
            'shop_id' => $shop->id,
            'batch_id' => $batchId,
            'product_id' => $productId,
            'delta_units' => $delta,
            'reason' => $reason,
            'ref_type' => 'bill',
            'ref_id' => $billId,
            'occurred_at' => now(),
            'created_by' => $user->id,
            'device_id' => $deviceId,
        ]);
        $movement->version = $shop->nextVersion();
        $movement->save();
    }

    /**
     * Recompute each batch's qty from its movements and give it a new
     * version so devices pull the new stock.
     *
     * @return list<array{batch_id: string, qty_units: int}>
     */
    private function refreshBatches(Shop $shop, Collection $batchIds): array
    {
        $out = [];
        foreach (Batch::withTrashed()->whereIn('id', $batchIds->all())->get() as $batch) {
            $batch->qty_units = (int) StockMovement::where('batch_id', $batch->id)->sum('delta_units');
            $batch->version = $shop->nextVersion();
            $batch->save();
            $out[] = ['batch_id' => $batch->id, 'qty_units' => (int) $batch->qty_units];
        }

        return $out;
    }

    // ---- checks (throw BillRefused) --------------------------------------

    private function checkAvailable(array $lines, Collection $batches, Collection $products): void
    {
        $today = now(self::TIMEZONE)->toDateString();
        $bad = [];
        foreach ($lines as $i => $line) {
            $batch = $batches[$line['batch_id']] ?? null;
            $product = $batch ? ($products[$batch->product_id] ?? null) : null;
            $reason = match (true) {
                ! $batch || ! $product => 'not_found',
                $batch->trashed() || $product->trashed() => 'deleted',
                $batch->expiry_date !== null && $batch->expiry_date->format('Y-m-d') < $today => 'expired',
                default => null,
            };
            if ($reason) {
                $bad[] = $this->lineRef($i, $line, $batch, $product) + [
                    'reason' => $reason,
                    'expiry_date' => $batch?->expiry_date?->format('Y-m-d'),
                ];
            }
        }
        if ($bad) {
            throw new BillRefused(422, [
                'message' => 'Some items can no longer be sold.',
                'error' => 'batch_unavailable',
                'lines' => $bad,
            ]);
        }
    }

    private function checkPrices(array $lines, Collection $batches, Collection $products): void
    {
        $stale = [];
        foreach ($lines as $i => $line) {
            $batch = $batches[$line['batch_id']];
            $priceChanged = (int) $batch->mrp_paise !== (int) $line['mrp_paise'];
            if ($priceChanged || (int) $batch->edit_version !== (int) $line['batch_version']) {
                $stale[] = $this->lineRef($i, $line, $batch, $products[$batch->product_id]) + [
                    'sent_mrp_paise' => (int) $line['mrp_paise'],
                    'mrp_paise' => (int) $batch->mrp_paise,
                    'batch_version' => (int) $batch->edit_version,
                    'price_changed' => $priceChanged,
                    'expiry_date' => $batch->expiry_date?->format('Y-m-d'),
                ];
            }
        }
        if ($stale) {
            throw new BillRefused(409, [
                'message' => 'Prices changed since this bill was started.',
                'error' => 'price_changed',
                'lines' => $stale,
            ]);
        }
    }

    private function checkStock(array $lines, Collection $batches, Collection $products): void
    {
        $wanted = [];
        foreach ($lines as $line) {
            $wanted[$line['batch_id']] = ($wanted[$line['batch_id']] ?? 0) + (int) $line['qty_units'];
        }
        $short = [];
        foreach ($lines as $i => $line) {
            $batch = $batches[$line['batch_id']];
            $available = max(0, (int) $batch->qty_units);
            if ($wanted[$batch->id] > $available) {
                $short[] = $this->lineRef($i, $line, $batch, $products[$batch->product_id]) + [
                    'requested_units' => $wanted[$batch->id],
                    'available_units' => $available,
                ];
            }
        }
        if ($short) {
            throw new BillRefused(422, [
                'message' => 'Not enough stock for some items.',
                'error' => 'insufficient_stock',
                'lines' => $short,
            ]);
        }
    }

    private function lineRef(int $index, array $line, ?Batch $batch, ?Product $product): array
    {
        return [
            'index' => $index,
            'batch_id' => $line['batch_id'],
            'name' => $product?->name,
            'batch_no' => $batch?->batch_no,
        ];
    }
}
