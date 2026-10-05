<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** One batch sent back to a supplier on a debit note. */
class PurchaseReturnItem extends Model
{
    public $timestamps = false;

    protected $guarded = [];

    protected function casts(): array
    {
        return [
            'line_no' => 'integer',
            'purchase_item_id' => 'integer',
            'qty' => 'integer',
            'units_per_pack' => 'integer',
            'rate_paise' => 'integer',
            'discount_bp' => 'integer',
            'gst_rate_bp' => 'integer',
            'discount_paise' => 'integer',
            'taxable_paise' => 'integer',
            'cgst_paise' => 'integer',
            'sgst_paise' => 'integer',
            'igst_paise' => 'integer',
            'total_paise' => 'integer',
        ];
    }

    public function purchaseReturn(): BelongsTo
    {
        return $this->belongsTo(PurchaseReturn::class);
    }
}
