<?php

namespace Tests\Feature;

use App\Models\Batch;
use App\Models\StockMovement;
use App\Models\User;
use App\Services\EntitlementService;
use Database\Seeders\DatabaseSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

class ProfitReportApiTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(DatabaseSeeder::class);
        Carbon::setTestNow('2026-10-05 11:30:00'); // 17:00 in India
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    // ---- helpers ----------------------------------------------------------

    private function token(): string
    {
        $user = User::factory()->create(['is_admin' => false]);
        app(EntitlementService::class)->ensureTrial($user);
        $token = $user->issueToken('test');
        // Maharashtra shop with a GSTIN: intra-state bills (CGST + SGST).
        $this->withToken($token)->patchJson('/api/v1/shops/current', [
            'legal_name' => 'Sahay Medicals', 'gstin' => '27AAPFU0939F1ZV',
        ])->assertOk();

        return $token;
    }

    private function push(string $token, array $mutations): TestResponse
    {
        return $this->withToken($token)->postJson('/api/v1/sync/push', [
            'device_id' => 'phone',
            'mutations' => array_map(fn ($m) => $m + ['mutation_id' => (string) Str::uuid(), 'op' => 'upsert'], $mutations),
        ])->assertOk();
    }

    /** A product with one batch of 50 units; returns the batch id. */
    private function stock(string $token, string $name, int $mrp, int $rate, string $category = 'Pain Relief', int $gst = 500): string
    {
        $p = (string) Str::uuid();
        $b = (string) Str::uuid();
        $this->push($token, [
            ['table' => 'products', 'id' => $p, 'data' => ['name' => $name, 'unit' => 'Strips', 'category' => $category, 'gst_rate_bp' => $gst]],
            ['table' => 'batches', 'id' => $b, 'data' => [
                'product_id' => $p, 'batch_no' => 'B-'.$name, 'expiry_date' => '2027-12-31',
                'mrp_paise' => $mrp, 'purchase_rate_paise' => $rate,
            ]],
            ['table' => 'stock_movements', 'id' => (string) Str::uuid(), 'data' => [
                'batch_id' => $b, 'delta_units' => 50, 'reason' => 'opening', 'occurred_at' => now()->toIso8601String(),
            ]],
        ]);

        return $b;
    }

    /** @param  array<string, int>  $lines  batch id => qty */
    private function bill(string $token, array $lines, int $discountBp = 0): string
    {
        $id = (string) Str::uuid();
        $this->withToken($token)->postJson('/api/v1/bills', [
            'id' => $id,
            'payment_mode' => 'cash',
            'lines' => array_map(function (string $batch, int $qty) use ($discountBp) {
                $b = Batch::findOrFail($batch);

                return [
                    'batch_id' => $batch, 'qty_units' => $qty, 'mrp_paise' => (int) $b->mrp_paise,
                    'batch_version' => (int) $b->edit_version, 'discount_bp' => $discountBp,
                ];
            }, array_keys($lines), $lines),
        ])->assertCreated();

        return $id;
    }

    private function report(string $token, string $from = '2026-10-01', string $to = '2026-10-31'): TestResponse
    {
        return $this->withToken($token)->getJson("/api/v1/reports/profit?from={$from}&to={$to}");
    }

    // ---- maths ----------------------------------------------------------------

    public function test_profit_is_taxable_value_minus_purchase_cost(): void
    {
        $token = $this->token();
        // MRP ₹30 incl. 5% GST, bought at ₹20 (excl. GST).
        $dolo = $this->stock($token, 'Dolo 650', 3000, 2000);
        // MRP ₹112.50 incl. 12% GST, bought at ₹70, sold at 10% off.
        $syrup = $this->stock($token, 'Cough Syrup', 11250, 7000, 'Cough & Cold', 1200);

        $this->bill($token, [$dolo => 2]);
        $this->bill($token, [$syrup => 3], 1000);

        $res = $this->report($token)->assertOk();

        // Dolo: 2 x ₹30 = ₹60.00 incl. GST; CGST = SGST = 6000 x 2.5 / 105 = 142.86 -> 143,
        // taxable 6000 - 286 = 5714; cost 2 x 2000 = 4000; profit 1714.
        // Syrup: 3 x 11250 = 33750, -10% = 30375; CGST = SGST = 30375 x 6 / 112 = 1627.23 -> 1627,
        // taxable 27121; cost 3 x 7000 = 21000; profit 6121.
        $totals = $res->json('totals');
        $this->assertSame(5714 + 27121, $totals['revenue_paise']);
        $this->assertSame(6000 + 30375, $totals['sales_paise']);
        $this->assertSame(4000 + 21000, $totals['cost_paise']);
        $this->assertSame(1714 + 6121, $totals['profit_paise']);
        // 7835 / 32835 = 23.862% -> 2386 bp
        $this->assertSame(2386, $totals['margin_bp']);
        $this->assertSame(2, $totals['bills']);
        $this->assertSame(5, $totals['qty_units']);
        $this->assertSame(0, $totals['unknown_cost_revenue_paise']);

        $byProduct = collect($res->json('by_product'))->keyBy('name');
        $this->assertSame([27121, 21000, 6121, 2257], [
            $byProduct['Cough Syrup']['revenue_paise'], $byProduct['Cough Syrup']['cost_paise'],
            $byProduct['Cough Syrup']['profit_paise'], $byProduct['Cough Syrup']['margin_bp'],
        ]);
        $this->assertSame([1714, 3000], [$byProduct['Dolo 650']['profit_paise'], $byProduct['Dolo 650']['margin_bp']]);
        // Highest revenue first.
        $this->assertSame('Cough Syrup', $res->json('by_product.0.name'));

        $byCategory = collect($res->json('by_category'))->keyBy('category');
        $this->assertSame(1714, $byCategory['Pain Relief']['profit_paise']);
        $this->assertSame(6121, $byCategory['Cough & Cold']['profit_paise']);
    }

    public function test_profit_is_grouped_by_bill_day(): void
    {
        $token = $this->token();
        $dolo = $this->stock($token, 'Dolo 650', 3000, 2000);

        Carbon::setTestNow('2026-10-03 06:00:00');
        $this->bill($token, [$dolo => 1]);
        Carbon::setTestNow('2026-10-05 06:00:00');
        $this->bill($token, [$dolo => 2]);
        $this->bill($token, [$dolo => 1]);
        Carbon::setTestNow('2026-11-02 06:00:00');
        $this->bill($token, [$dolo => 5]); // outside the range

        $days = $this->report($token)->assertOk()->json('by_day');
        $this->assertSame(['2026-10-03', '2026-10-05'], array_column($days, 'date'));
        $this->assertSame([1, 3], array_column($days, 'qty_units'));
        $this->assertSame(3, $this->report($token)->json('totals.bills'));

        // A single day.
        $one = $this->report($token, '2026-10-05', '2026-10-05')->json('totals');
        $this->assertSame([3, 2], [$one['qty_units'], $one['bills']]);
    }

    public function test_lines_without_a_purchase_rate_are_flagged_not_counted_as_profit(): void
    {
        $token = $this->token();
        $dolo = $this->stock($token, 'Dolo 650', 3000, 2000);
        $noCost = $this->stock($token, 'Mystery Tonic', 5000, 0, 'Tonics');

        $this->bill($token, [$dolo => 2, $noCost => 1]);
        $res = $this->report($token)->assertOk();

        // Tonic: 5000 incl. 5% -> CGST = SGST = 119.05 -> 119, taxable 4762.
        $totals = $res->json('totals');
        $this->assertSame(5714 + 4762, $totals['revenue_paise']);
        $this->assertSame(5714, $totals['costed_revenue_paise']);
        $this->assertSame(4000, $totals['cost_paise']);
        $this->assertSame(1714, $totals['profit_paise']);
        $this->assertSame(3000, $totals['margin_bp'], 'margin only over lines with a known cost');
        $this->assertSame(4762, $totals['unknown_cost_revenue_paise']);
        $this->assertSame(1, $totals['unknown_cost_qty_units']);

        $this->assertSame([[
            'product_id' => Batch::findOrFail($noCost)->product_id, 'batch_id' => $noCost, 'name' => 'Mystery Tonic',
            'batch_no' => 'B-Mystery Tonic', 'qty_units' => 1, 'revenue_paise' => 4762,
        ]], $res->json('unknown_cost'));

        $tonic = collect($res->json('by_product'))->firstWhere('name', 'Mystery Tonic');
        $this->assertSame(0, $tonic['profit_paise']);
        $this->assertNull($tonic['margin_bp']);

        // Entering the rate later corrects the report.
        $batch = Batch::findOrFail($noCost);
        $this->push($token, [['table' => 'batches', 'id' => $noCost, 'base_version' => (int) $batch->edit_version,
            'data' => ['purchase_rate_paise' => 3000]]]);
        $after = $this->report($token)->json('totals');
        $this->assertSame([0, 1714 + 1762], [$after['unknown_cost_revenue_paise'], $after['profit_paise']]);
    }

    public function test_cancelled_bills_are_excluded(): void
    {
        $token = $this->token();
        $dolo = $this->stock($token, 'Dolo 650', 3000, 2000);
        $this->bill($token, [$dolo => 2]);
        $cancelled = $this->bill($token, [$dolo => 10]);
        $this->withToken($token)->postJson("/api/v1/bills/{$cancelled}/cancel")->assertOk();

        $totals = $this->report($token)->json('totals');
        $this->assertSame([1, 2, 1714], [$totals['bills'], $totals['qty_units'], $totals['profit_paise']]);
    }

    public function test_a_deleted_batch_still_has_its_cost(): void
    {
        $token = $this->token();
        $dolo = $this->stock($token, 'Dolo 650', 3000, 2000);
        $this->bill($token, [$dolo => 2]);
        $batch = Batch::findOrFail($dolo);
        $this->withToken($token)->postJson('/api/v1/sync/push', ['device_id' => 'phone', 'mutations' => [[
            'mutation_id' => (string) Str::uuid(), 'table' => 'batches', 'op' => 'delete', 'id' => $dolo,
            'base_version' => (int) $batch->edit_version,
        ]]])->assertOk();
        $this->assertSoftDeleted('batches', ['id' => $dolo]);

        $this->assertSame(1714, $this->report($token)->json('totals.profit_paise'));
    }

    // ---- isolation + validation ----------------------------------------------------

    public function test_report_only_covers_the_users_own_shop(): void
    {
        $mine = $this->token();
        $theirs = $this->token();
        $this->bill($mine, [$this->stock($mine, 'Dolo 650', 3000, 2000) => 2]);
        $this->bill($theirs, [$this->stock($theirs, 'Crocin', 4000, 1000) => 7]);

        $res = $this->report($mine)->assertOk();
        $this->assertSame(['Dolo 650'], array_column($res->json('by_product'), 'name'));
        $this->assertSame([1, 2], [$res->json('totals.bills'), $res->json('totals.qty_units')]);

        $other = $this->report($theirs)->json('totals');
        $this->assertSame([1, 7], [$other['bills'], $other['qty_units']]);
    }

    public function test_empty_range_gives_zero_totals_and_no_margin(): void
    {
        $res = $this->report($this->token())->assertOk();
        $this->assertSame(0, $res->json('totals.revenue_paise'));
        $this->assertNull($res->json('totals.margin_bp'));
        $this->assertSame([], $res->json('by_day'));
        $this->assertSame([], $res->json('unknown_cost'));
    }

    public function test_validation_and_auth(): void
    {
        $this->getJson('/api/v1/reports/profit?from=2026-10-01&to=2026-10-31')->assertUnauthorized();

        $token = $this->token();
        $this->withToken($token)->getJson('/api/v1/reports/profit')->assertUnprocessable()
            ->assertJsonValidationErrors(['from', 'to']);
        $this->report($token, '2026-10-31', '2026-10-01')->assertUnprocessable()->assertJsonValidationErrors(['to']);
        $this->report($token, '2026/10/01', '2026-10-31')->assertUnprocessable()->assertJsonValidationErrors(['from']);
        $this->report($token, '2025-01-01', '2026-10-31')->assertUnprocessable()->assertJsonValidationErrors(['to']);
        $this->report($token, '2025-10-01', '2026-09-30')->assertOk(); // 365 days
    }

    // ---- expiry write-off (used by the app's expiry report) --------------------

    public function test_expiry_write_off_movement_syncs_and_zeroes_the_batch(): void
    {
        $token = $this->token();
        $dolo = $this->stock($token, 'Dolo 650', 3000, 2000);

        $res = $this->push($token, [['table' => 'stock_movements', 'id' => (string) Str::uuid(), 'data' => [
            'batch_id' => $dolo, 'delta_units' => -50, 'reason' => 'expiry_writeoff',
            'occurred_at' => now()->toIso8601String(),
        ]]]);
        $this->assertSame('ok', $res->json('results.0.status'));
        $this->assertSame(0, (int) Batch::findOrFail($dolo)->qty_units);
        $this->assertSame(-50, (int) StockMovement::where('reason', 'expiry_writeoff')->sole()->delta_units);
    }
}
