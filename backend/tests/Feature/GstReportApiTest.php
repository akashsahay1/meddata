<?php

namespace Tests\Feature;

use App\Models\Bill;
use App\Models\Purchase;
use App\Models\PurchaseReturn;
use App\Models\SaleReturn;
use App\Services\GstReportService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Str;
use Tests\Feature\Concerns\AccountingHelpers;
use Tests\TestCase;

class GstReportApiTest extends TestCase
{
    use AccountingHelpers;
    use RefreshDatabase;

    private const HEADS = ['taxable_paise', 'cgst_paise', 'sgst_paise', 'igst_paise'];

    /**
     * October 2026 in a Maharashtra shop: B2B within the state and to
     * Karnataka, B2C small (local and to Delhi), one B2C large to Delhi, a
     * nil-rated sale, a cancelled bill, credit notes against B2B / B2CS /
     * B2CL, two purchases and a debit note. Plus a September bill that must
     * not show up.
     */
    private function month(string $token): array
    {
        $this->shop($token);
        Carbon::setTestNow('2026-09-30 10:00:00');
        $dolo = $this->stock($token, [], [], 5000);
        $nil = $this->stock($token, ['name' => 'Cotton', 'hsn' => '5601', 'gst_rate_bp' => 0], ['mrp_paise' => 5000]);
        $this->bill($token, [$this->line($dolo, 1)])->assertCreated();

        Carbon::setTestNow('2026-10-02 10:00:00');
        $local = $this->party($token, ['name' => 'City Hospital', 'gstin' => $this->gstin('27', 'AAACC1234K')]);
        $kar = $this->party($token, ['name' => 'Lakshmi Clinic', 'gstin' => $this->gstin('29')]);
        $b2bLocal = $this->bill($token, [$this->line($dolo, 10)], ['payment_mode' => 'credit', 'party_id' => $local])->json('bill');
        $this->bill($token, [$this->line($dolo, 5)], ['payment_mode' => 'credit', 'party_id' => $local])->assertCreated();
        $this->bill($token, [$this->line($dolo, 4)], ['party_id' => $kar])->assertCreated();
        $b2cs = $this->bill($token, [$this->line($dolo, 3), $this->line($nil, 2)])->json('bill');
        $this->bill($token, [$this->line($dolo, 2)], ['customer_state_code' => '07'])->assertCreated();
        $b2cl = $this->bill($token, [$this->line($dolo, 900)], ['customer_state_code' => '07', 'customer_name' => 'Delhi Trust'])->json('bill');
        $cancelled = $this->bill($token, [$this->line($dolo, 1)])->json('bill.id');
        $this->withToken($token)->postJson("/api/v1/bills/$cancelled/cancel")->assertOk();

        Carbon::setTestNow('2026-10-20 10:00:00');
        foreach ([[$b2bLocal, 2], [$b2cs, 1], [$b2cl, 100]] as [$bill, $qty]) {
            $this->withToken($token)->postJson('/api/v1/sale-returns', [
                'id' => (string) Str::uuid(), 'bill_id' => $bill['id'],
                'lines' => [['bill_item_id' => $bill['items'][0]['id'], 'qty_units' => $qty]],
            ])->assertCreated();
        }
        $supplier = $this->supplier($token);
        $outside = $this->supplier($token, ['name' => 'Bengaluru Pharma', 'gstin' => $this->gstin('29', 'AABCB1234C')]);
        $purchase = null;
        foreach ([[$supplier, 'L-1'], [$outside, 'K-1']] as [$party, $no]) {
            $purchase = $this->withToken($token)->postJson('/api/v1/purchases', [
                'id' => (string) Str::uuid(), 'party_id' => $party, 'supplier_invoice_no' => $no, 'invoice_date' => '2026-10-15',
                'lines' => [['product_id' => $dolo['product'], 'expiry_date' => '2028-01-31', 'qty' => 100, 'rate_paise' => 7000]],
            ])->assertCreated()->json('purchase');
        }
        $this->withToken($token)->postJson('/api/v1/purchase-returns', [
            'id' => (string) Str::uuid(), 'purchase_id' => $purchase['id'],
            'lines' => [['purchase_item_id' => $purchase['items'][0]['id'], 'qty' => 10]],
        ])->assertCreated();

        return ['b2cl' => $b2cl];
    }

    /** Taxable and tax of October's final bills less October's credit notes, from the tables. */
    private function booked(): array
    {
        $out = [];
        foreach (self::HEADS as $k) {
            $out[$k] = (int) Bill::where('status', 'final')->where('bill_date', '>=', '2026-10-01')->sum($k)
                - (int) SaleReturn::sum($k);
        }

        return $out;
    }

    public function test_gstr1_sections_reconcile_with_the_bills(): void
    {
        $token = $this->token();
        $docs = $this->month($token);

        $r = $this->withToken($token)->getJson('/api/v1/gst/gstr1?month=2026-10')->assertOk()->json();
        $this->assertSame(['GSTR-1', '27AAPFU0939F1ZV', true], [$r['return'], $r['gstin'], $r['registered']]);
        $this->assertStringContainsString('for review by your CA', $r['disclaimer']);

        // B2B by customer GSTIN.
        $this->assertSame(['City Hospital', 'Lakshmi Clinic'], array_column($r['b2b'], 'name'));
        $this->assertSame([2, 1], array_column($r['b2b'], 'invoice_count'));
        $this->assertSame('29', $r['b2b'][1]['invoices'][0]['place_of_supply']);
        $this->assertGreaterThan(0, $r['b2b'][1]['igst_paise']);
        $this->assertSame(0, $r['b2b'][0]['igst_paise']);
        // B2C large: the one inter-state invoice above Rs 1 lakh.
        $this->assertSame([$docs['b2cl']['invoice_no']], array_column($r['b2cl'], 'invoice_no'));
        $this->assertSame(10080000, $r['b2cl'][0]['invoice_value_paise']);
        // B2C small by place of supply / rate, local and Delhi.
        $this->assertSame([['07', 1200, 'INTER'], ['27', 1200, 'INTRA']],
            array_map(fn ($row) => [$row['place_of_supply'], $row['gst_rate_bp'], $row['supply_type']], $r['b2cs']));
        $this->assertCount(1, $r['cdnr']);
        $this->assertSame('CN/26-27/000001', $r['cdnr'][0]['note_no']);
        $this->assertCount(1, $r['cdnur']);
        $this->assertSame('B2CL', $r['cdnur'][0]['type']);
        $this->assertSame([['intra_unregistered', 10000]], array_map(fn ($n) => [$n['supply'], $n['nil_rated_paise']], $r['nil_rated']));

        // Every section together = October's bills less credit notes.
        $sum = array_fill_keys(self::HEADS, 0);
        $addRates = function (array $rates, int $sign) use (&$sum) {
            foreach ($rates as $rate) {
                foreach (self::HEADS as $k) {
                    $sum[$k] += $sign * $rate[$k];
                }
            }
        };
        foreach ($r['b2b'] as $g) {
            foreach ($g['invoices'] as $inv) {
                $addRates($inv['rates'], 1);
            }
        }
        foreach ($r['b2cl'] as $inv) {
            $addRates($inv['rates'], 1);
        }
        $addRates($r['b2cs'], 1);
        foreach ([...$r['cdnr'], ...$r['cdnur']] as $note) {
            $addRates($note['rates'], -1);
        }
        $sum['taxable_paise'] += array_sum(array_column($r['nil_rated'], 'nil_rated_paise'));
        $booked = $this->booked();
        $this->assertSame($booked, $sum);
        $this->assertSame($booked['taxable_paise'], $r['summary']['net']['taxable_paise']);

        // The HSN summary adds up to the same, split B2B / B2C.
        $hsn = array_fill_keys(self::HEADS, 0);
        foreach ([...$r['hsn']['b2b'], ...$r['hsn']['b2c']] as $row) {
            foreach (self::HEADS as $k) {
                $hsn[$k] += $row[$k];
            }
        }
        $this->assertSame($booked, $hsn);
        $this->assertSame(['3004'], array_values(array_unique(array_column($r['hsn']['b2b'], 'hsn'))));
        $this->assertEqualsCanonicalizing(['3004', '5601'], array_column($r['hsn']['b2c'], 'hsn'));

        // Documents issued: every October number, the cancelled one counted.
        $this->assertSame(['Invoices for outward supply', 'MED/26-27/000002', 'MED/26-27/000008', 7, 1, 6],
            array_values($r['documents'][0]));
        $this->assertSame(['Credit notes', 'CN/26-27/000001', 'CN/26-27/000003', 3, 0, 3], array_values($r['documents'][1]));
    }

    public function test_gstr3b_output_tax_itc_and_set_off(): void
    {
        $token = $this->token();
        $this->month($token);

        $r = $this->withToken($token)->getJson('/api/v1/gst/gstr3b?month=2026-10')->assertOk()->json();
        $this->assertStringContainsString('for review by your CA', $r['disclaimer']);
        $booked = $this->booked();
        $this->assertSame($booked['taxable_paise'] - 10000, $r['outward_taxable']['taxable_paise']);
        foreach (['cgst_paise', 'sgst_paise', 'igst_paise'] as $k) {
            $this->assertSame($booked[$k], $r['outward_taxable'][$k]);
        }
        $this->assertSame(10000, $r['outward_nil_rated']['taxable_paise']);
        // Inter-state to unregistered: Delhi only.
        $this->assertSame(['07'], array_column($r['inter_state_unregistered'], 'place_of_supply'));

        // ITC: 2 purchases of 100 x Rs 70 at 12% (one IGST), less a debit note of 10.
        $this->assertSame([42000, 42000, 84000, 2], [$r['itc']['available']['cgst_paise'], $r['itc']['available']['sgst_paise'],
            $r['itc']['available']['igst_paise'], $r['itc']['available']['purchase_count']]);
        $this->assertSame([0, 0, 8400], [$r['itc']['reversed']['cgst_paise'], $r['itc']['reversed']['sgst_paise'], $r['itc']['reversed']['igst_paise']]);
        $this->assertSame(['igst_paise' => 75600, 'cgst_paise' => 42000, 'sgst_paise' => 42000], $r['itc']['net']);
        $this->assertSame(
            (int) Purchase::sum('igst_paise') - (int) PurchaseReturn::sum('igst_paise'),
            $r['itc']['net']['igst_paise'],
        );

        $pay = $r['payment'];
        $this->assertSame(GstReportService::setOff($pay['tax_payable'], $r['itc']['net']), $pay);
        $this->assertSame(
            array_sum($pay['tax_payable']) - array_sum($pay['itc_used']),
            $pay['cash_payable']['total_paise'],
        );
    }

    public function test_itc_set_off_order(): void
    {
        // IGST credit goes to IGST, then CGST, then SGST.
        $r = GstReportService::setOff(['igst_paise' => 100, 'cgst_paise' => 300, 'sgst_paise' => 300],
            ['igst_paise' => 500, 'cgst_paise' => 0, 'sgst_paise' => 0]);
        $this->assertSame(['igst_paise' => 0, 'cgst_paise' => 0, 'sgst_paise' => 200, 'total_paise' => 200], $r['cash_payable']);
        $this->assertSame(0, $r['itc_carried_forward']['total_paise']);

        // CGST credit never pays SGST; leftover CGST credit pays IGST.
        $r = GstReportService::setOff(['igst_paise' => 50, 'cgst_paise' => 100, 'sgst_paise' => 100],
            ['igst_paise' => 0, 'cgst_paise' => 400, 'sgst_paise' => 20]);
        $this->assertSame(['igst_paise' => 0, 'cgst_paise' => 0, 'sgst_paise' => 80, 'total_paise' => 80], $r['cash_payable']);
        $this->assertSame(['igst_paise' => 0, 'cgst_paise' => 250, 'sgst_paise' => 0, 'total_paise' => 250], $r['itc_carried_forward']);

        // More credit notes than sales: nothing payable, nothing negative.
        $r = GstReportService::setOff(['igst_paise' => -10, 'cgst_paise' => 0, 'sgst_paise' => 0],
            ['igst_paise' => 5, 'cgst_paise' => 0, 'sgst_paise' => 0]);
        $this->assertSame(0, $r['cash_payable']['total_paise']);
        $this->assertSame(5, $r['itc_carried_forward']['igst_paise']);
    }

    public function test_month_validation_and_shop_isolation(): void
    {
        $alice = $this->token();
        $bob = $this->token();
        $this->month($alice);

        $this->withToken($alice)->getJson('/api/v1/gst/gstr1')->assertStatus(422)->assertJsonValidationErrors('month');
        $this->withToken($alice)->getJson('/api/v1/gst/gstr3b?month=2026-13')->assertStatus(422);
        $this->withToken($alice)->getJson('/api/v1/gst/gstr1?month=2026-09')->assertOk()
            ->assertJsonPath('summary.bills.count', 1)->assertJsonCount(0, 'cdnr');

        $bobs = $this->withToken($bob)->getJson('/api/v1/gst/gstr1?month=2026-10')->assertOk()->json();
        $this->assertSame([[], [], [], false], [$bobs['b2b'], $bobs['b2cs'], $bobs['hsn']['b2c'], $bobs['registered']]);
        $this->assertSame(0, $bobs['documents'][0]['total']);
        $this->assertSame(0, $this->withToken($bob)->getJson('/api/v1/gst/gstr3b?month=2026-10')->json('itc.available.purchase_count'));
        $this->withoutToken()->getJson('/api/v1/gst/gstr1?month=2026-10')->assertUnauthorized();
    }
}
