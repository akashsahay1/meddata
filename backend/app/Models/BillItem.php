<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** One batch sold on a bill, with its prices and tax as invoiced. */
class BillItem extends Model
{
    public $timestamps = false;

    protected $guarded = [];

    protected function casts(): array
    {
        // expiry_date stays a plain 'Y-m-d' string, like bills.bill_date.
        return [
            'line_no' => 'integer',
            'qty_units' => 'integer',
            'mrp_paise' => 'integer',
            'rate_paise' => 'integer',
            'discount_bp' => 'integer',
            'discount_paise' => 'integer',
            'gst_rate_bp' => 'integer',
            'taxable_paise' => 'integer',
            'cgst_paise' => 'integer',
            'sgst_paise' => 'integer',
            'igst_paise' => 'integer',
            'total_paise' => 'integer',
        ];
    }

    public function bill(): BelongsTo
    {
        return $this->belongsTo(Bill::class);
    }

    public function toApi(): array
    {
        return [
            'line_no' => $this->line_no,
            'product_id' => $this->product_id,
            'batch_id' => $this->batch_id,
            'name' => $this->name,
            'hsn' => $this->hsn,
            'unit' => $this->unit,
            'batch_no' => $this->batch_no,
            'expiry_date' => $this->expiry_date === null ? null : substr((string) $this->expiry_date, 0, 10),
            'qty_units' => $this->qty_units,
            'mrp_paise' => $this->mrp_paise,
            'rate_paise' => $this->rate_paise,
            'discount_bp' => $this->discount_bp,
            'discount_paise' => $this->discount_paise,
            'gst_rate_bp' => $this->gst_rate_bp,
            'taxable_paise' => $this->taxable_paise,
            'cgst_paise' => $this->cgst_paise,
            'sgst_paise' => $this->sgst_paise,
            'igst_paise' => $this->igst_paise,
            'total_paise' => $this->total_paise,
        ];
    }
}
