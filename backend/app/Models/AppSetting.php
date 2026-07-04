<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class AppSetting extends Model
{
    protected $fillable = ['key', 'value', 'type', 'label', 'group'];

    /** Read a setting, cast to its declared type, with a fallback. */
    public static function get(string $key, mixed $default = null): mixed
    {
        $row = static::where('key', $key)->first();
        if (! $row) {
            return $default;
        }
        return match ($row->type) {
            'int' => (int) $row->value,
            'bool' => filter_var($row->value, FILTER_VALIDATE_BOOLEAN),
            'json' => json_decode($row->value, true),
            default => $row->value,
        };
    }

    public static function put(string $key, mixed $value, string $type = 'string'): void
    {
        static::updateOrCreate(
            ['key' => $key],
            ['value' => is_array($value) ? json_encode($value) : (string) $value, 'type' => $type],
        );
    }
}
