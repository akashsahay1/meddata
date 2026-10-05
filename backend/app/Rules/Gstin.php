<?php

namespace App\Rules;

use App\Support\GstStates;
use Closure;
use Illuminate\Contracts\Validation\ValidationRule;

/**
 * A regular GSTIN: state code, PAN, entity number, 'Z', check character.
 * The check character catches most typos, which matter on B2B invoices
 * (the buyer's input tax credit depends on the GSTIN being right).
 */
class Gstin implements ValidationRule
{
    private const CHARS = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';

    public function validate(string $attribute, mixed $value, Closure $fail): void
    {
        if (! is_string($value) || ! self::isValid($value)) {
            $fail('The :attribute is not a valid GSTIN.');
        }
    }

    public static function isValid(string $gstin): bool
    {
        if (! preg_match('/^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$/', $gstin)) {
            return false;
        }
        if (GstStates::name(substr($gstin, 0, 2)) === null) {
            return false;
        }

        return $gstin[14] === self::checkChar(substr($gstin, 0, 14));
    }

    /** GSTIN check character (weights 1,2,1,2,... in base 36). */
    public static function checkChar(string $first14): string
    {
        $sum = 0;
        for ($i = 0; $i < 14; $i++) {
            $product = strpos(self::CHARS, $first14[$i]) * ($i % 2 === 0 ? 1 : 2);
            $sum += intdiv($product, 36) + $product % 36;
        }

        return self::CHARS[(36 - $sum % 36) % 36];
    }
}
