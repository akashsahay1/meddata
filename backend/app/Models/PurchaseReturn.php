<?php

namespace App\Models;

use App\Support\GstStates;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * A debit note: goods sent back to a supplier. Created only by
 * ReturnService (its own gap-free DN series, stock out, input GST reversed
 * with the purchase maths).
 */
class PurchaseReturn extends Model
{
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

    public function purchase(): BelongsTo
    {
        return $this->belongsTo(Purchase::class);
    }

    public function items(): HasMany
    {
        return $this->hasMany(PurchaseReturnItem::class)->orderBy('line_no');
    }

    public function toApi(): array
    {
        $stateCode = $this->supplier_gstin ? substr($this->supplier_gstin, 0, 2) : null;

        return [
            'id' => $this->id,
            'kind' => 'debit_note',
            'note_no' => $this->note_no,
            'fy' => $this->fy,
            'seq' => $this->seq,
            'return_date' => Purchase::day($this->return_date),
            'created_at' => $this->created_at?->toIso8601String(),
            'purchase_id' => $this->purchase_id,
            'supplier_invoice_no' => $this->supplier_invoice_no,
            'party_id' => $this->party_id,
            'reason' => $this->reason,
            'party_name' => $this->supplier_name,
            'party_gstin' => $this->supplier_gstin,
            'place_of_supply' => $stateCode,
            'place_of_supply_name' => GstStates::name($stateCode),
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
            'items' => $this->items->map(fn (PurchaseReturnItem $i) => [
                'line_no' => $i->line_no,
                'purchase_item_id' => $i->purchase_item_id,
                'product_id' => $i->product_id,
                'batch_id' => $i->batch_id,
                'name' => $i->name,
                'hsn' => $i->hsn,
                'unit' => null,
                'batch_no' => $i->batch_no,
                'expiry_date' => Purchase::day($i->expiry_date),
                'qty' => $i->qty,
                'units_per_pack' => $i->units_per_pack,
                'rate_paise' => $i->rate_paise,
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
            'kind' => 'debit_note',
            'note_no' => $this->note_no,
            'return_date' => Purchase::day($this->return_date),
            'purchase_id' => $this->purchase_id,
            'party_id' => $this->party_id,
            'party_name' => $this->supplier_name,
            'total_paise' => $this->total_paise,
            'created_at' => $this->created_at?->toIso8601String(),
        ];
    }
}
