<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Shop extends Model
{
    protected $fillable = [
        'owner_user_id', 'name', 'gstin', 'state_code', 'drug_license_no',
        'address', 'phone', 'invoice_prefix',
    ];

    protected $hidden = ['seq'];

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
