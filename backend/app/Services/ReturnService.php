<?php

namespace App\Services;

use App\Exceptions\ApiRefused;
use App\Models\Batch;
use App\Models\Bill;
use App\Models\BillItem;
use App\Models\Party;
use App\Models\Product;
use App\Models\Purchase;
use App\Models\PurchaseItem;
use App\Models\PurchaseReturn;
use App\Models\PurchaseReturnItem;
use App\Models\SaleReturn;
use App\Models\SaleReturnItem;
use App\Models\Shop;
use App\Models\User;
use App\Support\DocumentSeries;
use App\Support\GstMath;
use App\Support\StockLedger;
use Illuminate\Support\Facades\DB;

/**
 * Sale returns (credit notes, "CN/26-27/000001") and purchase returns
 * (debit notes, "DN/26-27/000001"), online-only.
 *
 * - A credit note is against one bill: per line, at most what was sold
 *   less what earlier credit notes returned. Tax is reversed with the same
 *   GstMath as the bill (the last units of a line take exactly what is left
 *   of it, so a line's returns add up to the line). Stock goes back to the
 *   same batch with 'sale_return' movements.
 * - A debit note is against a purchase (per line at most the billed qty
 *   less earlier returns) or, for a supplier, against any batches in stock.
 *   Stock goes out with 'purchase_return' movements; there must be enough.
 *
 * Each runs in one transaction under the shop row lock with its own
 * gap-free series per financial year; a refusal uses no number, and a
 * retry with the same id returns the same note.
 */
class ReturnService
{
    /** @return array{0: SaleReturn, 1: bool, 2: list<array{batch_id: string, qty_units: int}>} */
    public function saleReturn(Shop $shop, User $user, Bill $bill, array $data): array
    {
        return DB::transaction(function () use ($shop, $user, $bill, $data) {
            $shop = Shop::whereKey($shop->id)->lockForUpdate()->firstOrFail();
            if ($existing = $this->replay(SaleReturn::class, $shop, $data['id'])) {
                return [$existing, false, []];
            }
            /** @var Bill $bill */
            $bill = Bill::with('items')->whereKey($bill->id)->lockForUpdate()->firstOrFail();
            if ($bill->isCancelled()) {
                throw new ApiRefused(422, 'bill_cancelled', 'This bill is cancelled; its stock is already back.');
            }
            $refundMode = $this->refundMode($bill, $data['refund_mode'] ?? null);

            $items = $bill->items->keyBy('id');
            $wanted = $this->sumLines($data['lines'], 'bill_item_id', 'qty_units');
            $returned = $this->returnedSoFar(SaleReturnItem::class, 'bill_item_id', 'qty_units', array_keys($wanted));
            $over = [];
            foreach ($wanted as $itemId => $qty) {
                /** @var BillItem|null $item */
                $item = $items[$itemId] ?? null;
                if (! $item) {
                    throw new ApiRefused(422, 'item_not_on_bill', 'A returned item is not on this bill.', ['bill_item_id' => $itemId]);
                }
                $left = $item->qty_units - $returned[$itemId]['qty'];
                if ($qty > $left) {
                    $over[] = ['bill_item_id' => $itemId, 'name' => $item->name, 'batch_no' => $item->batch_no,
                        'sold' => $item->qty_units, 'returned' => $returned[$itemId]['qty'], 'returnable' => max(0, $left)];
                }
            }
            if ($over) {
                throw new ApiRefused(422, 'return_exceeds_sold', 'More is being returned than was sold.', ['lines' => $over]);
            }

            $rows = [];
            $calcs = [];
            foreach ($wanted as $itemId => $qty) {
                $item = $items[$itemId];
                $calc = $qty === $item->qty_units - $returned[$itemId]['qty']
                    ? GstMath::remainder($this->billItemCalc($item), $returned[$itemId]['calcs'])
                    : GstMath::line((int) $item->mrp_paise, $qty, (int) $item->discount_bp, (int) $item->gst_rate_bp, (bool) $bill->is_inter_state);
                $calcs[] = $calc;
                $rows[] = [
                    'line_no' => count($rows) + 1,
                    'bill_item_id' => $item->id,
                    'product_id' => $item->product_id,
                    'batch_id' => $item->batch_id,
                    'name' => $item->name,
                    'hsn' => $item->hsn,
                    'unit' => $item->unit,
                    'batch_no' => $item->batch_no,
                    'expiry_date' => Purchase::day($item->expiry_date),
                    'qty_units' => $qty,
                    'mrp_paise' => (int) $item->mrp_paise,
                    'discount_bp' => (int) $item->discount_bp,
                    'gst_rate_bp' => (int) $item->gst_rate_bp,
                ] + $this->amounts($calc);
            }

            $now = now(BillingService::TIMEZONE);
            $fy = GstMath::financialYear($now);
            $seq = DocumentSeries::next($shop->id, DocumentSeries::CREDIT_NOTE, $fy);
            $note = new SaleReturn;
            $note->id = $data['id'];
            $note->forceFill([
                'shop_id' => $shop->id,
                'bill_id' => $bill->id,
                'party_id' => $bill->party_id,
                'user_id' => $user->id,
                'device_id' => $data['device_id'] ?? null,
                'note_no' => DocumentSeries::format(DocumentSeries::CREDIT_NOTE, $fy, $seq),
                'fy' => $fy,
                'seq' => $seq,
                'return_date' => $now->toDateString(),
                'refund_mode' => $refundMode,
                'reason' => $data['reason'] ?? null,
                'customer_name' => $bill->customer_name,
                'customer_gstin' => $bill->customer_gstin,
                'place_of_supply' => $bill->place_of_supply,
                'is_inter_state' => (bool) $bill->is_inter_state,
                'seller' => $shop->invoiceDetails(),
            ] + GstMath::totals($calcs))->save();

            foreach ($rows as $row) {
                SaleReturnItem::create(['sale_return_id' => $note->id] + $row);
                StockLedger::move($shop, $user, $data['device_id'] ?? null, $row['batch_id'], $row['product_id'],
                    $row['qty_units'], 'sale_return', 'sale_return', $note->id);
            }
            $stock = StockLedger::refresh($shop, array_column($rows, 'batch_id'));

            return [$note->load('items'), true, $stock];
        });
    }

    /** @return array{0: PurchaseReturn, 1: bool, 2: list<array{batch_id: string, qty_units: int}>} */
    public function purchaseReturn(Shop $shop, User $user, array $data): array
    {
        return DB::transaction(function () use ($shop, $user, $data) {
            $shop = Shop::whereKey($shop->id)->lockForUpdate()->firstOrFail();
            if ($existing = $this->replay(PurchaseReturn::class, $shop, $data['id'])) {
                return [$existing, false, []];
            }

            $purchase = null;
            if (! empty($data['purchase_id'])) {
                $purchase = Purchase::with('items')->where('shop_id', $shop->id)->lockForUpdate()->find($data['purchase_id']);
                if (! $purchase) {
                    throw new ApiRefused(404, 'not_found', 'Purchase not found.');
                }
                if ($purchase->isCancelled()) {
                    throw new ApiRefused(422, 'purchase_cancelled', 'This purchase is cancelled.');
                }
                $party = Party::withTrashed()->find($purchase->party_id);
            } else {
                $party = Party::where('shop_id', $shop->id)->find($data['party_id'] ?? null);
                if (! $party || ! $party->isSupplier()) {
                    throw new ApiRefused(422, 'party_not_supplier', 'Choose the supplier the goods go back to.');
                }
            }
            $supplierState = $party->state_code ?: ($party->gstin ? substr($party->gstin, 0, 2) : null);
            $interState = $purchase ? (bool) $purchase->is_inter_state
                : ($shop->state_code !== null && $supplierState !== null && $supplierState !== $shop->state_code);

            [$rows, $calcs] = $purchase
                ? $this->againstPurchase($purchase, $data['lines'])
                : $this->fromStock($shop, $data['lines'], $interState);

            // Enough stock to send back?
            $need = [];
            foreach ($rows as $row) {
                $need[$row['batch_id']] = ($need[$row['batch_id']] ?? 0) + $row['qty'] * $row['units_per_pack'];
            }
            $batches = Batch::withTrashed()->where('shop_id', $shop->id)->whereIn('id', array_keys($need))->lockForUpdate()->get()->keyBy('id');
            $short = [];
            foreach ($need as $batchId => $units) {
                $left = (int) ($batches[$batchId]->qty_units ?? 0);
                if ($units > $left) {
                    $short[] = ['batch_id' => $batchId, 'batch_no' => $batches[$batchId]->batch_no ?? null,
                        'requested_units' => $units, 'available_units' => max(0, $left)];
                }
            }
            if ($short) {
                throw new ApiRefused(422, 'insufficient_stock', 'Not enough stock to send back.', ['lines' => $short]);
            }

            $now = now(BillingService::TIMEZONE);
            $fy = GstMath::financialYear($now);
            $seq = DocumentSeries::next($shop->id, DocumentSeries::DEBIT_NOTE, $fy);
            $note = new PurchaseReturn;
            $note->id = $data['id'];
            $note->forceFill([
                'shop_id' => $shop->id,
                'party_id' => $party->id,
                'purchase_id' => $purchase?->id,
                'user_id' => $user->id,
                'device_id' => $data['device_id'] ?? null,
                'note_no' => DocumentSeries::format(DocumentSeries::DEBIT_NOTE, $fy, $seq),
                'fy' => $fy,
                'seq' => $seq,
                'return_date' => $now->toDateString(),
                'reason' => $data['reason'] ?? null,
                'supplier_name' => $purchase?->supplier_name ?? $party->name,
                'supplier_gstin' => $purchase ? $purchase->supplier_gstin : $party->gstin,
                'supplier_invoice_no' => $purchase?->supplier_invoice_no,
                'is_inter_state' => $interState,
                'seller' => $shop->invoiceDetails(),
            ] + GstMath::totals($calcs))->save();

            foreach ($rows as $row) {
                PurchaseReturnItem::create(['purchase_return_id' => $note->id] + $row);
                StockLedger::move($shop, $user, $data['device_id'] ?? null, $row['batch_id'], $row['product_id'],
                    -$row['qty'] * $row['units_per_pack'], 'purchase_return', 'purchase_return', $note->id);
            }
            $stock = StockLedger::refresh($shop, array_keys($need));

            return [$note->load('items'), true, $stock];
        });
    }

    // ---------------------------------------------------------------------

    /** @return array{0: list<array<string, mixed>>, 1: list<array<string, int>>} */
    private function againstPurchase(Purchase $purchase, array $lines): array
    {
        $items = $purchase->items->keyBy('id');
        $wanted = $this->sumLines($lines, 'purchase_item_id', 'qty');
        $returned = $this->returnedSoFar(PurchaseReturnItem::class, 'purchase_item_id', 'qty', array_keys($wanted));
        $over = [];
        foreach ($wanted as $itemId => $qty) {
            /** @var PurchaseItem|null $item */
            $item = $items[$itemId] ?? null;
            if (! $item) {
                throw new ApiRefused(422, 'item_not_on_purchase', 'A returned item is not on this purchase.', ['purchase_item_id' => $itemId]);
            }
            $left = $item->qty - $returned[$itemId]['qty'];
            if ($qty > $left) {
                $over[] = ['purchase_item_id' => $itemId, 'name' => $item->name, 'batch_no' => $item->batch_no,
                    'bought' => $item->qty, 'returned' => $returned[$itemId]['qty'], 'returnable' => max(0, $left)];
            }
        }
        if ($over) {
            throw new ApiRefused(422, 'return_exceeds_bought', 'More is being returned than was bought (free goods are not returned on a debit note).', ['lines' => $over]);
        }

        $rows = [];
        $calcs = [];
        foreach ($wanted as $itemId => $qty) {
            $item = $items[$itemId];
            $calc = $qty === $item->qty - $returned[$itemId]['qty']
                ? GstMath::remainder($this->purchaseItemCalc($item), $returned[$itemId]['calcs'])
                : GstMath::purchaseLine($item->rate_paise, $qty, $item->discount_bp, $item->gst_rate_bp, (bool) $purchase->is_inter_state);
            $calcs[] = $calc;
            $rows[] = [
                'line_no' => count($rows) + 1,
                'purchase_item_id' => $item->id,
                'product_id' => $item->product_id,
                'batch_id' => $item->batch_id,
                'name' => $item->name,
                'hsn' => $item->hsn,
                'batch_no' => $item->batch_no,
                'expiry_date' => Purchase::day($item->expiry_date),
                'qty' => $qty,
                'units_per_pack' => $item->units_per_pack,
                'rate_paise' => $item->rate_paise,
                'discount_bp' => $item->discount_bp,
                'gst_rate_bp' => $item->gst_rate_bp,
            ] + $this->amounts($calc);
        }

        return [$rows, $calcs];
    }

    /** @return array{0: list<array<string, mixed>>, 1: list<array<string, int>>} */
    private function fromStock(Shop $shop, array $lines, bool $interState): array
    {
        $rows = [];
        $calcs = [];
        foreach (array_values($lines) as $i => $line) {
            if (empty($line['batch_id'])) {
                throw new ApiRefused(422, 'batch_required', 'Choose the batch to send back.', ['index' => $i]);
            }
            $batch = Batch::where('shop_id', $shop->id)->find(strtolower($line['batch_id']));
            $product = $batch ? Product::withTrashed()->find($batch->product_id) : null;
            if (! $batch || ! $product) {
                throw new ApiRefused(422, 'batch_not_found', 'A batch on this return is not in your inventory.', ['index' => $i]);
            }
            $qty = (int) $line['qty'];
            $rate = (int) ($line['rate_paise'] ?? $batch->purchase_rate_paise);
            $gst = (int) ($line['gst_rate_bp'] ?? $product->gst_rate_bp ?? $shop->default_gst_rate_bp);
            $discount = (int) ($line['discount_bp'] ?? 0);
            $calc = GstMath::purchaseLine($rate, $qty, $discount, $gst, $interState);
            $calcs[] = $calc;
            $rows[] = [
                'line_no' => $i + 1,
                'purchase_item_id' => null,
                'product_id' => $product->id,
                'batch_id' => $batch->id,
                'name' => $product->name,
                'hsn' => $product->hsn,
                'batch_no' => $batch->batch_no,
                'expiry_date' => $batch->expiry_date?->format('Y-m-d'),
                'qty' => $qty,
                'units_per_pack' => 1,
                'rate_paise' => $rate,
                'discount_bp' => $discount,
                'gst_rate_bp' => $gst,
            ] + $this->amounts($calc);
        }

        return [$rows, $calcs];
    }

    /** credit = adjusted on the customer's account; a credit bill's return always is. */
    private function refundMode(Bill $bill, ?string $asked): string
    {
        if ($bill->payment_mode === 'credit') {
            if ($asked !== null && $asked !== 'credit') {
                throw new ApiRefused(422, 'refund_mode', 'A credit bill’s return is adjusted on the customer’s account.');
            }

            return 'credit';
        }
        $mode = $asked ?? $bill->payment_mode;
        if ($mode === 'credit' && ! $bill->party_id) {
            throw new ApiRefused(422, 'refund_mode', 'Only a bill with a customer account can be adjusted on account.');
        }

        return $mode;
    }

    private function replay(string $class, Shop $shop, string $id): ?object
    {
        $existing = $class::with('items')->find($id);
        if ($existing && (int) $existing->shop_id !== (int) $shop->id) {
            throw new ApiRefused(422, 'id_conflict', 'This return id is already in use.');
        }

        return $existing;
    }

    /** @return array<int, int> line id => total qty asked */
    private function sumLines(array $lines, string $idKey, string $qtyKey): array
    {
        $out = [];
        foreach ($lines as $i => $line) {
            if (empty($line[$idKey])) {
                throw new ApiRefused(422, 'line_required', 'Choose the items being returned.', ['index' => $i]);
            }
            $out[(int) $line[$idKey]] = ($out[(int) $line[$idKey]] ?? 0) + (int) $line[$qtyKey];
        }

        return $out;
    }

    /** @return array<int, array{qty: int, calcs: list<array<string, int>>}> */
    private function returnedSoFar(string $class, string $idKey, string $qtyKey, array $ids): array
    {
        $out = array_fill_keys($ids, ['qty' => 0, 'calcs' => []]);
        foreach ($class::whereIn($idKey, $ids)->get() as $row) {
            $id = (int) $row->{$idKey};
            $out[$id]['qty'] += (int) $row->{$qtyKey};
            $out[$id]['calcs'][] = $row->only(['discount_paise', 'taxable_paise', 'cgst_paise', 'sgst_paise', 'igst_paise', 'total_paise'])
                + ['gross_paise' => (int) ($row->mrp_paise ?? $row->rate_paise) * (int) $row->{$qtyKey}];
        }

        return $out;
    }

    private function billItemCalc(BillItem $item): array
    {
        return [
            'gross_paise' => (int) $item->mrp_paise * (int) $item->qty_units,
            'discount_paise' => (int) $item->discount_paise,
            'taxable_paise' => (int) $item->taxable_paise,
            'cgst_paise' => (int) $item->cgst_paise,
            'sgst_paise' => (int) $item->sgst_paise,
            'igst_paise' => (int) $item->igst_paise,
            'total_paise' => (int) $item->total_paise,
        ];
    }

    private function purchaseItemCalc(PurchaseItem $item): array
    {
        return [
            'gross_paise' => $item->rate_paise * $item->qty,
            'discount_paise' => $item->discount_paise,
            'taxable_paise' => $item->taxable_paise,
            'cgst_paise' => $item->cgst_paise,
            'sgst_paise' => $item->sgst_paise,
            'igst_paise' => $item->igst_paise,
            'total_paise' => $item->total_paise,
        ];
    }

    private function amounts(array $calc): array
    {
        return array_intersect_key($calc, array_flip(['discount_paise', 'taxable_paise', 'cgst_paise', 'sgst_paise', 'igst_paise', 'total_paise']));
    }
}
