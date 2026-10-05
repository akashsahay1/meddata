<?php

namespace Tests\Feature;

use App\Models\Party;
use App\Models\Shop;
use App\Models\User;
use Database\Seeders\DatabaseSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

class AccountingAdminTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(DatabaseSeeder::class);
        $this->actingAs(User::where('is_admin', true)->firstOrFail());
    }

    public function test_parties_list_and_view_are_read_only(): void
    {
        $owner = User::create(['name' => 'Owner', 'email' => 'owner@example.com', 'password' => 'secret-password']);
        $shop = Shop::create(['owner_user_id' => $owner->id, 'name' => 'Sahay Medicals', 'state_code' => '27']);
        $party = Party::forceCreate([
            'id' => (string) Str::uuid(), 'shop_id' => $shop->id, 'type' => 'supplier', 'name' => 'Pune Pharma Distributors',
            'name_norm' => 'pune pharma distributors', 'gstin' => '27AAPFU0939F1ZV', 'state_code' => '27',
            'opening_balance_paise' => -125000,
        ]);
        $gone = Party::forceCreate([
            'id' => (string) Str::uuid(), 'shop_id' => $shop->id, 'type' => 'customer', 'name' => 'Old Customer',
            'name_norm' => 'old customer',
        ]);
        $gone->delete();

        $this->get('/parties')
            ->assertOk()
            ->assertSee('Pune Pharma Distributors')
            ->assertSee('Sahay Medicals')
            ->assertSee('₹1,250.00 to pay', false);

        $this->get("/parties/{$party->id}")
            ->assertOk()
            ->assertSee('27AAPFU0939F1ZV')
            ->assertSee('27 - Maharashtra')
            ->assertSee('₹1,250.00 to pay', false);
        $this->get("/parties/{$gone->id}")->assertOk()->assertSee('Old Customer');

        $this->get('/parties/create')->assertNotFound();
        $this->get("/parties/{$party->id}/edit")->assertNotFound();
    }
}
