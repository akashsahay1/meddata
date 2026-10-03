<?php

namespace App\Models;

use App\Models\Concerns\SyncedRow;
use Illuminate\Database\Eloquent\Model;

/** Server-written audit of a batch price edit (which device, old -> new). */
class PriceChange extends Model
{
    use SyncedRow;

    public static function clientFields(): array
    {
        return [];
    }
}
