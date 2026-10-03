<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/** Shared medicine catalog (CSV seed + medicines added by shops). */
class MedicineMaster extends Model
{
    protected $table = 'medicines_master';

    protected $guarded = [];

    protected $casts = [
        'price' => 'decimal:2',
        'is_discontinued' => 'boolean',
    ];

    /** Lowercase, single-spaced — the form every lookup compares on. */
    public static function norm(?string $value): ?string
    {
        $v = trim(preg_replace('/\s+/', ' ', mb_strtolower((string) $value)));

        return $v === '' ? null : $v;
    }
}
