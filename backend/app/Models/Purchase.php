<?php

namespace App\Models;

use App\Support\GstStates;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * A supplier's bill entered by the shop. Created only by PurchaseService,
 * which also creates/attaches the batches and records the 'purchase' stock
 * movements; cancelling takes that stock back out.
 */
class Purchase extends Model
{
    public const STATUS_FINAL = 'final';

    public const STATUS_CANCELLED = 'cancelled';

    public $incrementing = false;

    protected $keyType = 'string';

    protected $guarded = [];

    protected function casts(): array
    {
        return [
            'is_inter_state' => 'boolean',
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

    public function party(): BelongsTo
    {
        return $this->belongsTo(Party::class)->withTrashed();
    }

    public function items(): HasMany
    {
        return $this->hasMany(PurchaseItem::class)->orderBy('line_no');
    }

    public function isCancelled(): bool
    {
        return $this->status === self::STATUS_CANCELLED;
    }

    public static function day(mixed $value): ?string
    {
        return $value === null ? null : substr((string) $value, 0, 10);
    }

    /** @return list<array{gst_rate_bp: int, taxable_paise: int, cgst_paise: int, sgst_paise: int, igst_paise: int}> */
    public function taxSummary(): array
    {
        return self::summarise($this->items);
    }

    /** Taxable value and tax per GST rate of any item list. */
    public static function summarise(iterable $items): array
    {
        $by = [];
        foreach ($items as $item) {
            $rate = (int) $item->gst_rate_bp;
            $by[$rate] ??= ['gst_rate_bp' => $rate, 'taxable_paise' => 0, 'cgst_paise' => 0, 'sgst_paise' => 0, 'igst_paise' => 0];
            foreach (['taxable_paise', 'cgst_paise', 'sgst_paise', 'igst_paise'] as $key) {
                $by[$rate][$key] += (int) $item->{$key};
            }
        }
        ksort($by);

        return array_values($by);
    }

    public function toApi(?array $extra = []): array
    {
        return [
            'id' => $this->id,
            'party_id' => $this->party_id,
            'supplier_name' => $this->supplier_name,
            'supplier_gstin' => $this->supplier_gstin,
            'supplier_state_code' => $this->supplier_state_code,
            'supplier_state_name' => GstStates::name($this->supplier_state_code),
            'supplier_invoice_no' => $this->supplier_invoice_no,
            'invoice_date' => self::day($this->invoice_date),
            'entry_date' => self::day($this->entry_date),
            'invoice_scan_id' => $this->invoice_scan_id,
            'is_inter_state' => $this->is_inter_state,
            'subtotal_paise' => $this->subtotal_paise,
            'discount_paise' => $this->discount_paise,
            'taxable_paise' => $this->taxable_paise,
            'cgst_paise' => $this->cgst_paise,
            'sgst_paise' => $this->sgst_paise,
            'igst_paise' => $this->igst_paise,
            'round_off_paise' => $this->round_off_paise,
            'total_paise' => $this->total_paise,
            'notes' => $this->notes,
            'status' => $this->status,
            'cancelled_at' => $this->cancelled_at?->toIso8601String(),
            'cancel_reason' => $this->cancel_reason,
            'created_at' => $this->created_at?->toIso8601String(),
            'items' => $this->items->map(fn (PurchaseItem $i) => $i->toApi())->all(),
            'tax_summary' => $this->taxSummary(),
        ] + ($extra ?? []);
    }

    public function toSummary(): array
    {
        return [
            'id' => $this->id,
            'party_id' => $this->party_id,
            'supplier_name' => $this->supplier_name,
            'supplier_invoice_no' => $this->supplier_invoice_no,
            'invoice_date' => self::day($this->invoice_date),
            'entry_date' => self::day($this->entry_date),
            'status' => $this->status,
            'total_paise' => $this->total_paise,
            'items_count' => (int) ($this->items_count ?? $this->items()->count()),
            'created_at' => $this->created_at?->toIso8601String(),
        ];
    }
}
