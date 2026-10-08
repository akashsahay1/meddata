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
 *   gross    = mrp x qty / packSize (rounded half up: the MRP is per pack of
 *              packSize pieces and qty is in pieces - see PackSize)
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
    public static function line(int $mrpPaise, int $qty, int $discountBp, int $gstRateBp, bool $interState, int $packSize = 1): array
    {
        $gross = self::roundDiv($mrpPaise * $qty, max(1, $packSize));
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
            // Price per pack before GST, after discount (display only).
            'rate_paise' => $qty > 0 ? self::roundDiv($taxable * max(1, $packSize), $qty) : 0,
            'taxable_paise' => $taxable,
            'cgst_paise' => $cgst,
            'sgst_paise' => $sgst,
            'igst_paise' => $igst,
            'total_paise' => $amount,
        ];
    }

    /**
     * A purchase line. Supplier bills print rates before GST, so tax is
     * added on top of the taxable value (unlike sales, where it is taken out
     * of the MRP):
     *   gross    = rate x qty
     *   discount = gross x discount% (rounded half up)
     *   taxable  = gross - discount
     *   inter-state: IGST = taxable x rate%
     *   intra-state: CGST = SGST = taxable x rate% / 2
     *   total    = taxable + tax
     * Same keys as line(), so totals() adds these up too.
     *
     * @return array{gross_paise: int, discount_paise: int, rate_paise: int, taxable_paise: int,
     *               cgst_paise: int, sgst_paise: int, igst_paise: int, total_paise: int}
     */
    public static function purchaseLine(int $ratePaise, int $qty, int $discountBp, int $gstRateBp, bool $interState, int $packSize = 1): array
    {
        $gross = self::roundDiv($ratePaise * $qty, max(1, $packSize));
        $discount = self::roundDiv($gross * $discountBp, 10000);
        $taxable = $gross - $discount;

        if ($interState) {
            $cgst = $sgst = 0;
            $igst = self::roundDiv($taxable * $gstRateBp, 10000);
        } else {
            $cgst = $sgst = self::roundDiv($taxable * $gstRateBp, 20000);
            $igst = 0;
        }

        return [
            'gross_paise' => $gross,
            'discount_paise' => $discount,
            'rate_paise' => $ratePaise,
            'taxable_paise' => $taxable,
            'cgst_paise' => $cgst,
            'sgst_paise' => $sgst,
            'igst_paise' => $igst,
            'total_paise' => $taxable + $cgst + $sgst + $igst,
        ];
    }

    /**
     * What is left of a line after earlier partial returns. Used when a
     * return takes the last units of a line, so all the returns of a line
     * add up exactly to the line (no paisa lost to rounding).
     *
     * @param  array<string, int>  $line
     * @param  array<int, array<string, int>>  $returned
     * @return array<string, int>
     */
    public static function remainder(array $line, array $returned): array
    {
        $out = $line;
        foreach (['gross_paise', 'discount_paise', 'taxable_paise', 'cgst_paise', 'sgst_paise', 'igst_paise', 'total_paise'] as $key) {
            $out[$key] = (int) ($line[$key] ?? 0) - array_sum(array_map(fn (array $r) => (int) ($r[$key] ?? 0), $returned));
        }

        return $out;
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
