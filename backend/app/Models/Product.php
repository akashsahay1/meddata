<?php

namespace App\Models;

use App\Support\PackSize;
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

    /** Pieces a batch price covers: the strip when the pack size applies, else one unit. */
    public function pricePack(): int
    {
        return PackSize::pricePack($this->unit, (int) $this->pack_size);
    }
}
