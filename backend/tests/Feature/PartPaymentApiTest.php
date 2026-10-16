<?php

namespace Tests\Feature;

use App\Models\PartyPayment;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\Feature\Concerns\AccountingHelpers;
use Tests\TestCase;

/** Bills paid in part at the counter: the rest goes on the customer's account. */
class PartPaymentApiTest extends TestCase
{
    use AccountingHelpers;
    use RefreshDatabase;

    public function test_part_paid_bill_is_a_credit_bill_with_the_counter_payment_recorded(): void
    {
        $token = $this->token();
        $this->shop($token);
        $dolo = $this->stock($token);
        $party = $this->party($token);

        // Two units = 22400; 10000 taken in cash now.
        $bill = $this->bill($token, [$this->line($dolo, 2)], [
            'payment_mode' => 'cash', 'received_paise' => 10000, 'party_id' => $party,
        ])->assertCreated()->json('bill');
        $this->assertSame(['credit', 22400, 10000, 12400, 10000, 'cash'],
            [$bill['payment_mode'], $bill['total_paise'], $bill['paid_paise'], $bill['balance_paise'],
                $bill['received_paise'], $bill['received_mode']]);

        $payment = PartyPayment::where('bill_id', $bill['id'])->sole();
        $this->assertSame(['in', 10000, 'cash', true, 'active', $party],
            [$payment->direction, $payment->amount_paise, $payment->mode, $payment->at_billing, $payment->status, $payment->party_id]);
        // The customer's account owes only the rest.
        $this->withToken($token)->getJson("/api/v1/parties/$party")
            ->assertJsonPath('party.balance_paise', 12400)
            ->assertJsonPath('open_documents.0.outstanding_paise', 12400);

        // "Mark as paid": the rest collected later against the bill.
        $this->withToken($token)->postJson('/api/v1/payments', [
            'id' => (string) Str::uuid(), 'party_id' => $party, 'direction' => 'in', 'mode' => 'upi',
            'amount_paise' => 12400, 'bill_id' => $bill['id'],
        ])->assertCreated()->assertJsonPath('balance_paise', 0);
        $this->withToken($token)->getJson("/api/v1/bills/{$bill['id']}")
            ->assertJsonPath('bill.paid_paise', 22400)->assertJsonPath('bill.balance_paise', 0);
    }

    public function test_received_rules(): void
    {
        $token = $this->token();
        $this->shop($token);
        $dolo = $this->stock($token);
        $party = $this->party($token);

        // More than the total.
        $this->bill($token, [$this->line($dolo)], ['received_paise' => 11201])
            ->assertStatus(422)->assertJsonPath('error', 'received_exceeds_total');
        // Part paid needs a customer account for the rest.
        $this->bill($token, [$this->line($dolo)], ['received_paise' => 5000])
            ->assertStatus(422)->assertJsonPath('error', 'party_required');
        // Credit means nothing taken now.
        $this->bill($token, [$this->line($dolo)], ['payment_mode' => 'credit', 'party_id' => $party, 'received_paise' => 100])
            ->assertStatus(422)->assertJsonValidationErrors('received_paise');
        $this->assertSame(0, DB::table('bills')->count(), 'refused bills use no number');

        // Paid in full (default, or said so): a plain UPI bill, no payment row.
        $full = $this->bill($token, [$this->line($dolo)], ['payment_mode' => 'upi', 'received_paise' => 11200])
            ->assertCreated()->json('bill');
        $this->assertSame(['upi', 11200, 0, 11200, 'upi'],
            [$full['payment_mode'], $full['paid_paise'], $full['balance_paise'], $full['received_paise'], $full['received_mode']]);
        // Nothing received on a cash bill = all on account.
        $none = $this->bill($token, [$this->line($dolo)], ['received_paise' => 0, 'party_id' => $party])
            ->assertCreated()->json('bill');
        $this->assertSame(['credit', 0, 11200, null], [$none['payment_mode'], $none['paid_paise'], $none['balance_paise'], $none['received_mode']]);
        $this->assertSame(0, PartyPayment::count());
    }

    public function test_cancelling_takes_the_counter_payment_with_it_but_not_later_collections(): void
    {
        $token = $this->token();
        $this->shop($token);
        $dolo = $this->stock($token);
        $party = $this->party($token);

        $bill = $this->bill($token, [$this->line($dolo, 2)], ['received_paise' => 10000, 'party_id' => $party])->json('bill');
        $later = $this->withToken($token)->postJson('/api/v1/payments', [
            'id' => (string) Str::uuid(), 'party_id' => $party, 'direction' => 'in', 'mode' => 'cash',
            'amount_paise' => 2000, 'bill_id' => $bill['id'],
        ])->assertCreated()->json('payment.id');

        $this->withToken($token)->postJson("/api/v1/bills/{$bill['id']}/cancel")
            ->assertStatus(422)->assertJsonPath('error', 'has_payments');
        $this->withToken($token)->postJson("/api/v1/payments/$later/cancel")->assertOk();

        $this->withToken($token)->postJson("/api/v1/bills/{$bill['id']}/cancel")->assertOk()
            ->assertJsonPath('bill.status', 'cancelled')
            ->assertJsonPath('bill.balance_paise', 0)
            ->assertJsonPath('bill.paid_paise', 0);
        $counter = PartyPayment::where('bill_id', $bill['id'])->where('at_billing', true)->sole();
        $this->assertSame(['cancelled', 'Bill cancelled'], [$counter->status, $counter->cancel_reason]);
        $this->withToken($token)->getJson("/api/v1/parties/$party")->assertJsonPath('party.balance_paise', 0);
    }

    public function test_bill_list_shows_what_is_due_and_filters_pending_bills(): void
    {
        $token = $this->token();
        $this->shop($token);
        $dolo = $this->stock($token);
        $party = $this->party($token);

        $this->bill($token, [$this->line($dolo)])->assertCreated();                                                    // paid
        $part = $this->bill($token, [$this->line($dolo, 2)], ['received_paise' => 10000, 'party_id' => $party])->json('bill.id'); // 12400 due
        $credit = $this->bill($token, [$this->line($dolo)], ['payment_mode' => 'credit', 'party_id' => $party])->json('bill.id'); // 11200 due
        $cancelled = $this->bill($token, [$this->line($dolo)], ['payment_mode' => 'credit', 'party_id' => $party])->json('bill.id');
        $this->withToken($token)->postJson("/api/v1/bills/$cancelled/cancel")->assertOk();

        DB::enableQueryLog();
        $list = $this->withToken($token)->getJson('/api/v1/bills')->assertOk();
        $this->assertLessThan(12, count(DB::getQueryLog()), 'no query per bill');
        DB::disableQueryLog();
        $this->assertSame([2, 23600], [$list->json('summary.due_count'), $list->json('summary.due_paise')]);
        $byId = collect($list->json('data'))->keyBy('id');
        $this->assertSame([10000, 12400], [$byId[$part]['paid_paise'], $byId[$part]['balance_paise']]);
        $this->assertSame([0, 11200], [$byId[$credit]['paid_paise'], $byId[$credit]['balance_paise']]);
        $this->assertSame(0, $byId[$cancelled]['balance_paise']);

        $due = $this->withToken($token)->getJson('/api/v1/bills?due=1')->assertOk();
        $this->assertEqualsCanonicalizing([$part, $credit], array_column($due->json('data'), 'id'));
    }
}
