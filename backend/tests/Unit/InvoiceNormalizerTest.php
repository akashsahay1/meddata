<?php

namespace Tests\Unit;

use App\Services\InvoiceNormalizer;
use App\Support\MedicineNameKey;
use PHPUnit\Framework\TestCase;

class InvoiceNormalizerTest extends TestCase
{
    public function test_dates_become_y_m_d_with_month_only_expiry_at_month_end(): void
    {
        $n = new InvoiceNormalizer;
        $expiry = fn ($v) => $n->date($v, endOfMonth: true);

        $this->assertSame('2027-06-30', $expiry('2027-06'));
        $this->assertSame('2027-06-30', $expiry('06/27'));
        $this->assertSame('2027-06-30', $expiry('6/2027'));
        $this->assertSame('2027-06-30', $expiry('Jun-27'));
        $this->assertSame('2027-06-30', $expiry('EXP: JUN 2027'));
        $this->assertSame('2028-02-29', $expiry('02/28'));
        $this->assertSame('2027-06-01', $n->date('06/27'));          // mfg: first of the month
        $this->assertSame('2027-06-05', $n->date('05/06/2027'));     // day first
        $this->assertSame('2027-06-05', $n->date('05-06-27'));
        $this->assertSame('2027-06-05', $n->date('2027-06-05'));
        $this->assertSame('2027-06-05', $n->date('2027-06-05T00:00:00Z'));
        $this->assertSame('2026-10-01', $n->date('1 Oct 2026'));
        $this->assertSame('2026-10-01', $n->date('Oct 1, 2026'));

        foreach (['', 'N/A', '31/02/2027', '13/27', '2027', 'soon', null, 2027] as $bad) {
            $this->assertNull($n->date($bad), var_export($bad, true));
        }
    }

    public function test_numbers_and_codes_are_cleaned(): void
    {
        $n = new InvoiceNormalizer;

        $this->assertSame(1234.5, $n->money('₹ 1,234.50'));
        $this->assertSame(45.0, $n->money('Rs. 45'));
        $this->assertSame(12.0, $n->percent('12%'));
        $this->assertNull($n->percent(120));
        $this->assertNull($n->money(-3));
        $this->assertSame(10, $n->quantity(10.0));
        $this->assertNull($n->quantity('ten'));

        $out = $n->normalize([
            'supplier_gstin' => ' 27abcde 1234f1z5 ',
            'items' => [
                ['product_name' => '  Pan   40 ', 'hsn' => '3004.90', 'barcode' => '12', 'batch_no' => 'na', 'free_quantity' => null],
                ['product_name' => '   '],
                'not a line',
            ],
        ]);

        $this->assertSame('27ABCDE1234F1Z5', $out['supplier_gstin']);
        $this->assertNull($out['invoice_no']);
        $this->assertCount(1, $out['items']);
        $this->assertSame('Pan 40', $out['items'][0]['product_name']);
        $this->assertSame('300490', $out['items'][0]['hsn']);
        $this->assertNull($out['items'][0]['barcode']);   // too short for a barcode
        $this->assertNull($out['items'][0]['batch_no']);
        $this->assertSame(0, $out['items'][0]['free_quantity']);
        $this->assertNull($out['items'][0]['quantity']);
    }

    public function test_medicine_names_match_loosely_but_not_across_dosage_forms(): void
    {
        $this->assertTrue(MedicineNameKey::same('DOLO-650 TAB 15\'S', 'Dolo 650'));
        $this->assertTrue(MedicineNameKey::same('Dolo 650 Tablet', 'DOLO 650 TABS'));
        $this->assertTrue(MedicineNameKey::same('PAN 40MG TAB', 'Pan 40'));
        $this->assertTrue(MedicineNameKey::same('AUGMENTIN DUO 625 TAB 1X10', 'Augmentin 625 Duo Tablet'));
        $this->assertTrue(MedicineNameKey::same('Alprax 0.25', 'ALPRAX 0.25 TAB'));

        $this->assertFalse(MedicineNameKey::same('Crocin Syrup', 'Crocin Tab'));
        $this->assertFalse(MedicineNameKey::same('Dolo 650', 'Dolo 500'));
        $this->assertFalse(MedicineNameKey::same('Alprax 0.25', 'Alprax 0.5'));
        $this->assertFalse(MedicineNameKey::same('Benadryl 100ml', 'Benadryl 50ml'));
        $this->assertFalse(MedicineNameKey::same('', ''));
    }
}
