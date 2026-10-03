<?php

namespace App\Models;

use App\Models\Concerns\SyncedRow;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class Batch extends Model
{
    use SyncedRow;

    /** Price fields whose edits are recorded in price_changes. */
    public const PRICE_FIELDS = ['mrp_paise', 'purchase_rate_paise'];

    public static function clientFields(): array
    {
        return ['product_id', 'batch_no', 'expiry_date', 'mfg_date', 'mrp_paise', 'purchase_rate_paise'];
    }

    protected function casts(): array
    {
        return [
            'expiry_date' => 'date:Y-m-d',
            'mfg_date' => 'date:Y-m-d',
        ];
    }

    public function product(): BelongsTo
    {
        return $this->belongsTo(Product::class);
    }
}
