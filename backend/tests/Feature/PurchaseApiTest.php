<?php

namespace Tests\Feature;

use App\Models\Batch;
use App\Models\Product;
use App\Models\Purchase;
use App\Models\StockMovement;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;
use Tests\Feature\Concerns\AccountingHelpers;
use Tests\TestCase;

class PurchaseApiTest extends TestCase
{
    use AccountingHelpers;
    use RefreshDatabase;

    private function purchase(string $token, array $lines, array $extra = []): TestResponse
    {
        return $this->withToken($token)->postJson('/api/v1/purchases', $extra + [
            'id' => (string) Str::uuid(),
            'device_id' => 'phone',
            'supplier_invoice_no' => 'PPD/2526/0042',
            'invoice_date' => '2026-10-03',
            'lines' => $lines,
        ]);
    }

    /**
     * A new medicine (10 tablets a strip, billed per strip, 10% off, 2 free)
     * and more of an existing batch.
     */
    private function lines(array $dolo, string $newProduct): array
    {
        return [
            [
                'product_id' => $newProduct,
                'product' => ['name' => 'Azithral 500', 'manufacturer' => 'Alembic', 'unit' => 'Tablets', 'pack_size' => 10],
                'batch_no' => 'AZ9', 'expiry_date' => '2028-03-31', 'mfg_date' => '2026-04-01',
                'qty' => 10, 'free_qty' => 2, 'units_per_pack' => 10,
                'rate_paise' => 5000, 'mrp_paise' => 11200, 'discount_bp' => 1000, 'gst_rate_bp' => 1200, 'hsn' => '30042019',
            ],
            [
                'product_id' => $dolo['product'],
                'batch_no' => 'b1', 'expiry_date' => '2027-10-31',
                'qty' => 5, 'rate_paise' => 7000, 'mrp_paise' => 11200,
            ],
        ];
    }

    public function test_purchase_adds_stock_once_on_the_server_with_input_gst(): void
    {
        $token = $this->token();
        $this->shop($token);
        $dolo = $this->stock($token);
        $supplier = $this->supplier($token);
        $since = $this->withToken($token)->getJson('/api/v1/sync/status')->json('server_version');
        $newProduct = (string) Str::uuid();

        $res = $this->purchase($token, $this->lines($dolo, $newProduct), ['party_id' => $supplier])->assertCreated();
        $p = $res->json('purchase');
        $this->assertSame(['Pune Pharma Distributors', 'PPD/2526/0042', '2026-10-03', '2026-10-05', false],
            [$p['supplier_name'], $p['supplier_invoice_no'], $p['invoice_date'], $p['entry_date'], $p['is_inter_state']]);
        $this->assertSame([85000, 5000, 80000, 4800, 4800, 0, 0, 89600],
            [$p['subtotal_paise'], $p['discount_paise'], $p['taxable_paise'], $p['cgst_paise'], $p['sgst_paise'],
                $p['igst_paise'], $p['round_off_paise'], $p['total_paise']]);
        $this->assertSame([45000, 2700, 2700, 50400, 120, true],
            [$p['items'][0]['taxable_paise'], $p['items'][0]['cgst_paise'], $p['items'][0]['sgst_paise'],
                $p['items'][0]['total_paise'], $p['items'][0]['stock_units'], $p['items'][0]['new_batch']]);
        $this->assertSame(89600, $p['outstanding_paise']);

        // The new medicine was created (with HSN and GST from the bill), a new
        // batch with per-tablet prices; the known batch got 5 more.
        $product = Product::findOrFail($newProduct);
        $this->assertSame(['Azithral 500', 'Tablets', '30042019', 1200], [$product->name, $product->unit, $product->hsn, (int) $product->gst_rate_bp]);
        $batch = Batch::where('product_id', $newProduct)->firstOrFail();
        $this->assertSame([120, 1120, 450, 'AZ9'], [(int) $batch->qty_units, (int) $batch->mrp_paise, (int) $batch->purchase_rate_paise, $batch->batch_no]);
        $this->assertSame($dolo['batch'], $p['items'][1]['batch_id']);
        $this->assertFalse($p['items'][1]['new_batch']);
        $this->assertSame(25, $this->qty($dolo['batch']));
        $this->assertEqualsCanonicalizing(
            [[100, 'purchase'], [20, 'purchase_free'], [5, 'purchase']],
            StockMovement::where('ref_id', $p['id'])->get()->map(fn ($m) => [(int) $m->delta_units, $m->reason])->all(),
        );
        $this->assertEqualsCanonicalizing([['batch_id' => $batch->id, 'qty_units' => 120], ['batch_id' => $dolo['batch'], 'qty_units' => 25]],
            $res->json('batches'));

        // Devices get the product, the batch, its qty and the movements by pull.
        $pull = $this->withToken($token)->getJson("/api/v1/sync/pull?since={$since}")->assertOk();
        $this->assertContains($newProduct, array_column($pull->json('changes.products'), 'id'));
        $pulledBatches = collect($pull->json('changes.batches'))->keyBy('id');
        $this->assertSame(120, $pulledBatches[$batch->id]['qty_units']);
        $this->assertSame(25, $pulledBatches[$dolo['batch']]['qty_units']);
        $moves = collect($pull->json('changes.stock_movements'));
        $this->assertSame(125, $moves->sum('delta_units'));
        $this->assertSame(['purchase'], $moves->pluck('ref_type')->unique()->values()->all());

        // In the supplier's ledger the purchase is owed.
        $this->withToken($token)->getJson("/api/v1/parties/$supplier")->assertJsonPath('party.balance_paise', -89600)
            ->assertJsonPath('open_documents.0.number', 'PPD/2526/0042');
        $this->withToken($token)->getJson('/api/v1/purchases')->assertOk()
            ->assertJsonPath('data.0.items_count', 2)->assertJsonPath('summary.total_paise', 89600);
    }

    public function test_supplier_in_another_state_charges_igst(): void
    {
        $token = $this->token();
        $this->shop($token);
        $dolo = $this->stock($token);
        $supplier = $this->supplier($token, ['name' => 'Bengaluru Pharma', 'gstin' => $this->gstin('29')]);

        $p = $this->purchase($token, $this->lines($dolo, (string) Str::uuid()), ['party_id' => $supplier])->assertCreated()->json('purchase');
        $this->assertTrue($p['is_inter_state']);
        $this->assertSame([80000, 0, 0, 9600, 89600], [$p['taxable_paise'], $p['cgst_paise'], $p['sgst_paise'], $p['igst_paise'], $p['total_paise']]);
        $this->assertSame('29', $p['supplier_state_code']);
    }

    public function test_retries_and_duplicate_invoices_never_add_stock_twice(): void
    {
        $token = $this->token();
        $dolo = $this->stock($token);
        $supplier = $this->supplier($token);
        $id = (string) Str::uuid();
        $line = [['product_id' => $dolo['product'], 'batch_id' => $dolo['batch'], 'expiry_date' => '2027-10-31', 'qty' => 10, 'rate_paise' => 7000]];

        $first = $this->purchase($token, $line, ['id' => $id, 'party_id' => $supplier])->assertCreated();
        $again = $this->purchase($token, $line, ['id' => $id, 'party_id' => $supplier])->assertOk();
        $this->assertTrue($again->json('replayed'));
        $this->assertSame($first->json('purchase.id'), $again->json('purchase.id'));
        $this->assertSame(30, $this->qty($dolo['batch']));

        // The same supplier invoice entered again (e.g. scanned twice).
        $this->purchase($token, $line, ['party_id' => $supplier, 'supplier_invoice_no' => 'ppd/2526/0042'])
            ->assertStatus(422)->assertJsonPath('error', 'duplicate_invoice')->assertJsonPath('purchase_id', $id);
        $this->assertSame(30, $this->qty($dolo['batch']));
        $this->assertSame(1, Purchase::count());
    }

    public function test_validation_and_shop_isolation(): void
    {
        $alice = $this->token();
        $bob = $this->token();
        $dolo = $this->stock($alice);
        $supplier = $this->supplier($alice);
        $customer = $this->party($alice);
        $line = ['product_id' => $dolo['product'], 'expiry_date' => '2027-10-31', 'qty' => 1, 'rate_paise' => 100];

        $this->purchase($alice, [])->assertStatus(422)->assertJsonValidationErrors(['party_id', 'lines']);
        $this->purchase($alice, [['product_id' => $dolo['product'], 'expiry_date' => '2027-10-31', 'mfg_date' => '2027-11-01', 'qty' => 0, 'rate_paise' => 1]],
            ['party_id' => $supplier])->assertStatus(422)->assertJsonValidationErrors(['lines.0.qty', 'lines.0.expiry_date']);
        $this->purchase($alice, [$line], ['party_id' => $supplier, 'invoice_date' => '2026-12-01'])
            ->assertStatus(422)->assertJsonValidationErrors('invoice_date');
        // Only suppliers.
        $this->purchase($alice, [$line], ['party_id' => $customer])->assertStatus(422)->assertJsonPath('error', 'party_not_supplier');
        // An unknown medicine without its details.
        $this->purchase($alice, [['product_id' => (string) Str::uuid()] + $line], ['party_id' => $supplier])
            ->assertStatus(422)->assertJsonPath('error', 'product_not_found');
        // A batch of another medicine.
        $other = $this->stock($alice, ['name' => 'Crocin']);
        $this->purchase($alice, [['batch_id' => $other['batch']] + $line], ['party_id' => $supplier])
            ->assertStatus(422)->assertJsonPath('error', 'batch_mismatch');

        // Bob can't use Alice's supplier, medicine or batch, nor see her purchase.
        $this->purchase($bob, [$line], ['party_id' => $supplier])->assertStatus(422)->assertJsonPath('error', 'party_not_supplier');
        $bobs = $this->supplier($bob);
        $this->purchase($bob, [$line], ['party_id' => $bobs])->assertStatus(422)->assertJsonPath('error', 'id_conflict');
        $this->assertSame(20, $this->qty($dolo['batch']));
        $mine = $this->purchase($alice, [$line], ['party_id' => $supplier])->assertCreated()->json('purchase.id');
        $this->withToken($bob)->getJson("/api/v1/purchases/$mine")->assertNotFound();
        $this->withToken($bob)->postJson("/api/v1/purchases/$mine/cancel")->assertNotFound();
        $this->assertSame([], $this->withToken($bob)->getJson('/api/v1/purchases')->json('data'));
    }

    public function test_cancel_takes_the_stock_back_out_unless_it_was_sold(): void
    {
        $token = $this->token();
        $this->shop($token);
        $supplier = $this->supplier($token);
        $product = (string) Str::uuid();
        $line = ['product_id' => $product, 'product' => ['name' => 'Pan 40', 'unit' => 'Strips'],
            'batch_no' => 'P1', 'expiry_date' => '2028-01-31', 'qty' => 10, 'rate_paise' => 1000, 'mrp_paise' => 2000, 'gst_rate_bp' => 500];
        $p = $this->purchase($token, [$line], ['party_id' => $supplier])->assertCreated()->json('purchase');
        $batch = $p['items'][0]['batch_id'];

        // Sell 4: the purchase can't be cancelled any more.
        $this->bill($token, [$this->line(['batch' => $batch], 4)])->assertCreated();
        $this->withToken($token)->postJson("/api/v1/purchases/{$p['id']}/cancel")
            ->assertStatus(422)->assertJsonPath('error', 'insufficient_stock')
            ->assertJsonPath('lines.0.available_units', 6);

        // A second purchase, not sold from, cancels: stock out, out of the ledger.
        $second = $this->purchase($token, [['batch_id' => $batch] + $line], ['party_id' => $supplier, 'supplier_invoice_no' => 'X2'])
            ->assertCreated()->json('purchase');
        $this->assertSame(16, $this->qty($batch));
        $this->withToken($token)->postJson("/api/v1/purchases/{$second['id']}/cancel", ['reason' => 'Entered twice'])
            ->assertOk()->assertJsonPath('purchase.status', 'cancelled')->assertJsonPath('batches.0.qty_units', 6);
        $this->assertSame(1, StockMovement::where('reason', 'purchase_cancel')->count());
        $this->withToken($token)->getJson("/api/v1/parties/$supplier")->assertJsonPath('party.balance_paise', -$p['total_paise']);
        // Cancelling again changes nothing; the invoice number can be entered again.
        $this->withToken($token)->postJson("/api/v1/purchases/{$second['id']}/cancel")->assertOk();
        $this->assertSame(6, $this->qty($batch));
        $this->purchase($token, [['batch_id' => $batch] + $line], ['party_id' => $supplier, 'supplier_invoice_no' => 'X2'])->assertCreated();

        // A purchase with a payment against it can't be cancelled.
        $this->withToken($token)->postJson('/api/v1/payments', [
            'id' => (string) Str::uuid(), 'party_id' => $supplier, 'direction' => 'out', 'amount_paise' => 100,
            'mode' => 'bank', 'purchase_id' => $p['id'],
        ])->assertCreated();
        $this->withToken($token)->postJson("/api/v1/purchases/{$p['id']}/cancel")->assertStatus(422)->assertJsonPath('error', 'has_payments');
    }
}
