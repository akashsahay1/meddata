<?php

namespace Tests\Feature;

use App\Models\Bill;
use App\Models\PartyPayment;
use App\Models\StockMovement;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;
use Tests\Feature\Concerns\AccountingHelpers;
use Tests\TestCase;

/** PUT /bills/{id}: a bill edited in place keeps its number; stock and money follow. */
class BillEditApiTest extends TestCase
{
    use AccountingHelpers;
    use RefreshDatabase;

    private function edit(string $token, string $id, array $lines, array $extra = []): TestResponse
    {
        return $this->withToken($token)->putJson("/api/v1/bills/$id", $extra + [
            'device_id' => 'pc',
            'payment_mode' => 'cash',
            'lines' => $lines,
        ]);
    }

    public function test_changing_quantities_adding_and_removing_lines_moves_the_stock(): void
    {
        $token = $this->token();
        $this->shop($token);
        $dolo = $this->stock($token);                                                           // 20 in stock
        $syrup = $this->stock($token, ['name' => 'Cough Syrup', 'gst_rate_bp' => 500], ['batch_no' => 'S1', 'mrp_paise' => 5000], 10);
        $pan = $this->stock($token, ['name' => 'Pan 40'], ['batch_no' => 'P1', 'mrp_paise' => 2000], 5);

        $bill = $this->bill($token, [$this->line($dolo, 2), $this->line($syrup, 3)])->assertCreated()->json('bill');
        $this->assertSame([18, 7, 5], [$this->qty($dolo['batch']), $this->qty($syrup['batch']), $this->qty($pan['batch'])]);
        $since = $this->withToken($token)->getJson('/api/v1/sync/status')->json('server_version');

        // Dolo 2 -> 5, syrup removed, Pan 40 added (1 unit, 10% off).
        $res = $this->edit($token, $bill['id'], [$this->line($dolo, 5), $this->line($pan, 1, ['discount_bp' => 1000])])
            ->assertOk();
        $this->assertSame([15, 10, 4], [$this->qty($dolo['batch']), $this->qty($syrup['batch']), $this->qty($pan['batch'])]);
        $this->assertEqualsCanonicalizing(
            [[$dolo['batch'], 15], [$syrup['batch'], 10], [$pan['batch'], 4]],
            array_map(fn ($b) => [$b['batch_id'], $b['qty_units']], $res->json('batches')),
        );

        $edited = $res->json('bill');
        $this->assertSame([$bill['id'], $bill['invoice_no'], $bill['bill_date'], $bill['seq']],
            [$edited['id'], $edited['invoice_no'], $edited['bill_date'], $edited['seq']]);
        $this->assertSame('MED/26-27/000001', $edited['invoice_no']);
        $this->assertNotNull($edited['edited_at']);
        $this->assertSame(['Dolo 650', 'Pan 40'], array_column($edited['items'], 'name'));
        $this->assertSame([5, 1], array_column($edited['items'], 'qty_units'));
        // 5 x 112 + 20 less 10% = 560 + 18; GST 12% on both, intra-state.
        $this->assertSame(57800, $edited['total_paise']);
        $this->assertSame(['cash', 57800, 0], [$edited['payment_mode'], $edited['paid_paise'], $edited['balance_paise']]);
        $this->assertGreaterThan(0, $edited['cgst_paise']);
        $this->assertSame($edited['cgst_paise'], $edited['sgst_paise']);
        $this->assertSame(0, $edited['igst_paise']);
        $this->assertSame(Bill::count(), 1);

        // Old lines came back as sale_edit; devices pull the movements and the new stock.
        $this->assertSame(2, StockMovement::where('reason', 'sale_edit')->where('ref_id', $bill['id'])->count());
        $pull = $this->withToken($token)->getJson("/api/v1/sync/pull?since={$since}")->assertOk();
        $reasons = collect($pull->json('changes.stock_movements'))->map(fn ($m) => [$m['reason'], $m['delta_units']])->all();
        $this->assertEqualsCanonicalizing([['sale_edit', 2], ['sale_edit', 3], ['sale', -5], ['sale', -1]], $reasons);
        $this->assertEqualsCanonicalizing([15, 10, 4], array_column($pull->json('changes.batches'), 'qty_units'));

        // The next bill still takes the next number.
        $this->bill($token, [$this->line($dolo)])->assertCreated()->assertJsonPath('bill.invoice_no', 'MED/26-27/000002');
    }

    public function test_stock_check_counts_what_the_bill_already_holds(): void
    {
        $token = $this->token();
        $this->shop($token);
        $dolo = $this->stock($token, qty: 10);
        $id = $this->bill($token, [$this->line($dolo, 4)])->json('bill.id'); // 6 left

        $this->edit($token, $id, [$this->line($dolo, 11)])->assertStatus(422)
            ->assertJsonPath('error', 'insufficient_stock')
            ->assertJsonPath('lines.0.available_units', 10);
        $this->assertSame(6, $this->qty($dolo['batch']), 'a refused edit changes nothing');
        $this->assertSame(4, Bill::find($id)->items->first()->qty_units);

        $this->edit($token, $id, [$this->line($dolo, 10)])->assertOk()->assertJsonPath('bill.items.0.qty_units', 10);
        $this->assertSame(0, $this->qty($dolo['batch']));
    }

    public function test_a_stale_price_is_refused_like_a_new_bill(): void
    {
        $token = $this->token();
        $this->shop($token);
        $dolo = $this->stock($token);
        $id = $this->bill($token, [$this->line($dolo, 1)])->json('bill.id');
        $this->edit($token, $id, [$this->line($dolo, 2, ['mrp_paise' => 9900])])->assertStatus(409)
            ->assertJsonPath('error', 'price_changed');
    }

    public function test_cancelled_and_returned_bills_cannot_be_edited_and_other_shops_get_404(): void
    {
        $token = $this->token();
        $this->shop($token);
        $dolo = $this->stock($token);
        $cancelled = $this->bill($token, [$this->line($dolo)])->json('bill.id');
        $this->withToken($token)->postJson("/api/v1/bills/$cancelled/cancel")->assertOk();
        $this->edit($token, $cancelled, [$this->line($dolo)])->assertStatus(422)->assertJsonPath('error', 'bill_cancelled');

        $returned = $this->bill($token, [$this->line($dolo, 2)])->json('bill');
        $this->withToken($token)->postJson('/api/v1/sale-returns', [
            'id' => (string) Str::uuid(), 'bill_id' => $returned['id'], 'refund_mode' => 'cash',
            'lines' => [['bill_item_id' => $returned['items'][0]['id'], 'qty_units' => 1]],
        ])->assertCreated();
        $this->edit($token, $returned['id'], [$this->line($dolo, 3)])->assertStatus(422)->assertJsonPath('error', 'has_returns');

        $this->edit($this->token(), $returned['id'], [$this->line($dolo)])->assertNotFound();
        $this->edit($token, $returned['id'], [])->assertStatus(422)->assertJsonValidationErrors('lines');
    }

    public function test_customer_and_payment_follow_the_edit(): void
    {
        $token = $this->token();
        $this->shop($token);
        $dolo = $this->stock($token);
        $party = $this->party($token);

        // Cash bill, then edited to part paid (5000 by UPI) for a customer in Karnataka: IGST.
        $id = $this->bill($token, [$this->line($dolo, 2)])->json('bill.id');
        $bill = $this->edit($token, $id, [$this->line($dolo, 2)], [
            'payment_mode' => 'upi', 'received_paise' => 5000, 'party_id' => $party, 'customer_state_code' => '29',
        ])->assertOk()->json('bill');
        $this->assertSame(['credit', 22400, 5000, 17400, 'upi', true], [$bill['payment_mode'], $bill['total_paise'],
            $bill['paid_paise'], $bill['balance_paise'], $bill['received_mode'], $bill['is_inter_state']]);
        $this->assertSame([0, 0], [$bill['cgst_paise'], $bill['sgst_paise']]);
        $this->assertGreaterThan(0, $bill['igst_paise']);

        // Counter amount changed: the same payment row follows it.
        $this->edit($token, $id, [$this->line($dolo, 2)], ['payment_mode' => 'cash', 'received_paise' => 8000, 'party_id' => $party])
            ->assertOk()->assertJsonPath('bill.paid_paise', 8000)->assertJsonPath('bill.received_mode', 'cash');
        $this->assertSame(1, PartyPayment::where('bill_id', $id)->count());

        // A later collection: the new total can't go below what was paid.
        $this->withToken($token)->postJson('/api/v1/payments', [
            'id' => (string) Str::uuid(), 'party_id' => $party, 'direction' => 'in', 'mode' => 'cash',
            'amount_paise' => 10000, 'bill_id' => $id,
        ])->assertCreated();
        $this->edit($token, $id, [$this->line($dolo, 1)], ['received_paise' => 8000, 'party_id' => $party])
            ->assertStatus(422)->assertJsonPath('error', 'payments_exceed_total');
        $this->edit($token, $id, [$this->line($dolo, 2)], ['party_id' => $party])
            ->assertStatus(422)->assertJsonPath('error', 'has_payments');
        $this->edit($token, $id, [$this->line($dolo, 3)], ['received_paise' => 8000, 'party_id' => $party])
            ->assertOk()->assertJsonPath('bill.paid_paise', 18000)->assertJsonPath('bill.balance_paise', 15600);
        $this->withToken($token)->getJson("/api/v1/parties/$party")->assertJsonPath('party.balance_paise', 15600);

        // Paid in full on a bill without later payments: the counter payment is cancelled.
        $other = $this->bill($token, [$this->line($dolo)], ['received_paise' => 1000, 'party_id' => $party])->json('bill.id');
        $this->edit($token, $other, [$this->line($dolo)], ['payment_mode' => 'card'])->assertOk()
            ->assertJsonPath('bill.payment_mode', 'card')->assertJsonPath('bill.balance_paise', 0);
        $this->assertSame('cancelled', PartyPayment::where('bill_id', $other)->sole()->status);
    }
}
