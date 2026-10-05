<?php

namespace Tests\Feature\Concerns;

use App\Models\Batch;
use App\Models\User;
use App\Rules\Gstin;
use App\Services\EntitlementService;
use Database\Seeders\DatabaseSeeder;
use Illuminate\Support\Carbon;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;

/**
 * Shared setup for the accounting API tests: a Maharashtra shop, stock
 * pushed like a device, bills, parties and valid GSTINs.
 */
trait AccountingHelpers
{
    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(DatabaseSeeder::class);
        Carbon::setTestNow('2026-10-05 11:30:00');
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    protected function token(?User $user = null): string
    {
        $user ??= User::factory()->create(['is_admin' => false]);
        app(EntitlementService::class)->ensureTrial($user);

        return $user->issueToken('test');
    }

    /** A valid GSTIN for a state (the check character worked out). */
    protected function gstin(string $state, string $pan = 'AABCU9603R', string $entity = '1'): string
    {
        $first = $state.$pan.$entity.'Z';

        return $first.Gstin::checkChar($first);
    }

    /** The shop's invoice details: Maharashtra (27), prefix MED. */
    protected function shop(string $token, array $details = []): array
    {
        return $this->withToken($token)->patchJson('/api/v1/shops/current', $details + [
            'legal_name' => 'Sahay Medicals Pvt Ltd',
            'gstin' => '27AAPFU0939F1ZV',
            'invoice_prefix' => 'med',
            'address' => '12 Station Road, Pune',
        ])->assertOk()->json('shop');
    }

    protected function push(string $token, array $mutations, string $device = 'phone'): TestResponse
    {
        return $this->withToken($token)->postJson('/api/v1/sync/push', [
            'device_id' => $device,
            'mutations' => array_map(fn ($m) => $m + ['mutation_id' => (string) Str::uuid(), 'op' => 'upsert'], $mutations),
        ])->assertOk();
    }

    /** @return array{product: string, batch: string} a product with one batch of $qty units */
    protected function stock(string $token, array $product = [], array $batch = [], int $qty = 20): array
    {
        $p = (string) Str::uuid();
        $b = (string) Str::uuid();
        $this->push($token, [
            ['table' => 'products', 'id' => $p, 'data' => $product + ['name' => 'Dolo 650', 'unit' => 'Strips', 'hsn' => '3004', 'gst_rate_bp' => 1200]],
            ['table' => 'batches', 'id' => $b, 'data' => $batch + ['product_id' => $p, 'batch_no' => 'B1', 'expiry_date' => '2027-10-31', 'mrp_paise' => 11200, 'purchase_rate_paise' => 7000]],
            ['table' => 'stock_movements', 'id' => (string) Str::uuid(), 'data' => [
                'batch_id' => $b, 'delta_units' => $qty, 'reason' => 'opening', 'occurred_at' => now()->toIso8601String(),
            ]],
        ]);

        return ['product' => $p, 'batch' => $b];
    }

    protected function line(array $stock, int $qty = 1, array $extra = []): array
    {
        $batch = Batch::withTrashed()->findOrFail($stock['batch']);

        return $extra + [
            'batch_id' => $stock['batch'],
            'qty_units' => $qty,
            'mrp_paise' => (int) $batch->mrp_paise,
            'batch_version' => (int) $batch->edit_version,
        ];
    }

    protected function bill(string $token, array $lines, array $extra = []): TestResponse
    {
        return $this->withToken($token)->postJson('/api/v1/bills', $extra + [
            'id' => (string) Str::uuid(),
            'device_id' => 'phone',
            'payment_mode' => 'cash',
            'lines' => $lines,
        ]);
    }

    /** Creates a party and returns its id. */
    protected function party(string $token, array $data = []): string
    {
        return $this->withToken($token)->postJson('/api/v1/parties', $data + ['type' => 'customer', 'name' => 'Ramesh Kumar'])
            ->assertCreated()->json('party.id');
    }

    protected function supplier(string $token, array $data = []): string
    {
        return $this->party($token, $data + ['type' => 'supplier', 'name' => 'Pune Pharma Distributors', 'gstin' => $this->gstin('27')]);
    }

    protected function qty(string $batchId): int
    {
        return (int) Batch::withTrashed()->findOrFail($batchId)->qty_units;
    }
}
