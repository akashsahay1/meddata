<?php

namespace App\Support;

use DateTimeInterface;

/**
 * GST arithmetic for bills, in integer paise. Shop prices are MRPs, which
 * include GST, so tax is taken out of the amount rather than added on.
 * The app has the same maths (app/lib/domain/gst.dart) for its preview;
 * keep the two in step - the server's numbers are the ones that count.
 *
 * Per line:
 *   gross    = mrp x qty
 *   discount = gross x discount% (rounded half up)
 *   amount   = gross - discount          what the customer pays for it
 *   inter-state: taxable = amount x 100 / (100 + rate%), IGST = amount - taxable
 *   intra-state: CGST = SGST = amount x (rate%/2) / (100 + rate%),
 *                taxable = amount - CGST - SGST
 * so taxable + tax always equals the amount, and CGST always equals SGST.
 * The bill total is rounded to the nearest rupee (50 paise rounds up).
 */
final class GstMath
{
    /** n / d rounded half up, for n >= 0 and d > 0. */
    public static function roundDiv(int $n, int $d): int
    {
        return intdiv(2 * $n + $d, 2 * $d);
    }

    /**
     * @return array{gross_paise: int, discount_paise: int, rate_paise: int, taxable_paise: int,
     *               cgst_paise: int, sgst_paise: int, igst_paise: int, total_paise: int}
     */
    public static function line(int $mrpPaise, int $qty, int $discountBp, int $gstRateBp, bool $interState): array
    {
        $gross = $mrpPaise * $qty;
        $discount = self::roundDiv($gross * $discountBp, 10000);
        $amount = $gross - $discount;

        if ($interState) {
            $taxable = self::roundDiv($amount * 10000, 10000 + $gstRateBp);
            $cgst = $sgst = 0;
            $igst = $amount - $taxable;
        } else {
            $cgst = $sgst = self::roundDiv($amount * $gstRateBp, 2 * (10000 + $gstRateBp));
            $igst = 0;
            $taxable = $amount - $cgst - $sgst;
        }

        return [
            'gross_paise' => $gross,
            'discount_paise' => $discount,
            // Unit price before GST, after discount (display only).
            'rate_paise' => $qty > 0 ? self::roundDiv($taxable, $qty) : 0,
            'taxable_paise' => $taxable,
            'cgst_paise' => $cgst,
            'sgst_paise' => $sgst,
            'igst_paise' => $igst,
            'total_paise' => $amount,
        ];
    }

    /**
     * Bill totals from computed lines (each as returned by line()).
     *
     * @param  array<int, array<string, int>>  $lines
     * @return array{subtotal_paise: int, discount_paise: int, taxable_paise: int, cgst_paise: int,
     *               sgst_paise: int, igst_paise: int, round_off_paise: int, total_paise: int}
     */
    public static function totals(array $lines): array
    {
        $sum = fn (string $key): int => array_sum(array_column($lines, $key));
        $net = $sum('total_paise');
        $roundOff = self::roundDiv($net, 100) * 100 - $net;

        return [
            'subtotal_paise' => $sum('gross_paise'),
            'discount_paise' => $sum('discount_paise'),
            'taxable_paise' => $sum('taxable_paise'),
            'cgst_paise' => $sum('cgst_paise'),
            'sgst_paise' => $sum('sgst_paise'),
            'igst_paise' => $sum('igst_paise'),
            'round_off_paise' => $roundOff,
            'total_paise' => $net + $roundOff,
        ];
    }

    /** Indian financial year (1 April - 31 March) of a date, e.g. "26-27". */
    public static function financialYear(DateTimeInterface $date): string
    {
        $year = (int) $date->format('Y');
        $start = (int) $date->format('n') >= 4 ? $year : $year - 1;

        return sprintf('%02d-%02d', $start % 100, ($start + 1) % 100);
    }
}
