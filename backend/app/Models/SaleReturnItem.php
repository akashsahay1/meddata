<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** One bill line (batch) returned on a credit note, with its reversed tax. */
class SaleReturnItem extends Model
{
    public $timestamps = false;

    protected $guarded = [];

    protected function casts(): array
    {
        return [
            'line_no' => 'integer',
            'bill_item_id' => 'integer',
            'qty_units' => 'integer',
            'mrp_paise' => 'integer',
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

    public function saleReturn(): BelongsTo
    {
        return $this->belongsTo(SaleReturn::class);
    }
}
