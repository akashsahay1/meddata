<?php

namespace Tests\Feature;

use App\Filament\Resources\Shops\Pages\ViewShop;
use App\Filament\Resources\Shops\RelationManagers\DevicesRelationManager;
use App\Filament\Resources\Shops\RelationManagers\ProductsRelationManager;
use App\Filament\Widgets\ProductCategoryChart;
use App\Filament\Widgets\RecentShops;
use App\Filament\Widgets\ShopGrowthChart;
use App\Filament\Widgets\StatsOverview;
use App\Models\Batch;
use App\Models\MedicineMaster;
use App\Models\Product;
use App\Models\Shop;
use App\Models\ShopDevice;
use App\Models\User;
use Database\Seeders\DatabaseSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\TestCase;

class AdminPanelSmokeTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(DatabaseSeeder::class);
    }

    private function admin(): User
    {
        return User::where('is_admin', true)->firstOrFail();
    }

    /** A shop with a device, two products (one soft-deleted) and batches, plus a master row. */
    private function seedShop(): Shop
    {
        $owner = User::create([
            'name' => 'Shop Owner',
            'email' => 'owner@example.com',
            'password' => 'secret-password',
        ]);

        $shop = Shop::create(['owner_user_id' => $owner->id, 'name' => 'Sahay Medicals', 'phone' => '9999999999']);

        ShopDevice::create([
            'shop_id' => $shop->id,
            'user_id' => $owner->id,
            'device_uuid' => 'device-1',
            'name' => 'Counter phone',
            'platform' => 'android',
            'app_version' => '1.0.0',
            'last_sync_at' => now(),
        ]);

        $product = Product::create([
            'id' => (string) Str::uuid(),
            'shop_id' => $shop->id,
            'version' => 1,
            'name' => 'Paracetamol 500',
            'name_norm' => 'paracetamol 500',
            'category' => 'Analgesic',
        ]);
        Batch::create([
            'id' => (string) Str::uuid(),
            'shop_id' => $shop->id,
            'version' => 2,
            'product_id' => $product->id,
            'expiry_date' => now()->subDay()->toDateString(),
            'qty_units' => 20,
        ]);
        Batch::create([
            'id' => (string) Str::uuid(),
            'shop_id' => $shop->id,
            'version' => 4,
            'product_id' => $product->id,
            'expiry_date' => now()->subDay()->toDateString(),
            'qty_units' => 100,
        ])->delete();

        $deleted = Product::create([
            'id' => (string) Str::uuid(),
            'shop_id' => $shop->id,
            'version' => 3,
            'name' => 'Old product',
            'name_norm' => 'old product',
        ]);
        $deleted->delete();

        MedicineMaster::create([
            'name' => 'Paracetamol 500',
            'name_norm' => 'paracetamol 500',
            'source' => 'shop',
            'created_by_shop_id' => $shop->id,
        ]);

        return $shop;
    }

    public function test_login_page_renders(): void
    {
        $this->get('/')
            ->assertStatus(200)
            ->assertSee('Meddata');
    }

    public function test_dashboard_renders_with_shop_data(): void
    {
        $this->seedShop();
        $this->actingAs($this->admin());

        $this->get('/dashboard')->assertStatus(200);

        // Dashboard widgets are lazy-loaded, so render each one directly.
        Livewire::test(StatsOverview::class)
            ->assertSee('1 expired in stock')
            ->assertSee('Shops');
        Livewire::test(ShopGrowthChart::class)->assertSuccessful();
        Livewire::test(ProductCategoryChart::class)->assertSuccessful();
        Livewire::test(RecentShops::class)
            ->assertSee('Sahay Medicals')
            ->assertSee('owner@example.com')
            ->assertDontSee('Old product');
    }

    public function test_dashboard_renders_empty(): void
    {
        $this->actingAs($this->admin());

        $this->get('/dashboard')->assertStatus(200);
        Livewire::test(StatsOverview::class)->assertSee('0 expired in stock');
        Livewire::test(ShopGrowthChart::class)->assertSuccessful();
        Livewire::test(ProductCategoryChart::class)->assertSuccessful();
        Livewire::test(RecentShops::class)->assertSuccessful();
    }

    public function test_all_resource_index_pages_render(): void
    {
        $this->seedShop();
        $this->actingAs($this->admin());

        $indexes = [
            '/shops',
            '/medicine-master',
            '/plans',
            '/entitlements',
            '/devices',
            '/app-settings',
            '/backups',
            '/purchase-logs',
            '/coupons',
            '/payments',
            '/users',
        ];

        foreach ($indexes as $url) {
            $this->get($url)->assertStatus(200);
        }
    }

    public function test_shop_pages_show_real_data(): void
    {
        $shop = $this->seedShop();
        $this->actingAs($this->admin());

        $this->get('/shops')
            ->assertStatus(200)
            ->assertSee('Sahay Medicals')
            ->assertSee('owner@example.com');

        $this->get("/shops/{$shop->id}")
            ->assertStatus(200)
            ->assertSee('Sahay Medicals')
            ->assertSee('owner@example.com');

        // Relation managers are lazy-loaded, so render them directly.
        Livewire::test(DevicesRelationManager::class, ['ownerRecord' => $shop, 'pageClass' => ViewShop::class])
            ->assertSee('Counter phone')
            ->assertSee('1.0.0');
        Livewire::test(ProductsRelationManager::class, ['ownerRecord' => $shop, 'pageClass' => ViewShop::class])
            ->assertSee('Paracetamol 500')
            ->assertDontSee('Old product')
            ->assertCanSeeTableRecords(Product::where('name', 'Paracetamol 500')->get())
            ->assertTableColumnStateSet('batches_sum_qty_units', 20, Product::where('name', 'Paracetamol 500')->first())
            ->assertTableColumnStateSet('batches_count', 1, Product::where('name', 'Paracetamol 500')->first());

        // Read-only: no create/edit routes.
        $this->get('/shops/create')->assertStatus(404);
        $this->get("/shops/{$shop->id}/edit")->assertStatus(404);
    }

    public function test_medicine_master_list_searches(): void
    {
        $this->seedShop();
        $this->actingAs($this->admin());

        $this->get('/medicine-master?search=parac')
            ->assertStatus(200)
            ->assertSee('Paracetamol 500');

        $this->get('/medicine-master/create')->assertStatus(404);
    }

    public function test_all_resource_create_pages_render(): void
    {
        $this->actingAs($this->admin());

        $creates = [
            '/plans/create',
            '/devices/create',
            '/app-settings/create',
            '/backups/create',
            '/purchase-logs/create',
            '/coupons/create',
            '/users/create',
        ];

        foreach ($creates as $url) {
            $this->get($url)->assertStatus(200);
        }
    }
}
