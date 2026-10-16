<?php

namespace App\Models;

use App\Support\GstStates;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * A GST sale invoice. Created only by BillingService (one transaction with
 * its number, items and stock movements). Cancelling keeps its number used.
 *
 * payment_mode: cash/upi/card = paid in full at the counter; credit = on
 * the customer's account, with whatever was taken at the counter recorded
 * as an at_billing party payment against it.
 */
class Bill extends Model
{
    public const PAYMENT_MODES = ['cash', 'upi', 'card', 'credit'];

    public const STATUS_FINAL = 'final';

    public const STATUS_CANCELLED = 'cancelled';

    /** Payments received against the bill (correlated to bills.id). */
    public const PAID_SQL = "(SELECT COALESCE(SUM(pp.amount_paise), 0) FROM party_payments pp WHERE pp.bill_id = bills.id AND pp.direction = 'in' AND pp.status = 'active')";

    /** Credit notes on the bill adjusted on the customer's account. */
    public const RETURNED_SQL = "(SELECT COALESCE(SUM(sr.total_paise), 0) FROM sale_returns sr WHERE sr.bill_id = bills.id AND sr.refund_mode = 'credit')";

    /** What is still to be paid on a credit bill (PartyLedger::billOutstanding in SQL). */
    public const DUE_SQL = '(bills.total_paise - '.self::PAID_SQL.' - '.self::RETURNED_SQL.')';

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

    /** Adds paid_in_paise and returned_credit_paise to each row (lists: no query per bill). */
    public function scopeWithPaid(Builder $query): void
    {
        if ($query->getQuery()->columns === null) {
            $query->select('bills.*');
        }
        $query->selectRaw(self::PAID_SQL.' AS paid_in_paise')
            ->selectRaw(self::RETURNED_SQL.' AS returned_credit_paise');
    }

    /** Final credit bills with money still to be paid. */
    public function scopeDue(Builder $query): void
    {
        $query->where('bills.status', self::STATUS_FINAL)->where('bills.payment_mode', 'credit')
            ->whereRaw(self::DUE_SQL.' > 0');
    }

    private function paidIn(): int
    {
        if (! array_key_exists('paid_in_paise', $this->attributes)) {
            $this->attributes['paid_in_paise'] = (int) PartyPayment::where('bill_id', $this->id)
                ->where('direction', 'in')->where('status', PartyPayment::STATUS_ACTIVE)->sum('amount_paise');
            $this->attributes['returned_credit_paise'] = (int) SaleReturn::where('bill_id', $this->id)
                ->where('refund_mode', 'credit')->sum('total_paise');
        }

        return (int) $this->attributes['paid_in_paise'];
    }

    /** Money received for the bill: the total for a cash/UPI/card bill, else the payments against it. */
    public function paidPaise(): int
    {
        return $this->payment_mode === 'credit' || $this->isCancelled() ? $this->paidIn() : (int) $this->total_paise;
    }

    /** Still to be paid: only a final credit bill can have a balance. */
    public function balancePaise(): int
    {
        if ($this->payment_mode !== 'credit' || $this->isCancelled()) {
            return 0;
        }
        $paid = $this->paidIn();

        return max(0, (int) $this->total_paise - $paid - (int) $this->attributes['returned_credit_paise']);
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
            'party_id' => $this->party_id,
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
            'paid_paise' => $this->paidPaise(),
            'balance_paise' => $this->balancePaise(),
            ...$this->receivedAtBilling(),
            'items' => $this->items->map(fn (BillItem $i) => $i->toApi())->all(),
            'tax_summary' => $this->taxSummary(),
        ];
    }

    /**
     * What was taken at the counter: the total for a cash/UPI/card bill, the
     * at-billing payment for a part-paid credit bill (mode null when none).
     *
     * @return array{received_paise: int, received_mode: ?string}
     */
    public function receivedAtBilling(): array
    {
        if ($this->payment_mode !== 'credit') {
            return ['received_paise' => (int) $this->total_paise, 'received_mode' => $this->payment_mode];
        }
        $payment = PartyPayment::where('bill_id', $this->id)->where('at_billing', true)
            ->where('status', PartyPayment::STATUS_ACTIVE)->first();

        return ['received_paise' => (int) ($payment?->amount_paise ?? 0), 'received_mode' => $payment?->mode];
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
            'party_id' => $this->party_id,
            'customer_name' => $this->customer_name,
            'customer_phone' => $this->customer_phone,
            'total_paise' => $this->total_paise,
            'paid_paise' => $this->paidPaise(),
            'balance_paise' => $this->balancePaise(),
            'items_count' => (int) ($this->items_count ?? $this->items()->count()),
        ];
    }
}
