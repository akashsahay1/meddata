<?php

namespace Tests\Feature;

use App\Models\Customer;
use App\Models\Medicine;
use App\Models\Store;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class AdminPanelSmokeTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(\Database\Seeders\DatabaseSeeder::class);
    }

    private function admin(): User
    {
        return User::where('is_admin', true)->firstOrFail();
    }

    public function test_login_page_renders(): void
    {
        $this->get('/admin/login')
            ->assertStatus(200)
            ->assertSee('Meddata');
    }

    public function test_all_resource_index_pages_render(): void
    {
        $this->actingAs($this->admin());

        $indexes = [
            '/admin/customers',
            '/admin/stores',
            '/admin/medicines',
            '/admin/plans',
            '/admin/entitlements',
            '/admin/devices',
            '/admin/app-settings',
            '/admin/backups',
            '/admin/purchase-logs',
            '/admin/users',
        ];

        foreach ($indexes as $url) {
            $this->get($url)->assertStatus(200);
        }
    }

    public function test_all_resource_create_pages_render(): void
    {
        $this->actingAs($this->admin());

        $creates = [
            '/admin/customers/create',
            '/admin/stores/create',
            '/admin/medicines/create',
            '/admin/plans/create',
            '/admin/devices/create',
            '/admin/app-settings/create',
            '/admin/backups/create',
            '/admin/purchase-logs/create',
            '/admin/users/create',
        ];

        foreach ($creates as $url) {
            $this->get($url)->assertStatus(200);
        }
    }

    public function test_edit_pages_render_for_seeded_records(): void
    {
        $this->actingAs($this->admin());

        $customer = Customer::first();
        $store = Store::first();
        $medicine = Medicine::first();

        $this->get("/admin/customers/{$customer->id}/edit")->assertStatus(200);
        $this->get("/admin/stores/{$store->id}/edit")->assertStatus(200);
        $this->get("/admin/medicines/{$medicine->id}/edit")->assertStatus(200);
    }

    public function test_demo_data_seeded(): void
    {
        $this->assertSame(30, Customer::count());
        $this->assertSame(40, Store::count());
        $this->assertSame(120, Medicine::count());
    }
}
