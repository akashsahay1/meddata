<?php

namespace Tests\Feature;

use App\Models\PartyPayment;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;
use Tests\Feature\Concerns\AccountingHelpers;
use Tests\TestCase;

class LedgerPaymentApiTest extends TestCase
{
    use AccountingHelpers;
    use RefreshDatabase;

    private function pay(string $token, array $data): TestResponse
    {
        return $this->withToken($token)->postJson('/api/v1/payments', $data + [
            'id' => (string) Str::uuid(),
            'direction' => 'in',
            'mode' => 'cash',
        ]);
    }

    private function on(string $date): void
    {
        Carbon::setTestNow($date.' 11:00:00');
    }

    public function test_customer_ledger_running_balance(): void
    {
        $token = $this->token();
        $this->shop($token);
        $this->on('2026-10-01');
        $dolo = $this->stock($token);
        $party = $this->party($token, ['opening_balance_paise' => 10000]);

        $credit = $this->bill($token, [$this->line($dolo, 2)], ['payment_mode' => 'credit', 'party_id' => $party])
            ->assertCreated()->json('bill');
        $this->assertSame(22400, $credit['total_paise']);
        // Paid at the counter: not on the account.
        $this->bill($token, [$this->line($dolo)], ['party_id' => $party, 'payment_mode' => 'upi'])->assertCreated();
        // Cancelled: left out.
        $cancelled = $this->bill($token, [$this->line($dolo)], ['payment_mode' => 'credit', 'party_id' => $party])->json('bill.id');
        $this->withToken($token)->postJson("/api/v1/bills/$cancelled/cancel")->assertOk();

        $this->on('2026-10-03');
        $this->pay($token, ['party_id' => $party, 'amount_paise' => 5000, 'reference' => 'Counter'])
            ->assertCreated()->assertJsonPath('balance_paise', 27400)->assertJsonPath('payment.payment_date', '2026-10-03');
        $this->on('2026-10-04');
        $this->pay($token, ['party_id' => $party, 'direction' => 'out', 'amount_paise' => 1000, 'mode' => 'upi', 'reference' => 'UPI-77'])
            ->assertCreated()->assertJsonPath('balance_paise', 28400);
        $this->on('2026-10-05');
        $credit = $this->withToken($token)->getJson("/api/v1/bills/{$credit['id']}")->json('bill');
        $this->withToken($token)->postJson('/api/v1/sale-returns', [
            'id' => (string) Str::uuid(), 'bill_id' => $credit['id'],
            'lines' => [['bill_item_id' => $credit['items'][0]['id'], 'qty_units' => 1]],
        ])->assertCreated()->assertJsonPath('sale_return.refund_mode', 'credit');
        $wrong = $this->pay($token, ['party_id' => $party, 'amount_paise' => 999])->json('payment.id');
        $this->withToken($token)->postJson("/api/v1/payments/$wrong/cancel", ['reason' => 'Typo'])
            ->assertOk()->assertJsonPath('payment.status', 'cancelled')->assertJsonPath('balance_paise', 17200);

        $ledger = $this->withToken($token)->getJson("/api/v1/parties/$party/ledger")->assertOk();
        $this->assertSame(10000, $ledger->json('opening_paise'));
        $this->assertSame(17200, $ledger->json('closing_paise'));
        $this->assertSame(
            [['sale', 22400, 0, 32400], ['payment_in', 0, 5000, 27400], ['payment_out', 1000, 0, 28400], ['sale_return', 0, 11200, 17200]],
            array_map(fn ($e) => [$e['type'], $e['debit_paise'], $e['credit_paise'], $e['balance_paise']], $ledger->json('entries')),
        );
        $this->assertSame('MED/26-27/000001', $ledger->json('entries.0.number'));
        $this->assertSame(23400, $ledger->json('debit_paise'));
        $this->assertSame(16200, $ledger->json('credit_paise'));
        $this->assertSame(17200, $ledger->json('party.balance_paise'));
        $this->assertSame('Sahay Medicals Pvt Ltd', $ledger->json('seller.legal_name'));

        // A date range brings the earlier balance forward.
        $range = $this->withToken($token)->getJson("/api/v1/parties/$party/ledger?from=2026-10-03&to=2026-10-04")->assertOk();
        $this->assertSame([32400, 28400], [$range->json('opening_paise'), $range->json('closing_paise')]);
        $this->assertSame(['payment_in', 'payment_out'], array_column($range->json('entries'), 'type'));
        $this->withToken($token)->getJson("/api/v1/parties/$party/ledger?from=2026-10-05&to=2026-10-01")
            ->assertStatus(422)->assertJsonValidationErrors('to');

        // The list shows the same balance.
        $this->assertSame(17200, $this->withToken($token)->getJson('/api/v1/parties')->json('data.0.balance_paise'));
        // What is still due on the credit bill: 22400 - 11200 returned.
        $this->withToken($token)->getJson("/api/v1/parties/$party")
            ->assertJsonPath('open_documents.0.outstanding_paise', 11200)->assertJsonCount(1, 'open_documents');
    }

    public function test_supplier_ledger_with_allocated_payment_and_debit_note(): void
    {
        $token = $this->token();
        $this->shop($token);
        $supplier = $this->supplier($token, ['opening_balance_paise' => -50000]);
        $product = (string) Str::uuid();
        $purchase = $this->withToken($token)->postJson('/api/v1/purchases', [
            'id' => (string) Str::uuid(), 'party_id' => $supplier, 'supplier_invoice_no' => 'S-1', 'invoice_date' => '2026-10-02',
            'lines' => [['product_id' => $product, 'product' => ['name' => 'Pan 40'], 'expiry_date' => '2028-01-31',
                'qty' => 10, 'rate_paise' => 1000, 'mrp_paise' => 2000, 'gst_rate_bp' => 500]],
        ])->assertCreated()->json('purchase');
        $this->assertSame(10500, $purchase['total_paise']);

        $this->pay($token, ['party_id' => $supplier, 'direction' => 'out', 'amount_paise' => 5000, 'mode' => 'cheque',
            'reference' => 'CHQ 000123', 'purchase_id' => $purchase['id']])
            ->assertCreated()->assertJsonPath('payment.purchase_id', $purchase['id']);
        $this->withToken($token)->postJson('/api/v1/purchase-returns', [
            'id' => (string) Str::uuid(), 'purchase_id' => $purchase['id'],
            'lines' => [['purchase_item_id' => $purchase['items'][0]['id'], 'qty' => 2]],
        ])->assertCreated()->assertJsonPath('purchase_return.total_paise', 2100);

        $ledger = $this->withToken($token)->getJson("/api/v1/parties/$supplier/ledger")->assertOk();
        $this->assertSame(
            [['purchase', 0, 10500, -60500], ['payment_out', 5000, 0, -55500], ['purchase_return', 2100, 0, -53400]],
            array_map(fn ($e) => [$e['type'], $e['debit_paise'], $e['credit_paise'], $e['balance_paise']], $ledger->json('entries')),
        );
        $this->withToken($token)->getJson("/api/v1/purchases/{$purchase['id']}")->assertJsonPath('purchase.outstanding_paise', 3400)
            ->assertJsonPath('purchase.items.0.returned_qty', 2);

        // More than is still due can't be put against it.
        $this->pay($token, ['party_id' => $supplier, 'direction' => 'out', 'amount_paise' => 3401, 'mode' => 'bank', 'purchase_id' => $purchase['id']])
            ->assertStatus(422)->assertJsonPath('error', 'over_allocated')->assertJsonPath('outstanding_paise', 3400);
        $this->pay($token, ['party_id' => $supplier, 'direction' => 'out', 'amount_paise' => 3400, 'mode' => 'bank', 'purchase_id' => $purchase['id']])
            ->assertCreated()->assertJsonPath('balance_paise', -50000);
        $this->withToken($token)->getJson("/api/v1/parties/$supplier")->assertJsonCount(0, 'open_documents');
        $this->withToken($token)->getJson("/api/v1/payments?party_id=$supplier&direction=out")->assertJsonCount(2, 'data')
            ->assertJsonPath('data.0.amount_paise', 3400);
    }

    public function test_payment_validation_allocation_and_isolation(): void
    {
        $alice = $this->token();
        $bob = $this->token();
        $this->shop($alice);
        $dolo = $this->stock($alice);
        $ramesh = $this->party($alice);
        $other = $this->party($alice, ['name' => 'Suresh']);
        $bill = $this->bill($alice, [$this->line($dolo)], ['payment_mode' => 'credit', 'party_id' => $ramesh])->json('bill');
        $cash = $this->bill($alice, [$this->line($dolo)], ['party_id' => $ramesh])->json('bill');

        $this->pay($alice, ['party_id' => $ramesh, 'amount_paise' => 0, 'mode' => 'gpay', 'direction' => 'sideways'])
            ->assertStatus(422)->assertJsonValidationErrors(['amount_paise', 'mode', 'direction']);
        $this->pay($alice, ['party_id' => $ramesh, 'amount_paise' => 100, 'payment_date' => '2026-10-06'])
            ->assertStatus(422)->assertJsonValidationErrors('payment_date');
        $this->pay($alice, ['party_id' => $ramesh, 'amount_paise' => 100, 'direction' => 'out', 'bill_id' => $bill['id']])
            ->assertStatus(422)->assertJsonValidationErrors('bill_id');
        $this->pay($alice, ['party_id' => $ramesh, 'amount_paise' => 100, 'purchase_id' => (string) Str::uuid()])
            ->assertStatus(422)->assertJsonValidationErrors('purchase_id');
        // A bill of another party, a cash bill.
        $this->pay($alice, ['party_id' => $other, 'amount_paise' => 100, 'bill_id' => $bill['id']])->assertNotFound();
        $this->pay($alice, ['party_id' => $ramesh, 'amount_paise' => 100, 'bill_id' => $cash['id']])
            ->assertStatus(422)->assertJsonPath('error', 'not_payable');

        // Retry-safe.
        $id = (string) Str::uuid();
        $this->pay($alice, ['id' => $id, 'party_id' => $ramesh, 'amount_paise' => 500, 'bill_id' => $bill['id']])->assertCreated();
        $this->pay($alice, ['id' => $id, 'party_id' => $ramesh, 'amount_paise' => 500, 'bill_id' => $bill['id']])
            ->assertOk()->assertJsonPath('replayed', true);
        $this->assertSame(1, PartyPayment::count());

        // A bill with a payment against it can't be cancelled until the payment is.
        $this->withToken($alice)->postJson("/api/v1/bills/{$bill['id']}/cancel")->assertStatus(422)->assertJsonPath('error', 'has_payments');
        $this->withToken($alice)->postJson("/api/v1/payments/$id/cancel")->assertOk();
        $this->withToken($alice)->postJson("/api/v1/payments/$id/cancel")->assertOk()->assertJsonPath('payment.status', 'cancelled');
        $this->withToken($alice)->postJson("/api/v1/bills/{$bill['id']}/cancel")->assertOk();

        // Bob can't pay Alice's party, see or cancel her payments.
        $this->pay($bob, ['party_id' => $ramesh, 'amount_paise' => 100])->assertNotFound();
        $this->withToken($bob)->postJson("/api/v1/payments/$id/cancel")->assertNotFound();
        $this->assertSame([], $this->withToken($bob)->getJson('/api/v1/payments')->json('data'));
        $this->pay($bob, ['id' => $id, 'party_id' => $this->party($bob), 'amount_paise' => 100])->assertStatus(422);
    }
}
