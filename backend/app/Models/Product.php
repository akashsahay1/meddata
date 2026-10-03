<?php

namespace App\Models;

use App\Models\Concerns\SyncedRow;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Product extends Model
{
    use SyncedRow;

    public static function clientFields(): array
    {
        return [
            'name', 'manufacturer', 'category', 'composition', 'unit', 'pack_size',
            'hsn', 'gst_rate_bp', 'barcode', 'low_stock_threshold_units',
            'discount_bp', 'master_id', 'notes',
        ];
    }

    public static function normalizeName(string $name): string
    {
        return trim(preg_replace('/\s+/', ' ', mb_strtolower($name)));
    }

    public function batches(): HasMany
    {
        return $this->hasMany(Batch::class);
    }
}
