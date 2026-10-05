<?php

namespace Tests\Feature;

use App\Filament\Resources\Bills\Pages\ViewBill;
use App\Filament\Resources\Bills\RelationManagers\ItemsRelationManager;
use App\Filament\Resources\Shops\Pages\ViewShop;
use App\Models\Batch;
use App\Models\Bill;
use App\Models\Product;
use App\Models\Shop;
use App\Models\StockMovement;
use App\Models\User;
use App\Services\BillingService;
use Database\Seeders\DatabaseSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\TestCase;

class BillingAdminTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(DatabaseSeeder::class);
        $this->actingAs(User::where('is_admin', true)->firstOrFail());
    }

    private function shopWithBill(): array
    {
        $owner = User::create(['name' => 'Owner', 'email' => 'owner@example.com', 'password' => 'secret-password']);
        $shop = Shop::create(['owner_user_id' => $owner->id, 'name' => 'Sahay Medicals', 'state_code' => '27']);
        $product = Product::create([
            'id' => (string) Str::uuid(), 'shop_id' => $shop->id, 'version' => 1, 'edit_version' => 1,
            'name' => 'Dolo 650', 'name_norm' => 'dolo 650', 'hsn' => '3004', 'gst_rate_bp' => 500,
        ]);
        $batch = Batch::create([
            'id' => (string) Str::uuid(), 'shop_id' => $shop->id, 'version' => 2, 'edit_version' => 2,
            'product_id' => $product->id, 'batch_no' => 'B77', 'expiry_date' => now()->addYear()->toDateString(),
            'mrp_paise' => 3000, 'qty_units' => 10,
        ]);
        StockMovement::create([
            'id' => (string) Str::uuid(), 'shop_id' => $shop->id, 'version' => 3, 'batch_id' => $batch->id,
            'product_id' => $product->id, 'delta_units' => 10, 'reason' => 'opening', 'occurred_at' => now(),
        ]);

        [$bill] = app(BillingService::class)->create($shop, $owner, [
            'id' => (string) Str::uuid(),
            'payment_mode' => 'upi',
            'customer_name' => 'Ramesh Kumar',
            'lines' => [['batch_id' => $batch->id, 'qty_units' => 2, 'mrp_paise' => 3000, 'batch_version' => 2]],
        ]);

        return [$shop, $bill];
    }

    public function test_bills_list_and_view_are_read_only(): void
    {
        /** @var Bill $bill */
        [, $bill] = $this->shopWithBill();

        $this->get('/bills')
            ->assertOk()
            ->assertSee('INV/26-27/000001', false)
            ->assertSee('Sahay Medicals')
            ->assertSee('Ramesh Kumar');

        $this->get("/bills/{$bill->id}")
            ->assertOk()
            ->assertSee('INV/26-27/000001', false)
            ->assertSee('Ramesh Kumar')
            ->assertSee('27 - Maharashtra');

        Livewire::test(ItemsRelationManager::class, ['ownerRecord' => $bill, 'pageClass' => ViewBill::class])
            ->assertSee('Dolo 650')
            ->assertSee('B77')
            ->assertSee('5%');

        $this->get('/bills/create')->assertNotFound();
        $this->get("/bills/{$bill->id}/edit")->assertNotFound();
    }

    public function test_admin_can_edit_a_shops_invoice_details(): void
    {
        [$shop] = $this->shopWithBill();

        Livewire::test(ViewShop::class, ['record' => $shop->getRouteKey()])
            ->callAction('editInvoiceDetails', data: ['gstin' => 'not-a-gstin', 'invoice_prefix' => 'TOOLONG'])
            ->assertHasActionErrors(['gstin', 'invoice_prefix']);

        Livewire::test(ViewShop::class, ['record' => $shop->getRouteKey()])
            ->callAction('editInvoiceDetails', data: [
                'legal_name' => 'Sahay Medicals Pvt Ltd',
                'gstin' => '27AAPFU0939F1ZV',
                'invoice_prefix' => 'MED',
                'drug_license_no' => 'MH-20B-1',
                'default_gst_rate_bp' => 1200,
            ])
            ->assertHasNoActionErrors();

        $shop->refresh();
        $this->assertSame(['Sahay Medicals Pvt Ltd', '27AAPFU0939F1ZV', '27', 'MED', 'MH-20B-1', 1200],
            [$shop->legal_name, $shop->gstin, $shop->state_code, $shop->invoice_prefix, $shop->drug_license_no, $shop->default_gst_rate_bp]);

        $this->get("/shops/{$shop->id}")
            ->assertOk()
            ->assertSee('Sahay Medicals Pvt Ltd')
            ->assertSee('12%');
    }
}
