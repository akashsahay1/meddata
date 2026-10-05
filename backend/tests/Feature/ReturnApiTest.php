<?php

namespace Tests\Feature;

use App\Models\SaleReturn;
use App\Models\StockMovement;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;
use Tests\Feature\Concerns\AccountingHelpers;
use Tests\TestCase;

class ReturnApiTest extends TestCase
{
    use AccountingHelpers;
    use RefreshDatabase;

    private function saleReturn(string $token, string $billId, array $lines, array $extra = []): TestResponse
    {
        return $this->withToken($token)->postJson('/api/v1/sale-returns', $extra + [
            'id' => (string) Str::uuid(), 'device_id' => 'phone', 'bill_id' => $billId, 'lines' => $lines,
        ]);
    }

    private function purchaseReturn(string $token, array $data): TestResponse
    {
        return $this->withToken($token)->postJson('/api/v1/purchase-returns', $data + ['id' => (string) Str::uuid()]);
    }

    public function test_credit_notes_limit_quantities_reverse_gst_exactly_and_number_without_gaps(): void
    {
        $token = $this->token();
        $this->shop($token);
        $syrup = $this->stock($token, ['name' => 'Cough Syrup', 'unit' => 'Bottles'], ['mrp_paise' => 11250]);
        $bill = $this->bill($token, [$this->line($syrup, 3, ['discount_bp' => 1000])])->assertCreated()->json('bill');
        $item = $bill['items'][0];
        $this->assertSame([3375, 27121, 1627, 1627, 30375], [$item['discount_paise'], $item['taxable_paise'],
            $item['cgst_paise'], $item['sgst_paise'], $item['total_paise']]);
        $this->assertSame(17, $this->qty($syrup['batch']));

        $first = $this->saleReturn($token, $bill['id'], [['bill_item_id' => $item['id'], 'qty_units' => 1]], ['reason' => 'Damaged'])
            ->assertCreated()->json('sale_return');
        $this->assertSame('CN/26-27/000001', $first['note_no']);
        // Same maths as the bill for one bottle; refunded like the bill was paid.
        $this->assertSame(['cash', 1125, 9041, 542, 542, 10125, 0, 10100],
            [$first['refund_mode'], $first['items'][0]['discount_paise'], $first['items'][0]['taxable_paise'], $first['items'][0]['cgst_paise'],
                $first['items'][0]['sgst_paise'], $first['items'][0]['total_paise'], $first['igst_paise'], $first['total_paise']]);
        $this->assertSame(-25, $first['round_off_paise']);
        $this->assertSame(18, $this->qty($syrup['batch']));

        // Too many: refused, no number used up.
        $this->saleReturn($token, $bill['id'], [['bill_item_id' => $item['id'], 'qty_units' => 3]])
            ->assertStatus(422)->assertJsonPath('error', 'return_exceeds_sold')
            ->assertJsonPath('lines.0.sold', 3)->assertJsonPath('lines.0.returned', 1)->assertJsonPath('lines.0.returnable', 2);
        // The same item split over two lines counts together.
        $this->saleReturn($token, $bill['id'], [['bill_item_id' => $item['id'], 'qty_units' => 2], ['bill_item_id' => $item['id'], 'qty_units' => 1]])
            ->assertStatus(422)->assertJsonPath('lines.0.returnable', 2);

        // The rest: the two notes add up exactly to the bill line.
        $second = $this->saleReturn($token, $bill['id'], [['bill_item_id' => $item['id'], 'qty_units' => 2]])->assertCreated()->json('sale_return');
        $this->assertSame('CN/26-27/000002', $second['note_no']);
        foreach (['discount_paise', 'taxable_paise', 'cgst_paise', 'sgst_paise', 'total_paise'] as $key) {
            $this->assertSame($item[$key], $first['items'][0][$key] + $second['items'][0][$key], $key);
        }
        $this->assertSame(20, $this->qty($syrup['batch']));
        $this->assertSame([1, 2], StockMovement::where('reason', 'sale_return')->orderBy('delta_units')->pluck('delta_units')->map(fn ($v) => (int) $v)->all());
        $this->saleReturn($token, $bill['id'], [['bill_item_id' => $item['id'], 'qty_units' => 1]])->assertStatus(422);

        // The bill shows what went back; it can't be cancelled now.
        $shown = $this->withToken($token)->getJson("/api/v1/bills/{$bill['id']}")->assertOk();
        $this->assertSame(3, $shown->json('bill.items.0.returned_qty'));
        $this->assertSame(['CN/26-27/000001', 'CN/26-27/000002'], array_column($shown->json('bill.returns'), 'note_no'));
        $this->withToken($token)->postJson("/api/v1/bills/{$bill['id']}/cancel")->assertStatus(422)->assertJsonPath('error', 'has_returns');

        // The series restarts in the next financial year.
        Carbon::setTestNow('2027-04-01 10:00:00');
        $next = $this->bill($token, [$this->line($syrup)])->json('bill');
        $this->saleReturn($token, $next['id'], [['bill_item_id' => $next['items'][0]['id'], 'qty_units' => 1]])
            ->assertCreated()->assertJsonPath('sale_return.note_no', 'CN/27-28/000001');
        $this->assertSame(2, (int) DB::table('document_series')->where('fy', '26-27')->value('last_seq'));
    }

    public function test_sale_return_rules_retries_and_isolation(): void
    {
        $alice = $this->token();
        $bob = $this->token();
        $this->shop($alice);
        $dolo = $this->stock($alice);
        $party = $this->party($alice);
        $cash = $this->bill($alice, [$this->line($dolo, 2)])->json('bill');
        $credit = $this->bill($alice, [$this->line($dolo, 2)], ['payment_mode' => 'credit', 'party_id' => $party])->json('bill');
        $line = fn (array $b, int $q = 1) => [['bill_item_id' => $b['items'][0]['id'], 'qty_units' => $q]];

        $this->saleReturn($alice, $cash['id'], [])->assertStatus(422)->assertJsonValidationErrors('lines');
        $this->saleReturn($alice, $cash['id'], [['bill_item_id' => $credit['items'][0]['id'], 'qty_units' => 1]])
            ->assertStatus(422)->assertJsonPath('error', 'item_not_on_bill');
        // A walk-in's bill can't go on account; a credit bill's return always does.
        $this->saleReturn($alice, $cash['id'], $line($cash), ['refund_mode' => 'credit'])->assertStatus(422)->assertJsonPath('error', 'refund_mode');
        $this->saleReturn($alice, $credit['id'], $line($credit), ['refund_mode' => 'cash'])->assertStatus(422)->assertJsonPath('error', 'refund_mode');
        $this->saleReturn($alice, $cash['id'], $line($cash), ['refund_mode' => 'upi'])->assertCreated()->assertJsonPath('sale_return.refund_mode', 'upi');

        $id = (string) Str::uuid();
        $this->saleReturn($alice, $credit['id'], $line($credit), ['id' => $id])->assertCreated()->assertJsonPath('sale_return.party_id', $party);
        $this->saleReturn($alice, $credit['id'], $line($credit), ['id' => $id])->assertOk()->assertJsonPath('replayed', true);
        $this->assertSame(2, SaleReturn::count());
        $this->withToken($alice)->getJson("/api/v1/sale-returns?bill_id={$credit['id']}")->assertJsonCount(1, 'data');
        $this->withToken($alice)->getJson("/api/v1/sale-returns/$id")->assertOk()->assertJsonPath('sale_return.bill_invoice_no', $credit['invoice_no']);

        // A cancelled bill has nothing to return.
        $other = $this->bill($alice, [$this->line($dolo)])->json('bill');
        $this->withToken($alice)->postJson("/api/v1/bills/{$other['id']}/cancel")->assertOk();
        $this->saleReturn($alice, $other['id'], $line($other))->assertStatus(422)->assertJsonPath('error', 'bill_cancelled');

        // Bob sees and returns nothing of Alice's.
        $this->saleReturn($bob, $cash['id'], $line($cash))->assertNotFound();
        $this->withToken($bob)->getJson("/api/v1/sale-returns/$id")->assertNotFound();
        $this->assertSame([], $this->withToken($bob)->getJson('/api/v1/sale-returns')->json('data'));
        $this->saleReturn($bob, $this->bill($bob, [$this->line($this->stock($bob))])->json('bill.id'), [['bill_item_id' => 1, 'qty_units' => 1]], ['id' => $id])
            ->assertStatus(422);
    }

    public function test_debit_notes_against_a_purchase_and_from_stock(): void
    {
        $token = $this->token();
        $this->shop($token);
        $supplier = $this->supplier($token);
        $product = (string) Str::uuid();
        $purchase = $this->withToken($token)->postJson('/api/v1/purchases', [
            'id' => (string) Str::uuid(), 'party_id' => $supplier, 'supplier_invoice_no' => 'S-9', 'invoice_date' => '2026-10-02',
            'lines' => [['product_id' => $product, 'product' => ['name' => 'Pan 40', 'unit' => 'Tablets'], 'expiry_date' => '2028-01-31',
                'qty' => 3, 'free_qty' => 1, 'units_per_pack' => 10, 'rate_paise' => 3333, 'discount_bp' => 500, 'mrp_paise' => 6000, 'gst_rate_bp' => 1200]],
        ])->assertCreated()->json('purchase');
        $item = $purchase['items'][0];
        $batch = $item['batch_id'];
        $this->assertSame(40, $this->qty($batch));

        $first = $this->purchaseReturn($token, ['purchase_id' => $purchase['id'], 'reason' => 'Short expiry',
            'lines' => [['purchase_item_id' => $item['id'], 'qty' => 1]]])->assertCreated()->json('purchase_return');
        $this->assertSame(['DN/26-27/000001', 'Pune Pharma Distributors', 'S-9'], [$first['note_no'], $first['party_name'], $first['supplier_invoice_no']]);
        $this->assertSame(30, $this->qty($batch));
        // Free packs are not returned on a debit note: 2 billed packs are left.
        $this->purchaseReturn($token, ['purchase_id' => $purchase['id'], 'lines' => [['purchase_item_id' => $item['id'], 'qty' => 3]]])
            ->assertStatus(422)->assertJsonPath('error', 'return_exceeds_bought')->assertJsonPath('lines.0.returnable', 2);
        $second = $this->purchaseReturn($token, ['purchase_id' => $purchase['id'], 'lines' => [['purchase_item_id' => $item['id'], 'qty' => 2]]])
            ->assertCreated()->json('purchase_return');
        $this->assertSame('DN/26-27/000002', $second['note_no']);
        foreach (['discount_paise', 'taxable_paise', 'cgst_paise', 'sgst_paise', 'total_paise'] as $key) {
            $this->assertSame($item[$key], $first['items'][0][$key] + $second['items'][0][$key], $key);
        }
        $this->assertSame(10, $this->qty($batch));
        $this->withToken($token)->postJson("/api/v1/purchases/{$purchase['id']}/cancel")->assertStatus(422)->assertJsonPath('error', 'has_returns');

        // From stock (no purchase): rate from the batch, IGST for an out-of-state supplier; stock must be there.
        $other = $this->supplier($token, ['name' => 'Bengaluru Pharma', 'gstin' => $this->gstin('29')]);
        $this->purchaseReturn($token, ['party_id' => $other, 'lines' => [['batch_id' => $batch, 'qty' => 11]]])
            ->assertStatus(422)->assertJsonPath('error', 'insufficient_stock')->assertJsonPath('lines.0.available_units', 10);
        $dn = $this->purchaseReturn($token, ['party_id' => $other, 'lines' => [['batch_id' => $batch, 'qty' => 4]]])->assertCreated()->json('purchase_return');
        $rate = (int) round(3333 * 0.95 / 10);
        $this->assertSame([$rate, 4 * $rate, true, 'DN/26-27/000003'], [$dn['items'][0]['rate_paise'], $dn['items'][0]['taxable_paise'], $dn['is_inter_state'], $dn['note_no']]);
        $this->assertSame((int) round(4 * $rate * 0.12), $dn['igst_paise']);
        $this->assertSame(6, $this->qty($batch));
        $this->assertSame(-34, (int) StockMovement::where('reason', 'purchase_return')->sum('delta_units'));

        // Validation and isolation.
        $this->purchaseReturn($token, ['lines' => [['batch_id' => $batch, 'qty' => 1]]])->assertStatus(422)->assertJsonValidationErrors('purchase_id');
        $this->purchaseReturn($token, ['party_id' => $this->party($token), 'lines' => [['batch_id' => $batch, 'qty' => 1]]])
            ->assertStatus(422)->assertJsonPath('error', 'party_not_supplier');
        $bob = $this->token();
        $this->purchaseReturn($bob, ['purchase_id' => $purchase['id'], 'lines' => [['purchase_item_id' => $item['id'], 'qty' => 1]]])->assertNotFound();
        $bobs = $this->supplier($bob);
        $this->purchaseReturn($bob, ['party_id' => $bobs, 'lines' => [['batch_id' => $batch, 'qty' => 1]]])
            ->assertStatus(422)->assertJsonPath('error', 'batch_not_found');
        $this->withToken($bob)->getJson("/api/v1/purchase-returns/{$dn['id']}")->assertNotFound();
        $this->assertSame(6, $this->qty($batch));
        $this->withToken($token)->getJson("/api/v1/purchase-returns?purchase_id={$purchase['id']}")->assertJsonCount(2, 'data');
    }
}
