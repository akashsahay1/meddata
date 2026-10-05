<?php

namespace Tests\Feature;

use App\Models\Batch;
use App\Models\Bill;
use App\Models\Product;
use App\Models\Shop;
use App\Models\StockMovement;
use App\Models\User;
use App\Services\EntitlementService;
use Database\Seeders\DatabaseSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

class BillingApiTest extends TestCase
{
    use RefreshDatabase;

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

    // ---- helpers ----------------------------------------------------------

    private function token(?User $user = null): string
    {
        $user ??= User::factory()->create(['is_admin' => false]);
        app(EntitlementService::class)->ensureTrial($user);

        return $user->issueToken('test');
    }

    /** Set the shop's invoice details (Maharashtra, prefix MED). */
    private function shop(string $token, array $details = []): array
    {
        return $this->withToken($token)->patchJson('/api/v1/shops/current', $details + [
            'legal_name' => 'Sahay Medicals Pvt Ltd',
            'gstin' => '27AAPFU0939F1ZV',
            'invoice_prefix' => 'med',
            'drug_license_no' => 'MH-20B-12345',
        ])->assertOk()->json('shop');
    }

    private function push(string $token, array $mutations, string $device = 'phone'): TestResponse
    {
        return $this->withToken($token)->postJson('/api/v1/sync/push', [
            'device_id' => $device,
            'mutations' => array_map(fn ($m) => $m + ['mutation_id' => (string) Str::uuid(), 'op' => 'upsert'], $mutations),
        ])->assertOk();
    }

    /**
     * A product with one batch in stock, through the sync API like a device.
     *
     * @return array{product: string, batch: string, version: int}
     */
    private function stock(string $token, array $product = [], array $batch = [], int $qty = 20): array
    {
        $p = (string) Str::uuid();
        $b = (string) Str::uuid();
        $res = $this->push($token, [
            ['table' => 'products', 'id' => $p, 'data' => $product + ['name' => 'Dolo 650', 'unit' => 'Strips', 'hsn' => '3004', 'gst_rate_bp' => 500]],
            ['table' => 'batches', 'id' => $b, 'data' => $batch + ['product_id' => $p, 'batch_no' => 'B1', 'expiry_date' => '2027-10-31', 'mrp_paise' => 3000]],
            ['table' => 'stock_movements', 'id' => (string) Str::uuid(), 'data' => [
                'batch_id' => $b, 'delta_units' => $qty, 'reason' => 'opening', 'occurred_at' => now()->toIso8601String(),
            ]],
        ]);

        return ['product' => $p, 'batch' => $b, 'version' => (int) $res->json('results.1.version')];
    }

    private function line(array $stock, int $qty = 1, array $extra = []): array
    {
        $batch = Batch::withTrashed()->findOrFail($stock['batch']);

        return $extra + [
            'batch_id' => $stock['batch'],
            'qty_units' => $qty,
            'mrp_paise' => (int) $batch->mrp_paise,
            'batch_version' => (int) $batch->edit_version,
        ];
    }

    private function bill(string $token, array $lines, array $extra = [], ?string $id = null): TestResponse
    {
        return $this->withToken($token)->postJson('/api/v1/bills', $extra + [
            'id' => $id ?? (string) Str::uuid(),
            'device_id' => 'phone',
            'payment_mode' => 'cash',
            'lines' => $lines,
        ]);
    }

    // ---- tax ----------------------------------------------------------------

    public function test_intra_state_bill_splits_gst_into_cgst_and_sgst(): void
    {
        $token = $this->token();
        $this->shop($token);
        $dolo = $this->stock($token);
        $syrup = $this->stock($token, ['name' => 'Cough Syrup', 'unit' => 'Bottles', 'hsn' => '3004', 'gst_rate_bp' => 1200],
            ['batch_no' => 'S9', 'mrp_paise' => 11250]);

        $res = $this->bill($token, [
            $this->line($dolo, 2),
            $this->line($syrup, 3, ['discount_bp' => 1000]),
        ])->assertCreated();

        $bill = $res->json('bill');
        $this->assertSame('MED/26-27/000001', $bill['invoice_no']);
        $this->assertSame('2026-10-05', $bill['bill_date']);
        $this->assertSame('27', $bill['place_of_supply']);
        $this->assertFalse($bill['is_inter_state']);
        $this->assertSame(
            [39750, 3375, 32835, 1770, 1770, 0, 25, 36400],
            [$bill['subtotal_paise'], $bill['discount_paise'], $bill['taxable_paise'], $bill['cgst_paise'],
                $bill['sgst_paise'], $bill['igst_paise'], $bill['round_off_paise'], $bill['total_paise']],
        );

        $syrupLine = $bill['items'][1];
        $this->assertSame(['Cough Syrup', '3004', 'S9', '2027-10-31', 3, 11250, 1000, 1200],
            [$syrupLine['name'], $syrupLine['hsn'], $syrupLine['batch_no'], $syrupLine['expiry_date'],
                $syrupLine['qty_units'], $syrupLine['mrp_paise'], $syrupLine['discount_bp'], $syrupLine['gst_rate_bp']]);
        $this->assertSame([3375, 27121, 1627, 1627, 0, 30375, 9040],
            [$syrupLine['discount_paise'], $syrupLine['taxable_paise'], $syrupLine['cgst_paise'], $syrupLine['sgst_paise'],
                $syrupLine['igst_paise'], $syrupLine['total_paise'], $syrupLine['rate_paise']]);

        // Tax summary per rate, and the seller details as printed.
        $this->assertSame([500, 1200], array_column($bill['tax_summary'], 'gst_rate_bp'));
        $this->assertSame(5714, $bill['tax_summary'][0]['taxable_paise']);
        $this->assertSame('Sahay Medicals Pvt Ltd', $bill['seller']['legal_name']);
        $this->assertSame('27AAPFU0939F1ZV', $bill['seller']['gstin']);
        $this->assertSame('MH-20B-12345', $bill['seller']['drug_license_no']);
    }

    public function test_customer_from_another_state_gets_igst(): void
    {
        $token = $this->token();
        $this->shop($token);
        $dolo = $this->stock($token);

        // State taken from the customer's GSTIN (Karnataka).
        $bill = $this->bill($token, [$this->line($dolo, 2)], [
            'customer_name' => 'City Clinic',
            'customer_gstin' => '29aagcb7383j1z4',
            'customer_address' => 'MG Road, Bengaluru',
        ])->assertCreated()->json('bill');

        $this->assertSame(['29AAGCB7383J1Z4', '29', '29', 'Karnataka', true],
            [$bill['customer_gstin'], $bill['customer_state_code'], $bill['place_of_supply'],
                $bill['place_of_supply_name'], $bill['is_inter_state']]);
        $this->assertSame([5714, 0, 0, 286, 6000],
            [$bill['taxable_paise'], $bill['cgst_paise'], $bill['sgst_paise'], $bill['igst_paise'], $bill['total_paise']]);

        // An explicit place of supply in the shop's state is intra-state.
        $intra = $this->bill($token, [$this->line($dolo, 1)], ['customer_state_code' => '27'])
            ->assertCreated()->json('bill');
        $this->assertFalse($intra['is_inter_state']);
        $this->assertSame(0, $intra['igst_paise']);
    }

    public function test_products_without_a_gst_rate_use_the_shop_default(): void
    {
        $token = $this->token();
        $this->shop($token, ['default_gst_rate_bp' => 1200]);
        $plain = $this->stock($token, ['name' => 'Cotton', 'hsn' => null, 'gst_rate_bp' => null], ['mrp_paise' => 11200]);

        $item = $this->bill($token, [$this->line($plain)])->assertCreated()->json('bill.items.0');

        $this->assertSame([1200, 10000, 600, 600], [$item['gst_rate_bp'], $item['taxable_paise'], $item['cgst_paise'], $item['sgst_paise']]);
    }

    // ---- refusals -------------------------------------------------------------

    public function test_stale_price_is_refused_with_the_current_price(): void
    {
        $token = $this->token();
        $dolo = $this->stock($token);
        $seen = $this->line($dolo, 2);

        // Another device raises the MRP from ₹30 to ₹32 after this one loaded it.
        $this->push($token, [['table' => 'batches', 'id' => $dolo['batch'], 'base_version' => $dolo['version'], 'data' => ['mrp_paise' => 3200]]], 'pc');

        $res = $this->bill($token, [$seen])->assertStatus(409);
        $res->assertJsonPath('error', 'price_changed')
            ->assertJsonPath('lines.0.index', 0)
            ->assertJsonPath('lines.0.name', 'Dolo 650')
            ->assertJsonPath('lines.0.sent_mrp_paise', 3000)
            ->assertJsonPath('lines.0.mrp_paise', 3200)
            ->assertJsonPath('lines.0.price_changed', true);
        $this->assertSame(0, Bill::count());
        $this->assertSame(20, (int) Batch::find($dolo['batch'])->qty_units);

        // The device accepts ₹32 and resends with the version it was given.
        $this->bill($token, [['mrp_paise' => 3200, 'batch_version' => $res->json('lines.0.batch_version')] + $seen])
            ->assertCreated()
            ->assertJsonPath('bill.total_paise', 6400);
    }

    public function test_any_edit_of_the_batch_since_it_was_loaded_is_refused(): void
    {
        $token = $this->token();
        $dolo = $this->stock($token);
        $seen = $this->line($dolo);
        $this->push($token, [['table' => 'batches', 'id' => $dolo['batch'], 'base_version' => $dolo['version'], 'data' => ['batch_no' => 'B1-A']]], 'pc');

        $this->bill($token, [$seen])->assertStatus(409)
            ->assertJsonPath('lines.0.price_changed', false)
            ->assertJsonPath('lines.0.mrp_paise', 3000);
    }

    public function test_a_sale_on_another_device_does_not_make_the_price_stale(): void
    {
        $token = $this->token();
        $dolo = $this->stock($token);
        $seen = $this->line($dolo, 2);
        $this->push($token, [['table' => 'stock_movements', 'id' => (string) Str::uuid(), 'data' => [
            'batch_id' => $dolo['batch'], 'delta_units' => -1, 'reason' => 'sale', 'occurred_at' => now()->toIso8601String(),
        ]]], 'pc');

        $this->bill($token, [$seen])->assertCreated();
        $this->assertSame(17, (int) Batch::find($dolo['batch'])->qty_units);
    }

    public function test_insufficient_stock_is_refused_with_what_is_left(): void
    {
        $token = $this->token();
        $dolo = $this->stock($token, qty: 5);

        // Two lines of the same batch count together.
        $this->bill($token, [$this->line($dolo, 4), $this->line($dolo, 2)])
            ->assertStatus(422)
            ->assertJsonPath('error', 'insufficient_stock')
            ->assertJsonPath('lines.0.requested_units', 6)
            ->assertJsonPath('lines.0.available_units', 5)
            ->assertJsonPath('lines.0.batch_no', 'B1');

        $this->assertSame(0, Bill::count());
        $this->assertSame(1, StockMovement::count(), 'only the opening stock');
        $this->bill($token, [$this->line($dolo, 5)])->assertCreated();
    }

    public function test_batch_must_belong_to_the_shop_and_be_sellable(): void
    {
        $alice = $this->token();
        $bob = $this->token();
        $alicesBatch = $this->stock($alice);
        $expired = $this->stock($bob, batch: ['batch_no' => 'OLD', 'expiry_date' => '2026-10-04']);
        $today = $this->stock($bob, batch: ['batch_no' => 'TODAY', 'expiry_date' => '2026-10-05']);
        $deleted = $this->stock($bob, ['name' => 'Gone']);
        $this->push($bob, [['table' => 'products', 'op' => 'delete', 'id' => $deleted['product'], 'base_version' => (int) Product::find($deleted['product'])->edit_version]]);

        $res = $this->bill($bob, [
            $this->line($alicesBatch),
            $this->line($expired),
            $this->line($deleted),
            $this->line($today),
        ])->assertStatus(422);

        $res->assertJsonPath('error', 'batch_unavailable');
        $this->assertSame(
            [[0, 'not_found'], [1, 'expired'], [2, 'deleted']],
            array_map(fn ($l) => [$l['index'], $l['reason']], $res->json('lines')),
        );
        $this->assertNull($res->json('lines.0.name'), "nothing of the other shop's batch leaks");
        $this->assertSame(20, (int) Batch::find($alicesBatch['batch'])->qty_units);

        // Expiring today is still sellable.
        $this->bill($bob, [$this->line($today)])->assertCreated();
    }

    public function test_validation(): void
    {
        $token = $this->token();
        $dolo = $this->stock($token);

        $this->bill($token, [])->assertStatus(422)->assertJsonValidationErrors('lines');
        $this->bill($token, [$this->line($dolo, 0)], ['payment_mode' => 'cheque'])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['lines.0.qty_units', 'payment_mode']);
        // A credit sale goes on a customer's account (a typed name is not
        // enough); GSTINs are checked.
        $this->bill($token, [$this->line($dolo)], ['payment_mode' => 'credit', 'customer_name' => 'Ramesh', 'customer_gstin' => '27AAPFU0939F1ZX'])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['party_id', 'customer_gstin']);
        $party = $this->withToken($token)->postJson('/api/v1/parties', ['type' => 'customer', 'name' => 'Ramesh'])
            ->assertCreated()->json('party.id');
        $this->bill($token, [$this->line($dolo)], ['payment_mode' => 'credit', 'party_id' => $party])
            ->assertCreated()
            ->assertJsonPath('bill.payment_mode', 'credit')
            ->assertJsonPath('bill.party_id', $party)
            ->assertJsonPath('bill.customer_name', 'Ramesh');
        // A cash bill still takes just a typed name.
        $this->bill($token, [$this->line($dolo)], ['customer_name' => 'Walk-in Suresh'])->assertCreated();
    }

    // ---- idempotency + numbering -------------------------------------------

    public function test_retrying_with_the_same_id_returns_the_same_bill(): void
    {
        $token = $this->token();
        $dolo = $this->stock($token);
        $id = (string) Str::uuid();

        $first = $this->bill($token, [$this->line($dolo, 3)], [], $id)->assertCreated();
        // The retry carries the same lines; even a changed body can't bill twice.
        $again = $this->bill($token, [$this->line($dolo, 5)], [], $id)->assertOk();

        $this->assertTrue($again->json('replayed'));
        $this->assertSame($first->json('bill'), $again->json('bill'));
        $this->assertSame(1, Bill::count());
        $this->assertSame(17, (int) Batch::find($dolo['batch'])->qty_units);
        $this->assertSame(1, StockMovement::where('reason', 'sale')->count());
        $this->assertSame(1, (int) DB::table('invoice_series')->value('last_seq'));

        // Another shop can't reuse (or read) that id.
        $this->bill($this->token(), [$this->line($this->stock($this->token()))], [], $id)->assertStatus(422);
    }

    public function test_invoice_numbers_are_gap_free_per_shop_and_restart_each_financial_year(): void
    {
        $alice = $this->token();
        $bob = $this->token();
        $this->shop($alice);
        $a = $this->stock($alice, qty: 100);
        $b = $this->stock($bob, qty: 100);

        $numbers = fn (string $token, array $stock, int $n) => array_map(
            fn () => $this->bill($token, [$this->line($stock)])->assertCreated()->json('bill.invoice_no'), range(1, $n));

        $this->assertSame(['MED/26-27/000001', 'MED/26-27/000002'], $numbers($alice, $a, 2));
        // Bob has his own series, with the default prefix.
        $this->assertSame(['INV/26-27/000001'], $numbers($bob, $b, 1));

        // A refused bill doesn't use up a number.
        $this->bill($alice, [$this->line($a, 1000)])->assertStatus(422);
        $this->bill($alice, [['mrp_paise' => 1] + $this->line($a)])->assertStatus(409);
        $this->assertSame(['MED/26-27/000003'], $numbers($alice, $a, 1));

        // Last day of the financial year, then 1 April: a new series.
        Carbon::setTestNow('2027-03-31 23:59:00');
        $this->assertSame(['MED/26-27/000004'], $numbers($alice, $a, 1));
        Carbon::setTestNow('2027-04-01 00:01:00');
        $this->assertSame(['MED/27-28/000001', 'MED/27-28/000002'], $numbers($alice, $a, 2));

        $alicesShop = Shop::where('invoice_prefix', 'MED')->firstOrFail();
        $this->assertSame([1, 2, 3, 4], Bill::where('shop_id', $alicesShop->id)->where('fy', '26-27')->orderBy('seq')->pluck('seq')->all());
        $this->assertSame('2027-04-01', Bill::where('shop_id', $alicesShop->id)->where('fy', '27-28')->value('bill_date'));
    }

    public function test_bill_dates_are_indian_time(): void
    {
        $token = $this->token();
        $dolo = $this->stock($token);

        // 31 Mar 2027, 19:00 UTC is 1 Apr 2027, 00:30 in India: the new financial year.
        Carbon::setTestNow(Carbon::parse('2027-03-31 19:00:00', 'UTC'));
        $bill = $this->bill($token, [$this->line($dolo)])->assertCreated()->json('bill');

        $this->assertSame(['2027-04-01', '27-28', 'INV/27-28/000001'],
            [$bill['bill_date'], $bill['fy'], $bill['invoice_no']]);
    }

    // ---- cancel ----------------------------------------------------------------

    public function test_cancel_restores_stock_and_keeps_the_number_used(): void
    {
        $token = $this->token();
        $dolo = $this->stock($token);
        $id = $this->bill($token, [$this->line($dolo, 4)])->assertCreated()->json('bill.id');
        $this->assertSame(16, (int) Batch::find($dolo['batch'])->qty_units);

        $res = $this->withToken($token)->postJson("/api/v1/bills/{$id}/cancel", ['reason' => 'Wrong medicine', 'device_id' => 'pc'])
            ->assertOk()
            ->assertJsonPath('bill.status', 'cancelled')
            ->assertJsonPath('bill.cancel_reason', 'Wrong medicine')
            ->assertJsonPath('batches.0.qty_units', 20);
        $this->assertNotNull($res->json('bill.cancelled_at'));
        $this->assertSame(20, (int) Batch::find($dolo['batch'])->qty_units);
        $back = StockMovement::where('reason', 'sale_cancel')->sole();
        $this->assertSame([4, 'bill', $id, 'pc'], [(int) $back->delta_units, $back->ref_type, $back->ref_id, $back->device_id]);

        // Cancelling twice changes nothing; the next bill takes the next number.
        $this->withToken($token)->postJson("/api/v1/bills/{$id}/cancel")->assertOk();
        $this->assertSame(1, StockMovement::where('reason', 'sale_cancel')->count());
        $this->bill($token, [$this->line($dolo)])->assertCreated()->assertJsonPath('bill.invoice_no', 'INV/26-27/000002');
    }

    // ---- reading -------------------------------------------------------------------

    public function test_bills_are_listed_by_date_and_shop_scoped(): void
    {
        $alice = $this->token();
        $bob = $this->token();
        $dolo = $this->stock($alice, qty: 100);

        Carbon::setTestNow('2026-10-04 18:00:00');
        $this->bill($alice, [$this->line($dolo, 1)], ['customer_name' => 'Ramesh'])->assertCreated();
        Carbon::setTestNow('2026-10-05 10:00:00');
        $this->bill($alice, [$this->line($dolo, 2)])->assertCreated();
        $cancelled = $this->bill($alice, [$this->line($dolo, 3)])->assertCreated()->json('bill.id');
        $this->withToken($alice)->postJson("/api/v1/bills/{$cancelled}/cancel")->assertOk();

        $today = $this->withToken($alice)->getJson('/api/v1/bills?from=2026-10-05&to=2026-10-05')->assertOk();
        $this->assertSame(['INV/26-27/000003', 'INV/26-27/000002'], array_column($today->json('data'), 'invoice_no'));
        $this->assertSame(['count' => 1, 'total_paise' => 6000, 'cancelled_count' => 1], $today->json('summary'));
        $this->assertSame(1, $today->json('data.1.items_count'));

        $all = $this->withToken($alice)->getJson('/api/v1/bills?per_page=2')->assertOk();
        $this->assertSame(['current_page' => 1, 'last_page' => 2, 'per_page' => 2, 'total' => 3], $all->json('meta'));
        $this->assertSame('Ramesh', $this->withToken($alice)->getJson('/api/v1/bills?q=rame')->json('data.0.customer_name'));

        $first = $this->withToken($alice)->getJson('/api/v1/bills?page=2&per_page=2')->json('data.0.id');
        $this->withToken($alice)->getJson("/api/v1/bills/{$first}")->assertOk()
            ->assertJsonPath('bill.items.0.qty_units', 1);

        // Bob sees none of it.
        $this->assertSame([], $this->withToken($bob)->getJson('/api/v1/bills')->json('data'));
        $this->withToken($bob)->getJson("/api/v1/bills/{$first}")->assertNotFound();
        $this->withToken($bob)->postJson("/api/v1/bills/{$first}/cancel")->assertNotFound();
        $this->assertSame('final', Bill::find($first)->status);

        $this->withoutToken()->getJson('/api/v1/bills')->assertUnauthorized();
        $this->withoutToken()->postJson('/api/v1/bills', [])->assertUnauthorized();
    }

    public function test_devices_pull_the_sale_and_the_new_stock(): void
    {
        $token = $this->token();
        $dolo = $this->stock($token);
        $since = $this->withToken($token)->getJson('/api/v1/sync/status')->json('server_version');

        $billId = $this->bill($token, [$this->line($dolo, 3)])->assertCreated()
            ->assertJsonPath('batches.0.qty_units', 17)
            ->json('bill.id');

        $pull = $this->withToken($token)->getJson("/api/v1/sync/pull?since={$since}")->assertOk();
        $move = $pull->json('changes.stock_movements.0');
        $this->assertSame([-3, 'sale', 'bill', $billId, $dolo['batch'], $dolo['product']],
            [$move['delta_units'], $move['reason'], $move['ref_type'], $move['ref_id'], $move['batch_id'], $move['product_id']]);
        $this->assertSame(17, $pull->json('changes.batches.0.qty_units'));
        // A sale is not an edit: the batch's edit_version (price check) is unchanged.
        $this->assertSame($dolo['version'], $pull->json('changes.batches.0.edit_version'));
    }

    // ---- shop details ------------------------------------------------------------

    public function test_shop_invoice_details_are_validated(): void
    {
        $token = $this->token();

        $shop = $this->shop($token, ['state_code' => null]);
        $this->assertSame(['Sahay Medicals Pvt Ltd', '27AAPFU0939F1ZV', '27', 'MED', 1800],
            [$shop['legal_name'], $shop['gstin'], $shop['state_code'], $shop['invoice_prefix'], $shop['default_gst_rate_bp']]);

        $patch = fn (array $data) => $this->withToken($token)->patchJson('/api/v1/shops/current', $data);
        $patch(['gstin' => '27AAPFU0939F1ZX', 'invoice_prefix' => 'MEDS', 'state_code' => '99', 'default_gst_rate_bp' => 4000])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['gstin', 'invoice_prefix', 'state_code', 'default_gst_rate_bp']);
        $patch(['state_code' => '29'])->assertStatus(422)->assertJsonValidationErrors('state_code');
        $patch(['gstin' => null, 'state_code' => '29', 'invoice_prefix' => ''])->assertOk()
            ->assertJsonPath('shop.state_code', '29')
            ->assertJsonPath('shop.invoice_prefix', null);
    }
}
