<?php

namespace App\Models;

use App\Support\GstStates;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * A customer or supplier (or both) of a shop, for credit sales, purchases,
 * payments and ledgers. Online-only, like bills.
 *
 * Balance sign convention (opening balance and ledger): positive = the
 * party owes the shop (receivable, "to collect"), negative = the shop owes
 * the party (payable, "to pay").
 */
class Party extends Model
{
    use SoftDeletes;

    public const TYPES = ['customer', 'supplier', 'both'];

    public $incrementing = false;

    protected $keyType = 'string';

    protected $guarded = [];

    protected function casts(): array
    {
        return ['opening_balance_paise' => 'integer'];
    }

    public function shop(): BelongsTo
    {
        return $this->belongsTo(Shop::class);
    }

    public function isCustomer(): bool
    {
        return in_array($this->type, ['customer', 'both'], true);
    }

    public function isSupplier(): bool
    {
        return in_array($this->type, ['supplier', 'both'], true);
    }

    public static function normalizeName(string $name): string
    {
        return mb_substr(trim(preg_replace('/\s+/', ' ', mb_strtolower($name))), 0, 100);
    }

    public function toApi(?int $balance = null): array
    {
        return [
            'id' => $this->id,
            'type' => $this->type,
            'name' => $this->name,
            'phone' => $this->phone,
            'gstin' => $this->gstin,
            'state_code' => $this->state_code,
            'state_name' => GstStates::name($this->state_code),
            'address' => $this->address,
            'opening_balance_paise' => $this->opening_balance_paise,
            'notes' => $this->notes,
            'balance_paise' => $balance,
            'created_at' => $this->created_at?->toIso8601String(),
            'updated_at' => $this->updated_at?->toIso8601String(),
        ];
    }
}
