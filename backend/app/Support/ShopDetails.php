<?php

namespace App\Support;

use App\Rules\Gstin;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/**
 * Validation for the shop details printed on invoices; shared by
 * PATCH /shops/current and the admin panel.
 */
final class ShopDetails
{
    /** @return array<string, array<int, mixed>> */
    public static function rules(): array
    {
        return [
            'name' => ['sometimes', 'required', 'string', 'max:255'],
            'legal_name' => ['sometimes', 'nullable', 'string', 'max:255'],
            'gstin' => ['sometimes', 'nullable', 'string', new Gstin],
            'state_code' => ['sometimes', 'nullable', 'string', Rule::in(GstStates::codes())],
            'drug_license_no' => ['sometimes', 'nullable', 'string', 'max:255'],
            'address' => ['sometimes', 'nullable', 'string', 'max:1000'],
            'phone' => ['sometimes', 'nullable', 'string', 'max:32'],
            // Letters/digits only, at most 3: "ABC/26-27/000042" is the
            // longest number that fits the 16-character GST limit.
            'invoice_prefix' => ['sometimes', 'nullable', 'string', 'regex:/^[A-Za-z0-9]{1,3}$/'],
            'default_gst_rate_bp' => ['sometimes', 'required', 'integer', 'min:0', 'max:2800'],
        ];
    }

    /**
     * Upper-case codes before validation; blanks become null; a state code
     * given as a number (7) becomes the two-character code ("07").
     */
    public static function prepare(array $input): array
    {
        foreach (['gstin', 'invoice_prefix'] as $key) {
            if (array_key_exists($key, $input) && is_string($input[$key])) {
                $value = strtoupper(trim($input[$key]));
                $input[$key] = $value === '' ? null : $value;
            }
        }
        if (is_int($input['state_code'] ?? null) || ctype_digit((string) ($input['state_code'] ?? 'x'))) {
            $input['state_code'] = str_pad((string) $input['state_code'], 2, '0', STR_PAD_LEFT);
        }

        return $input;
    }

    /**
     * Apply validated changes to the current values: the state follows the
     * GSTIN when none is set, and must match it when both are.
     *
     * @throws ValidationException
     */
    public static function merge(array $current, array $changes): array
    {
        $next = array_merge($current, $changes);
        $gstin = $next['gstin'] ?? null;
        if ($gstin) {
            $fromGstin = substr($gstin, 0, 2);
            if (empty($next['state_code'])) {
                $next['state_code'] = $fromGstin;
                $changes['state_code'] = $fromGstin;
            } elseif ($next['state_code'] !== $fromGstin) {
                throw ValidationException::withMessages([
                    'state_code' => 'The state must match the GSTIN (its first two digits are '.$fromGstin.').',
                ]);
            }
        }

        return $changes;
    }
}
