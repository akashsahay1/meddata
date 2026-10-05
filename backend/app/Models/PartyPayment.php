<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Money received from a party (in) or paid to one (out), optionally against
 * one bill or purchase. Never deleted: a mistake is cancelled, which takes
 * it out of the ledger.
 */
class PartyPayment extends Model
{
    public const MODES = ['cash', 'upi', 'card', 'bank', 'cheque'];

    public const DIRECTIONS = ['in', 'out'];

    public const STATUS_ACTIVE = 'active';

    public const STATUS_CANCELLED = 'cancelled';

    public $incrementing = false;

    protected $keyType = 'string';

    protected $guarded = [];

    protected function casts(): array
    {
        return [
            'amount_paise' => 'integer',
            'cancelled_at' => 'datetime',
        ];
    }

    public function party(): BelongsTo
    {
        return $this->belongsTo(Party::class)->withTrashed();
    }

    public function isCancelled(): bool
    {
        return $this->status === self::STATUS_CANCELLED;
    }

    public function toApi(): array
    {
        return [
            'id' => $this->id,
            'party_id' => $this->party_id,
            'direction' => $this->direction,
            'amount_paise' => $this->amount_paise,
            'mode' => $this->mode,
            'reference' => $this->reference,
            'payment_date' => Purchase::day($this->payment_date),
            'notes' => $this->notes,
            'bill_id' => $this->bill_id,
            'purchase_id' => $this->purchase_id,
            'status' => $this->status,
            'cancelled_at' => $this->cancelled_at?->toIso8601String(),
            'cancel_reason' => $this->cancel_reason,
            'created_at' => $this->created_at?->toIso8601String(),
        ];
    }
}
