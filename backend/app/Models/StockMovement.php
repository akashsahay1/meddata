<?php

namespace App\Models;

use App\Models\Concerns\SyncedRow;
use Illuminate\Database\Eloquent\Model;

/** Append-only stock ledger entry; batches.qty_units is derived from these. */
class StockMovement extends Model
{
    use SyncedRow;

    public const REASONS = [
        'opening', 'purchase', 'purchase_free', 'sale', 'sale_return',
        'purchase_return', 'adjust', 'expiry_writeoff', 'migration',
    ];

    public static function clientFields(): array
    {
        return ['batch_id', 'delta_units', 'reason', 'ref_type', 'ref_id', 'occurred_at'];
    }

    protected function casts(): array
    {
        return ['occurred_at' => 'datetime'];
    }
}
