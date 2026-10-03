<?php

namespace Tests\Feature;

use App\Models\MedicineMaster;
use App\Models\Product;
use App\Models\User;
use App\Services\EntitlementService;
use Database\Seeders\DatabaseSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

class MasterCatalogTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(DatabaseSeeder::class);
    }

    private function token(): string
    {
        $user = User::factory()->create(['is_admin' => false]);
        app(EntitlementService::class)->ensureTrial($user);

        return $user->issueToken('test');
    }

    private function pushProduct(string $token, array $data, ?array $batch = null): string
    {
        $id = (string) Str::uuid();
        $mutations = [[
            'mutation_id' => (string) Str::uuid(), 'table' => 'products', 'op' => 'upsert', 'id' => $id, 'data' => $data,
        ]];
        if ($batch) {
            $mutations[] = [
                'mutation_id' => (string) Str::uuid(), 'table' => 'batches', 'op' => 'upsert',
                'id' => (string) Str::uuid(), 'data' => ['product_id' => $id] + $batch,
            ];
        }
        $this->withToken($token)->postJson('/api/v1/sync/push', ['device_id' => 'd', 'mutations' => $mutations])
            ->assertOk()->assertJsonPath('results.0.status', 'ok');

        return $id;
    }

    private function seedRow(string $name, string $maker): MedicineMaster
    {
        return MedicineMaster::create([
            'seed_id' => random_int(1, 1_000_000),
            'name' => $name,
            'name_norm' => MedicineMaster::norm($name),
            'manufacturer' => $maker,
            'manufacturer_norm' => MedicineMaster::norm($maker),
            'source' => 'seed',
        ]);
    }

    public function test_known_medicine_links_to_the_catalog_without_a_duplicate(): void
    {
        $seed = $this->seedRow('Paracetamol 500', 'Acme Pharma');
        $count = MedicineMaster::count();

        $id = $this->pushProduct($this->token(), ['name' => '  paracetamol   500 ', 'manufacturer' => 'ACME pharma']);

        $this->assertSame($count, MedicineMaster::count());
        $this->assertSame($seed->id, (int) Product::find($id)->master_id);
    }

    public function test_new_medicine_is_added_and_other_shops_can_find_it(): void
    {
        $shopA = $this->token();
        $id = $this->pushProduct($shopA,
            ['name' => 'Kofex Herbal Syrup', 'manufacturer' => 'Zed Labs', 'unit' => 'ML', 'pack_size' => 100, 'barcode' => '8901234567890'],
            ['batch_no' => 'K1', 'expiry_date' => '2027-06-30', 'mrp_paise' => 9550]);

        $master = MedicineMaster::where('name_norm', 'kofex herbal syrup')->sole();
        $this->assertSame(['shop', '8901234567890', '100 ML', '95.50'],
            [$master->source, $master->barcode, $master->pack_size, (string) $master->price]);
        $this->assertSame($master->id, (int) Product::find($id)->master_id);

        // The device learns the link on its next pull.
        $pulled = $this->withToken($shopA)->getJson('/api/v1/sync/pull?since=0')->json('changes.products.0');
        $this->assertSame($master->id, $pulled['master_id']);

        // Another shop finds it by name and by barcode.
        $shopB = $this->token();
        $this->withToken($shopB)->getJson('/api/v1/medicines/search?q=kofex')
            ->assertJsonPath('results.0.id', $master->id)
            ->assertJsonPath('results.0.source', 'shop')
            ->assertJsonPath('results.0.unit', 'ML');
        $this->withToken($shopB)->getJson('/api/v1/medicines/search?barcode=8901234567890')
            ->assertJsonPath('results.0.name', 'Kofex Herbal Syrup');

        // Shop B adding the same medicine reuses that catalog row.
        $idB = $this->pushProduct($shopB, ['name' => 'KOFEX herbal syrup', 'manufacturer' => 'zed labs']);
        $this->assertSame(1, MedicineMaster::where('name_norm', 'kofex herbal syrup')->count());
        $this->assertSame($master->id, (int) Product::find($idB)->master_id);
    }

    public function test_csv_reimport_upserts_seed_rows_and_keeps_shop_rows(): void
    {
        $this->pushProduct($this->token(), ['name' => 'Shop Only Tonic', 'manufacturer' => 'Local']);
        $csv = tempnam(sys_get_temp_dir(), 'med').'.csv';
        file_put_contents($csv, implode("\n", [
            'id,name,price(₹),Is_discontinued,manufacturer_name,type,pack_size_label,short_composition1,short_composition2',
            '1,Azithral 500 Tablet,119.5,FALSE,Alembic Pharmaceuticals Ltd,allopathy,strip of 5 tablets,Azithromycin (500mg),',
            '2,Ascoril LS Syrup,118,FALSE,Glenmark Pharmaceuticals Ltd,allopathy,bottle of 100 ml syrup,Ambroxol (30mg/5ml),Levosalbutamol (1mg/5ml)',
        ]));

        $this->artisan('medicines:import', ['path' => $csv])->assertSuccessful();
        $this->artisan('medicines:import', ['path' => $csv])->assertSuccessful();

        $this->assertSame(2, MedicineMaster::where('source', 'seed')->count(), 're-import does not duplicate');
        $this->assertSame(1, MedicineMaster::where('source', 'shop')->count(), 'shop rows survive');
        $this->assertSame('azithral 500 tablet', MedicineMaster::where('seed_id', 1)->value('name_norm'));
        @unlink($csv);
    }
}
