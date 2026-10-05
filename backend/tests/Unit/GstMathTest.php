<?php

namespace Tests\Unit;

use App\Rules\Gstin;
use App\Support\GstMath;
use Carbon\CarbonImmutable;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\TestCase;

/**
 * The same vectors are in app/test/gst_math_test.dart: the app's preview
 * and the server's bill must agree to the paisa.
 */
class GstMathTest extends TestCase
{
    public static function lines(): array
    {
        // [mrp, qty, discount_bp, gst_rate_bp, inter] => [discount, taxable, cgst, sgst, igst, total, rate]
        return [
            'intra 5%' => [3000, 2, 0, 500, false, [0, 5714, 143, 143, 0, 6000, 2857]],
            'inter 5%' => [3000, 2, 0, 500, true, [0, 5714, 0, 0, 286, 6000, 2857]],
            'intra 12% with 10% off' => [11250, 3, 1000, 1200, false, [3375, 27121, 1627, 1627, 0, 30375, 9040]],
            'inter 12% with 10% off' => [11250, 3, 1000, 1200, true, [3375, 27121, 0, 0, 3254, 30375, 9040]],
            'discount rounds down below half' => [105, 1, 500, 1200, false, [5, 90, 5, 5, 0, 100, 90]],
            'discount rounds half up' => [105, 1, 1000, 1800, false, [11, 80, 7, 7, 0, 94, 80]],
            'inter 18% with 2.5% off' => [4599, 7, 250, 1800, true, [805, 26600, 0, 0, 4788, 31388, 3800]],
            'one paisa at 28%' => [1, 1, 0, 2800, false, [0, 1, 0, 0, 0, 1, 1]],
            'nil rated' => [99999, 13, 0, 0, false, [0, 1299987, 0, 0, 0, 1299987, 99999]],
            'free (100% off)' => [2050, 10, 10000, 1200, false, [20500, 0, 0, 0, 0, 0, 0]],
            'odd discount' => [3333, 3, 333, 500, false, [333, 9206, 230, 230, 0, 9666, 3069]],
        ];
    }

    #[DataProvider('lines')]
    public function test_line_maths(int $mrp, int $qty, int $discBp, int $rateBp, bool $inter, array $expected): void
    {
        $line = GstMath::line($mrp, $qty, $discBp, $rateBp, $inter);

        $this->assertSame($expected, [
            $line['discount_paise'], $line['taxable_paise'], $line['cgst_paise'],
            $line['sgst_paise'], $line['igst_paise'], $line['total_paise'], $line['rate_paise'],
        ]);
        // Tax is inside the MRP: taxable + tax is exactly what the customer pays.
        $this->assertSame($line['total_paise'],
            $line['taxable_paise'] + $line['cgst_paise'] + $line['sgst_paise'] + $line['igst_paise']);
        $this->assertSame($mrp * $qty - $line['discount_paise'], $line['total_paise']);
    }

    public function test_totals_round_to_the_nearest_rupee(): void
    {
        $totals = GstMath::totals([
            GstMath::line(3000, 2, 0, 500, false),
            GstMath::line(11250, 3, 1000, 1200, false),
        ]);

        $this->assertSame([
            'subtotal_paise' => 39750,
            'discount_paise' => 3375,
            'taxable_paise' => 32835,
            'cgst_paise' => 1770,
            'sgst_paise' => 1770,
            'igst_paise' => 0,
            'round_off_paise' => 25,
            'total_paise' => 36400,
        ], $totals);
    }

    public function test_round_off_is_half_up(): void
    {
        $roundOff = fn (int $net) => GstMath::totals([['gross_paise' => $net, 'discount_paise' => 0,
            'taxable_paise' => $net, 'cgst_paise' => 0, 'sgst_paise' => 0, 'igst_paise' => 0, 'total_paise' => $net]]);

        $this->assertSame([-49, 12300], array_values(array_slice($roundOff(12349), -2)));
        $this->assertSame([50, 12400], array_values(array_slice($roundOff(12350), -2)));
        $this->assertSame([1, 12400], array_values(array_slice($roundOff(12399), -2)));
        $this->assertSame([0, 0], array_values(array_slice($roundOff(0), -2)));
    }

    public function test_financial_year_runs_april_to_march(): void
    {
        $this->assertSame('26-27', GstMath::financialYear(CarbonImmutable::parse('2026-10-05')));
        $this->assertSame('26-27', GstMath::financialYear(CarbonImmutable::parse('2027-03-31 23:59:59')));
        $this->assertSame('27-28', GstMath::financialYear(CarbonImmutable::parse('2027-04-01 00:00:00')));
        $this->assertSame('25-26', GstMath::financialYear(CarbonImmutable::parse('2026-01-15')));
        $this->assertSame('99-00', GstMath::financialYear(CarbonImmutable::parse('2099-06-01')));
    }

    public function test_gstin_check_character(): void
    {
        $this->assertTrue(Gstin::isValid('27AAPFU0939F1ZV'));
        $this->assertTrue(Gstin::isValid('29AAGCB7383J1Z4'));
        $this->assertFalse(Gstin::isValid('27AAPFU0939F1ZX'), 'wrong check character');
        $this->assertFalse(Gstin::isValid('27AAPFU0939F1Z'), 'too short');
        $this->assertFalse(Gstin::isValid('27aapfu0939f1zv'), 'lower case is normalised before validation');
        $this->assertFalse(Gstin::isValid('99AAPFU0939F1ZV'), 'not a state code');
    }
}
