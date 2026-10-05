<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Shop extends Model
{
    protected $fillable = [
        'owner_user_id', 'name', 'legal_name', 'gstin', 'state_code', 'drug_license_no',
        'address', 'phone', 'invoice_prefix', 'default_gst_rate_bp',
    ];

    protected $hidden = ['seq'];

    /** Mirrors the column default so a just-created shop has it too. */
    protected $attributes = ['default_gst_rate_bp' => 500];

    protected function casts(): array
    {
        return ['default_gst_rate_bp' => 'integer'];
    }

    public function owner(): BelongsTo
    {
        return $this->belongsTo(User::class, 'owner_user_id');
    }

    public function devices(): HasMany
    {
        return $this->hasMany(ShopDevice::class);
    }

    public function products(): HasMany
    {
        return $this->hasMany(Product::class);
    }

    public function bills(): HasMany
    {
        return $this->hasMany(Bill::class);
    }

    /** Invoice number prefix; "INV" until the shop sets its own. */
    public function invoicePrefix(): string
    {
        $prefix = strtoupper(trim((string) $this->invoice_prefix));

        return $prefix !== '' ? $prefix : 'INV';
    }

    /** Seller details as printed on an invoice (copied onto each bill). */
    public function invoiceDetails(): array
    {
        return [
            'name' => $this->name,
            'legal_name' => $this->legal_name,
            'address' => $this->address,
            'phone' => $this->phone,
            'gstin' => $this->gstin,
            'state_code' => $this->state_code,
            'drug_license_no' => $this->drug_license_no,
        ];
    }

    /**
     * Reserve the next change version for this shop. Must run inside a DB
     * transaction; the row lock serialises concurrent pushes so versions are
     * unique and increasing (devices pull everything above their cursor).
     */
    public function nextVersion(): int
    {
        $seq = static::whereKey($this->id)->lockForUpdate()->value('seq') + 1;
        static::whereKey($this->id)->update(['seq' => $seq]);
        $this->seq = $seq;

        return $seq;
    }
}
