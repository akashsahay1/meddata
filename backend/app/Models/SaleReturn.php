<?php

namespace App\Models;

use App\Support\GstStates;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * A credit note: goods a customer returned against a bill. Created only by
 * ReturnService (its own gap-free CN series, stock back, GST reversed with
 * the bill's maths). refund_mode 'credit' = adjusted against the customer's
 * account (shows in the ledger); otherwise refunded at the counter.
 */
class SaleReturn extends Model
{
    public const REFUND_MODES = ['credit', 'cash', 'upi', 'card', 'bank'];

    public $incrementing = false;

    protected $keyType = 'string';

    protected $guarded = [];

    protected function casts(): array
    {
        return [
            'is_inter_state' => 'boolean',
            'seller' => 'array',
            'seq' => 'integer',
            'subtotal_paise' => 'integer',
            'discount_paise' => 'integer',
            'taxable_paise' => 'integer',
            'cgst_paise' => 'integer',
            'sgst_paise' => 'integer',
            'igst_paise' => 'integer',
            'round_off_paise' => 'integer',
            'total_paise' => 'integer',
        ];
    }

    public function bill(): BelongsTo
    {
        return $this->belongsTo(Bill::class);
    }

    public function items(): HasMany
    {
        return $this->hasMany(SaleReturnItem::class)->orderBy('line_no');
    }

    public function toApi(): array
    {
        $bill = $this->bill;

        return [
            'id' => $this->id,
            'kind' => 'credit_note',
            'note_no' => $this->note_no,
            'fy' => $this->fy,
            'seq' => $this->seq,
            'return_date' => Purchase::day($this->return_date),
            'created_at' => $this->created_at?->toIso8601String(),
            'bill_id' => $this->bill_id,
            'bill_invoice_no' => $bill?->invoice_no,
            'bill_date' => $bill?->billDate(),
            'party_id' => $this->party_id,
            'refund_mode' => $this->refund_mode,
            'reason' => $this->reason,
            'party_name' => $this->customer_name,
            'party_gstin' => $this->customer_gstin,
            'place_of_supply' => $this->place_of_supply,
            'place_of_supply_name' => GstStates::name($this->place_of_supply),
            'is_inter_state' => $this->is_inter_state,
            'seller' => $this->seller,
            'subtotal_paise' => $this->subtotal_paise,
            'discount_paise' => $this->discount_paise,
            'taxable_paise' => $this->taxable_paise,
            'cgst_paise' => $this->cgst_paise,
            'sgst_paise' => $this->sgst_paise,
            'igst_paise' => $this->igst_paise,
            'round_off_paise' => $this->round_off_paise,
            'total_paise' => $this->total_paise,
            'items' => $this->items->map(fn (SaleReturnItem $i) => [
                'line_no' => $i->line_no,
                'bill_item_id' => $i->bill_item_id,
                'product_id' => $i->product_id,
                'batch_id' => $i->batch_id,
                'name' => $i->name,
                'hsn' => $i->hsn,
                'unit' => $i->unit,
                'pack_size' => (int) $i->pack_size,
                'batch_no' => $i->batch_no,
                'expiry_date' => Purchase::day($i->expiry_date),
                'qty' => $i->qty_units,
                'rate_paise' => $i->mrp_paise,
                'discount_bp' => $i->discount_bp,
                'discount_paise' => $i->discount_paise,
                'gst_rate_bp' => $i->gst_rate_bp,
                'taxable_paise' => $i->taxable_paise,
                'cgst_paise' => $i->cgst_paise,
                'sgst_paise' => $i->sgst_paise,
                'igst_paise' => $i->igst_paise,
                'total_paise' => $i->total_paise,
            ])->all(),
            'tax_summary' => Purchase::summarise($this->items),
        ];
    }

    public function toSummary(): array
    {
        return [
            'id' => $this->id,
            'kind' => 'credit_note',
            'note_no' => $this->note_no,
            'return_date' => Purchase::day($this->return_date),
            'bill_id' => $this->bill_id,
            'party_id' => $this->party_id,
            'party_name' => $this->customer_name,
            'refund_mode' => $this->refund_mode,
            'total_paise' => $this->total_paise,
            'created_at' => $this->created_at?->toIso8601String(),
        ];
    }
}
