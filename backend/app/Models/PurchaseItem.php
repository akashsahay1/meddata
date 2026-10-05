<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** One line of a supplier's bill: a batch received, as billed (per pack). */
class PurchaseItem extends Model
{
    public $timestamps = false;

    protected $guarded = [];

    protected function casts(): array
    {
        return [
            'line_no' => 'integer',
            'qty' => 'integer',
            'free_qty' => 'integer',
            'units_per_pack' => 'integer',
            'rate_paise' => 'integer',
            'mrp_paise' => 'integer',
            'discount_bp' => 'integer',
            'gst_rate_bp' => 'integer',
            'discount_paise' => 'integer',
            'taxable_paise' => 'integer',
            'cgst_paise' => 'integer',
            'sgst_paise' => 'integer',
            'igst_paise' => 'integer',
            'total_paise' => 'integer',
            'new_batch' => 'boolean',
        ];
    }

    public function purchase(): BelongsTo
    {
        return $this->belongsTo(Purchase::class);
    }

    /** Stock units this line added. */
    public function stockUnits(): int
    {
        return ($this->qty + $this->free_qty) * max(1, $this->units_per_pack);
    }

    public function toApi(): array
    {
        return [
            'id' => $this->id,
            'line_no' => $this->line_no,
            'product_id' => $this->product_id,
            'batch_id' => $this->batch_id,
            'name' => $this->name,
            'hsn' => $this->hsn,
            'batch_no' => $this->batch_no,
            'expiry_date' => Purchase::day($this->expiry_date),
            'mfg_date' => Purchase::day($this->mfg_date),
            'qty' => $this->qty,
            'free_qty' => $this->free_qty,
            'units_per_pack' => $this->units_per_pack,
            'stock_units' => $this->stockUnits(),
            'rate_paise' => $this->rate_paise,
            'mrp_paise' => $this->mrp_paise,
            'discount_bp' => $this->discount_bp,
            'gst_rate_bp' => $this->gst_rate_bp,
            'discount_paise' => $this->discount_paise,
            'taxable_paise' => $this->taxable_paise,
            'cgst_paise' => $this->cgst_paise,
            'sgst_paise' => $this->sgst_paise,
            'igst_paise' => $this->igst_paise,
            'total_paise' => $this->total_paise,
            'new_batch' => $this->new_batch,
            'returned_qty' => isset($this->returned_qty) ? (int) $this->returned_qty : null,
        ];
    }
}
