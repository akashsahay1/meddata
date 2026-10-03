<?php

namespace Tests\Feature;

use App\Models\Batch;
use App\Models\PriceChange;
use App\Models\Product;
use App\Models\StockMovement;
use App\Models\User;
use App\Services\EntitlementService;
use Database\Seeders\DatabaseSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

class SyncApiTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(DatabaseSeeder::class);
    }

    private function token(?User $user = null): string
    {
        $user ??= User::factory()->create(['is_admin' => false]);
        // New users get a trial (premium) so plan limits don't interfere.
        app(EntitlementService::class)->ensureTrial($user);

        return $user->issueToken('test');
    }

    private function push(string $token, array $mutations, string $device = 'dev-a')
    {
        return $this->withToken($token)->postJson('/api/v1/sync/push', [
            'device_id' => $device,
            'mutations' => $mutations,
        ]);
    }

    private function m(string $table, string $id, array $data, ?int $base = null, string $op = 'upsert'): array
    {
        return array_filter([
            'mutation_id' => (string) Str::uuid(),
            'table' => $table,
            'op' => $op,
            'id' => $id,
            'base_version' => $base,
            'data' => $data,
        ], fn ($v) => $v !== null);
    }

    /** Creates a product + batch and returns [productId, batchId, batchVersion]. */
    private function seedBatch(string $token, int $mrp = 3000): array
    {
        $p = (string) Str::uuid();
        $b = (string) Str::uuid();
        $res = $this->push($token, [
            $this->m('products', $p, ['name' => 'Paracetamol 500', 'unit' => 'Tablets', 'pack_size' => 10]),
            $this->m('batches', $b, ['product_id' => $p, 'batch_no' => 'B1', 'expiry_date' => '2027-10-31', 'mrp_paise' => $mrp]),
        ])->assertOk();

        return [$p, $b, $res->json('results.1.version')];
    }

    public function test_push_then_pull_round_trip_and_cursor_paging(): void
    {
        $token = $this->token();
        [$p, $b] = $this->seedBatch($token);

        $all = $this->withToken($token)->getJson('/api/v1/sync/pull?since=0')->assertOk();
        $this->assertSame($p, $all->json('changes.products.0.id'));
        $this->assertSame('paracetamol 500', $all->json('changes.products.0.name_norm'));
        $this->assertSame($b, $all->json('changes.batches.0.id'));
        $this->assertSame('2027-10-31', $all->json('changes.batches.0.expiry_date'));
        $this->assertFalse($all->json('has_more'));

        // Page size 1: two pages, cursor moves forward, nothing skipped.
        $first = $this->withToken($token)->getJson('/api/v1/sync/pull?since=0&limit=1')->assertOk();
        $this->assertTrue($first->json('has_more'));
        $second = $this->withToken($token)->getJson('/api/v1/sync/pull?since='.$first->json('next').'&limit=1');
        $this->assertSame($b, $second->json('changes.batches.0.id'));
        $this->assertSame($all->json('next'), $second->json('next'));

        $this->withToken($token)->getJson('/api/v1/sync/status')
            ->assertJsonPath('server_version', $all->json('next'));
    }

    public function test_resending_a_mutation_is_idempotent(): void
    {
        $token = $this->token();
        [, $b] = $this->seedBatch($token);
        $move = $this->m('stock_movements', (string) Str::uuid(), [
            'batch_id' => $b, 'delta_units' => 100, 'reason' => 'opening', 'occurred_at' => now()->toIso8601String(),
        ]);

        $one = $this->push($token, [$move])->json('results.0');
        $two = $this->push($token, [$move])->json('results.0');

        $this->assertSame($one, $two);
        $this->assertSame(1, StockMovement::count());
        $this->assertSame(100, (int) Batch::find($b)->qty_units);
    }

    public function test_batch_qty_is_derived_from_movements_and_can_go_negative(): void
    {
        $token = $this->token();
        [, $b] = $this->seedBatch($token);
        $mv = fn (int $d, string $r) => $this->m('stock_movements', (string) Str::uuid(), [
            'batch_id' => $b, 'delta_units' => $d, 'reason' => $r, 'occurred_at' => now()->toIso8601String(),
        ]);

        $this->push($token, [$mv(10, 'opening')], 'dev-a');
        // Two devices both sell 8 from the same 10 while out of sync.
        $this->push($token, [$mv(-8, 'sale')], 'dev-a');
        $last = $this->push($token, [$mv(-8, 'sale')], 'dev-b')->json('results.0');

        $this->assertSame(-6, $last['batch_qty_units']);
        $this->assertTrue($last['negative_stock']);
        $this->assertSame(-6, (int) Batch::find($b)->qty_units);
        $this->assertSame(-6, (int) StockMovement::where('batch_id', $b)->sum('delta_units'));

        // Clients cannot set qty directly, and movements cannot be deleted.
        $ver = (int) Batch::find($b)->version;
        $this->push($token, [$this->m('batches', $b, ['qty_units' => 999], $ver)]);
        $this->assertSame(-6, (int) Batch::find($b)->qty_units);
        $this->push($token, [$this->m('stock_movements', StockMovement::first()->id, [], null, 'delete')])
            ->assertJsonPath('results.0.reason', 'immutable');
    }

    public function test_concurrent_price_edit_conflicts_instead_of_overwriting(): void
    {
        $token = $this->token();
        [, $b, $v] = $this->seedBatch($token, 3000);

        // Phone changes MRP ₹30 -> ₹32 based on the version it saw.
        $this->push($token, [$this->m('batches', $b, ['mrp_paise' => 3200], $v)], 'phone')
            ->assertJsonPath('results.0.status', 'ok');

        // Windows, still on the old version, tries ₹31: must NOT overwrite.
        $res = $this->push($token, [$this->m('batches', $b, ['mrp_paise' => 3100], $v)], 'windows');
        $res->assertJsonPath('results.0.status', 'conflict')
            ->assertJsonPath('results.0.reason', 'version_mismatch')
            ->assertJsonPath('results.0.row.mrp_paise', 3200);
        $this->assertSame(3200, (int) Batch::find($b)->mrp_paise);

        // Audit trail records the accepted change with the device.
        $change = PriceChange::sole();
        $this->assertSame(['mrp_paise', 3000, 3200, 'phone'],
            [$change->field, (int) $change->old_paise, (int) $change->new_paise, $change->device_id]);

        // An edit with no base_version is never applied blindly either.
        $this->push($token, [$this->m('batches', $b, ['mrp_paise' => 1], null)])
            ->assertJsonPath('results.0.status', 'conflict');
    }

    public function test_delete_tombstones_product_and_its_batches(): void
    {
        $token = $this->token();
        [$p, $b] = $this->seedBatch($token);
        $since = $this->withToken($token)->getJson('/api/v1/sync/status')->json('server_version');
        $pv = (int) Product::find($p)->version;

        $this->push($token, [$this->m('products', $p, [], $pv, 'delete')])->assertJsonPath('results.0.status', 'ok');

        $pull = $this->withToken($token)->getJson('/api/v1/sync/pull?since='.$since)->assertOk();
        $this->assertNotNull($pull->json('changes.products.0.deleted_at'));
        $this->assertNotNull($pull->json('changes.batches.0.deleted_at'));
        $this->assertSame($b, $pull->json('changes.batches.0.id'));
    }

    public function test_invalid_rows_are_rejected_with_reasons(): void
    {
        $token = $this->token();
        $res = $this->push($token, [
            $this->m('products', (string) Str::uuid(), ['unit' => 'Tablets']),
            $this->m('batches', (string) Str::uuid(), ['product_id' => (string) Str::uuid(), 'expiry_date' => '2027-01-01']),
            $this->m('orders', (string) Str::uuid(), []),
        ]);
        $res->assertJsonPath('results.0.reason', 'invalid')
            ->assertJsonPath('results.1.reason', 'product_not_found')
            ->assertJsonPath('results.2.reason', 'unknown_table');
    }

    public function test_shops_are_isolated(): void
    {
        $alice = $this->token();
        $bob = $this->token();
        [$p, $b, $v] = $this->seedBatch($alice);

        // Bob sees nothing of Alice's shop.
        $pull = $this->withToken($bob)->getJson('/api/v1/sync/pull?since=0')->assertOk();
        $this->assertSame([], $pull->json('changes.products'));
        $this->assertSame([], $pull->json('changes.batches'));
        $this->withToken($bob)->getJson('/api/v1/shops/current')->assertJsonPath('has_data', false);

        // Bob cannot edit, delete, or move stock in Alice's rows.
        $this->push($bob, [
            $this->m('batches', $b, ['mrp_paise' => 1], $v),
            $this->m('products', $p, [], 1, 'delete'),
            $this->m('stock_movements', (string) Str::uuid(), [
                'batch_id' => $b, 'delta_units' => -5, 'reason' => 'sale', 'occurred_at' => now()->toIso8601String(),
            ]),
            $this->m('batches', (string) Str::uuid(), ['product_id' => $p, 'expiry_date' => '2027-01-01']),
        ])->assertJsonPath('results.0.reason', 'id_conflict')
            ->assertJsonPath('results.1.reason', 'id_conflict')
            ->assertJsonPath('results.2.reason', 'batch_not_found')
            ->assertJsonPath('results.3.reason', 'product_not_found');

        $this->assertSame(3000, (int) Batch::find($b)->mrp_paise);
        $this->assertSame(0, StockMovement::count());
        $this->withToken($alice)->getJson('/api/v1/shops/current')->assertJsonPath('has_data', true);
    }

    public function test_sync_requires_auth(): void
    {
        $this->getJson('/api/v1/sync/pull')->assertStatus(401);
        $this->postJson('/api/v1/sync/push', [])->assertStatus(401);
    }
}
