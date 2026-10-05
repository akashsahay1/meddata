<?php

namespace Tests\Feature;

use App\Models\Party;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\Feature\Concerns\AccountingHelpers;
use Tests\TestCase;

class PartyApiTest extends TestCase
{
    use AccountingHelpers;
    use RefreshDatabase;

    public function test_create_list_search_update_and_delete_a_party(): void
    {
        $token = $this->token();
        $karnataka = $this->gstin('29');

        $res = $this->withToken($token)->postJson('/api/v1/parties', [
            'type' => 'customer',
            'name' => '  Lakshmi Clinic ',
            'phone' => '98450 12345',
            'gstin' => strtolower($karnataka),
            'address' => 'MG Road, Bengaluru',
            'opening_balance_paise' => 150000,
            'notes' => 'Pays monthly',
        ])->assertCreated();
        $party = $res->json('party');
        $this->assertSame('Lakshmi Clinic', $party['name']);
        $this->assertSame($karnataka, $party['gstin']);
        // The state comes from the GSTIN.
        $this->assertSame('29', $party['state_code']);
        $this->assertSame('Karnataka', $party['state_name']);
        $this->assertSame(150000, $party['opening_balance_paise']);
        $this->assertSame(150000, $party['balance_paise']);

        $supplier = $this->supplier($token);
        $this->party($token, ['name' => 'Asha', 'phone' => '9000000001', 'type' => 'both']);

        $list = $this->withToken($token)->getJson('/api/v1/parties')->assertOk();
        $this->assertSame(['Asha', 'Lakshmi Clinic', 'Pune Pharma Distributors'], array_column($list->json('data'), 'name'));
        $customers = $this->withToken($token)->getJson('/api/v1/parties?type=customer')->json('data');
        $this->assertSame(['Asha', 'Lakshmi Clinic'], array_column($customers, 'name'));
        $suppliers = $this->withToken($token)->getJson('/api/v1/parties?type=supplier')->json('data');
        $this->assertSame(['Asha', 'Pune Pharma Distributors'], array_column($suppliers, 'name'));
        // Search by name, phone or GSTIN.
        $this->assertSame(['Lakshmi Clinic'], array_column($this->withToken($token)->getJson('/api/v1/parties?q=lakSHMI')->json('data'), 'name'));
        $this->assertSame(['Lakshmi Clinic'], array_column($this->withToken($token)->getJson('/api/v1/parties?q=12345')->json('data'), 'name'));
        $this->assertSame(['Lakshmi Clinic'], array_column($this->withToken($token)->getJson('/api/v1/parties?q='.substr($karnataka, 0, 6))->json('data'), 'name'));

        $this->withToken($token)->patchJson("/api/v1/parties/{$party['id']}", ['phone' => '', 'opening_balance_paise' => -5000])
            ->assertOk()
            ->assertJsonPath('party.phone', null)
            ->assertJsonPath('party.balance_paise', -5000)
            ->assertJsonPath('party.name', 'Lakshmi Clinic');

        // A party that is owed money can't be deleted; settled, it can.
        $this->withToken($token)->deleteJson("/api/v1/parties/{$party['id']}")
            ->assertStatus(422)->assertJsonPath('error', 'balance_not_zero');
        $this->withToken($token)->patchJson("/api/v1/parties/{$party['id']}", ['opening_balance_paise' => 0])->assertOk();
        $this->withToken($token)->deleteJson("/api/v1/parties/{$party['id']}")->assertOk();
        $this->withToken($token)->getJson("/api/v1/parties/{$party['id']}")->assertNotFound();
        $this->assertSame(2, count($this->withToken($token)->getJson('/api/v1/parties')->json('data')));
        $this->assertSoftDeleted('parties', ['id' => $party['id']]);
        $this->assertNotNull($supplier);
    }

    public function test_validation(): void
    {
        $token = $this->token();
        $this->withToken($token)->postJson('/api/v1/parties', [])
            ->assertStatus(422)->assertJsonValidationErrors(['type', 'name']);
        $this->withToken($token)->postJson('/api/v1/parties', [
            'type' => 'vendor', 'name' => 'X', 'gstin' => '27AAPFU0939F1ZX', 'phone' => 'call me', 'state_code' => '99',
        ])->assertStatus(422)->assertJsonValidationErrors(['type', 'gstin', 'phone', 'state_code']);
        // The state must match the GSTIN.
        $this->withToken($token)->postJson('/api/v1/parties', [
            'type' => 'supplier', 'name' => 'X', 'gstin' => $this->gstin('29'), 'state_code' => '27',
        ])->assertStatus(422)->assertJsonValidationErrors('state_code');
        // A state without a GSTIN is fine (unregistered party); a number becomes "07".
        $this->withToken($token)->postJson('/api/v1/parties', ['type' => 'customer', 'name' => 'Delhi walk-in', 'state_code' => 7])
            ->assertCreated()->assertJsonPath('party.state_code', '07');
        // One party per GSTIN.
        $this->supplier($token);
        $this->withToken($token)->postJson('/api/v1/parties', ['type' => 'supplier', 'name' => 'Same', 'gstin' => $this->gstin('27')])
            ->assertStatus(422)->assertJsonValidationErrors('gstin');
    }

    public function test_retry_with_the_same_id_returns_the_same_party(): void
    {
        $token = $this->token();
        $id = (string) Str::uuid();
        $first = $this->withToken($token)->postJson('/api/v1/parties', ['id' => $id, 'type' => 'customer', 'name' => 'Ramesh'])->assertCreated();
        $again = $this->withToken($token)->postJson('/api/v1/parties', ['id' => $id, 'type' => 'customer', 'name' => 'Ramesh'])->assertOk();
        $this->assertTrue($again->json('replayed'));
        $this->assertSame($first->json('party.id'), $again->json('party.id'));
        $this->assertSame(1, Party::count());
        // Another shop can't take that id.
        $this->withToken($this->token())->postJson('/api/v1/parties', ['id' => $id, 'type' => 'customer', 'name' => 'Other'])->assertStatus(422);
    }

    public function test_parties_are_shop_scoped(): void
    {
        $alice = $this->token();
        $bob = $this->token();
        $party = $this->party($alice);

        $this->assertSame([], $this->withToken($bob)->getJson('/api/v1/parties')->json('data'));
        $this->withToken($bob)->getJson("/api/v1/parties/$party")->assertNotFound();
        $this->withToken($bob)->getJson("/api/v1/parties/$party/ledger")->assertNotFound();
        $this->withToken($bob)->patchJson("/api/v1/parties/$party", ['name' => 'Hacked'])->assertNotFound();
        $this->withToken($bob)->deleteJson("/api/v1/parties/$party")->assertNotFound();
        $this->withToken($bob)->getJson('/api/v1/parties/not-a-uuid')->assertNotFound();
        $this->assertSame('Ramesh Kumar', Party::find($party)->name);

        // A bill can't use another shop's party either.
        $this->shop($bob);
        $dolo = $this->stock($bob);
        $this->bill($bob, [$this->line($dolo)], ['payment_mode' => 'credit', 'party_id' => $party])
            ->assertStatus(422)->assertJsonPath('error', 'party_not_found');
        $this->assertSame(20, $this->qty($dolo['batch']));
    }

    public function test_a_bill_takes_the_customers_details_and_a_party_with_bills_stays_a_customer(): void
    {
        $token = $this->token();
        $this->shop($token);
        $dolo = $this->stock($token);
        $kar = $this->gstin('29');
        $party = $this->party($token, ['name' => 'Lakshmi Clinic', 'phone' => '9845012345', 'gstin' => $kar, 'address' => 'MG Road']);

        $bill = $this->bill($token, [$this->line($dolo, 2)], ['payment_mode' => 'credit', 'party_id' => $party])
            ->assertCreated()->json('bill');
        $this->assertSame(['Lakshmi Clinic', '9845012345', $kar, '29', 'MG Road', true],
            [$bill['customer_name'], $bill['customer_phone'], $bill['customer_gstin'], $bill['place_of_supply'],
                $bill['customer_address'], $bill['is_inter_state']]);
        // Typed details win over the party's.
        $this->bill($token, [$this->line($dolo)], ['party_id' => $party, 'customer_name' => 'Dr Lakshmi'])
            ->assertCreated()->assertJsonPath('bill.customer_name', 'Dr Lakshmi');
        $this->assertSame(2, count($this->withToken($token)->getJson("/api/v1/bills?party_id=$party&from=2026-10-01")->json('data')));

        $this->withToken($token)->patchJson("/api/v1/parties/$party", ['type' => 'supplier'])
            ->assertStatus(422)->assertJsonValidationErrors('type');
        $this->withToken($token)->patchJson("/api/v1/parties/$party", ['type' => 'both'])->assertOk();

        // A supplier-only party can't be billed.
        $supplier = $this->supplier($token);
        $this->bill($token, [$this->line($dolo)], ['payment_mode' => 'credit', 'party_id' => $supplier])
            ->assertStatus(422)->assertJsonPath('error', 'party_not_found');
    }
}
