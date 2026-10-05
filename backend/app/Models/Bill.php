<?php

namespace App\Models;

use App\Support\GstStates;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * A GST sale invoice. Created only by BillingService (one transaction with
 * its number, items and stock movements); never edited afterwards except to
 * cancel it, which keeps its number used.
 */
class Bill extends Model
{
    public const PAYMENT_MODES = ['cash', 'upi', 'card', 'credit'];

    public const STATUS_FINAL = 'final';

    public const STATUS_CANCELLED = 'cancelled';

    public $incrementing = false;

    protected $keyType = 'string';

    protected $guarded = [];

    protected function casts(): array
    {
        // bill_date stays a plain 'Y-m-d' string (a date cast would store a
        // time too, which breaks date-range filters on SQLite).
        return [
            'is_inter_state' => 'boolean',
            'seller' => 'array',
            'seq' => 'integer',
            'subtotal_paise' => 'integer',
            'discount_paise' => 'integer',
            'taxable_paise' => 'integer',
            'cgst_paise' => 'integer',
            'sgst_paise' => 'integer',
            'igst_paise' => 'integer',
            'round_off_paise' => 'integer',
            'total_paise' => 'integer',
            'cancelled_at' => 'datetime',
        ];
    }

    public function shop(): BelongsTo
    {
        return $this->belongsTo(Shop::class);
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function items(): HasMany
    {
        return $this->hasMany(BillItem::class)->orderBy('line_no');
    }

    /** The bill date as 'Y-m-d' (whatever the driver returns). */
    public function billDate(): ?string
    {
        return $this->bill_date === null ? null : substr((string) $this->bill_date, 0, 10);
    }

    public function isCancelled(): bool
    {
        return $this->status === self::STATUS_CANCELLED;
    }

    /**
     * Taxable value and tax per GST rate (the invoice's tax summary, and
     * what GSTR reports group by).
     *
     * @return list<array{gst_rate_bp: int, taxable_paise: int, cgst_paise: int, sgst_paise: int, igst_paise: int}>
     */
    public function taxSummary(): array
    {
        $by = [];
        foreach ($this->items as $item) {
            $rate = (int) $item->gst_rate_bp;
            $by[$rate] ??= ['gst_rate_bp' => $rate, 'taxable_paise' => 0, 'cgst_paise' => 0, 'sgst_paise' => 0, 'igst_paise' => 0];
            foreach (['taxable_paise', 'cgst_paise', 'sgst_paise', 'igst_paise'] as $key) {
                $by[$rate][$key] += (int) $item->{$key};
            }
        }
        ksort($by);

        return array_values($by);
    }

    /** Full API representation: header, seller, items and tax summary. */
    public function toApi(): array
    {
        return [
            'id' => $this->id,
            'invoice_no' => $this->invoice_no,
            'fy' => $this->fy,
            'seq' => $this->seq,
            'bill_date' => $this->billDate(),
            'created_at' => $this->created_at?->toIso8601String(),
            'status' => $this->status,
            'payment_mode' => $this->payment_mode,
            'customer_name' => $this->customer_name,
            'customer_phone' => $this->customer_phone,
            'customer_gstin' => $this->customer_gstin,
            'customer_state_code' => $this->customer_state_code,
            'customer_address' => $this->customer_address,
            'place_of_supply' => $this->place_of_supply,
            'place_of_supply_name' => GstStates::name($this->place_of_supply),
            'is_inter_state' => $this->is_inter_state,
            'seller' => $this->seller,
            'subtotal_paise' => $this->subtotal_paise,
            'discount_paise' => $this->discount_paise,
            'taxable_paise' => $this->taxable_paise,
            'cgst_paise' => $this->cgst_paise,
            'sgst_paise' => $this->sgst_paise,
            'igst_paise' => $this->igst_paise,
            'round_off_paise' => $this->round_off_paise,
            'total_paise' => $this->total_paise,
            'device_id' => $this->device_id,
            'user_id' => $this->user_id,
            'cancelled_at' => $this->cancelled_at?->toIso8601String(),
            'cancel_reason' => $this->cancel_reason,
            'items' => $this->items->map(fn (BillItem $i) => $i->toApi())->all(),
            'tax_summary' => $this->taxSummary(),
        ];
    }

    /** Short row for bill lists. */
    public function toSummary(): array
    {
        return [
            'id' => $this->id,
            'invoice_no' => $this->invoice_no,
            'bill_date' => $this->billDate(),
            'created_at' => $this->created_at?->toIso8601String(),
            'status' => $this->status,
            'payment_mode' => $this->payment_mode,
            'customer_name' => $this->customer_name,
            'customer_phone' => $this->customer_phone,
            'total_paise' => $this->total_paise,
            'items_count' => (int) ($this->items_count ?? $this->items()->count()),
        ];
    }
}
