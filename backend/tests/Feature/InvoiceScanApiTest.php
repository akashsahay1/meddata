<?php

namespace Tests\Feature;

use App\Jobs\ProcessInvoiceScan;
use App\Models\InvoiceScan;
use App\Models\MedicineMaster;
use App\Models\Product;
use App\Models\User;
use App\Services\EntitlementService;
use App\Services\GroqInvoiceReader;
use App\Services\InvoiceProductMatcher;
use App\Services\PdfToImages;
use App\Services\ShopService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\Request as HttpRequest;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Queue;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Sleep;
use Illuminate\Support\Str;
use RuntimeException;
use Tests\TestCase;

class InvoiceScanApiTest extends TestCase
{
    use RefreshDatabase;

    private const GROQ = 'https://api.groq.com/openai/v1/chat/completions';

    protected function setUp(): void
    {
        parent::setUp();
        // Never reach the real API from tests.
        Http::preventStrayRequests();
        Sleep::fake();
        Storage::fake(InvoiceScan::DISK);
        config([
            'services.groq.key' => 'test-key',
            'services.groq.model' => 'qwen/qwen3.8-27b',
            'services.groq.base_url' => 'https://api.groq.com/openai/v1',
        ]);
    }

    private function user(bool $trial = true): User
    {
        $user = User::factory()->create(['is_admin' => false]);
        if ($trial) {
            app(EntitlementService::class)->ensureTrial($user);
        }

        return $user;
    }

    private function upload(User $user, ?UploadedFile $file = null)
    {
        return $this->withToken($user->issueToken('test'))->post('/api/v1/invoices/scan', [
            'file' => $file ?? UploadedFile::fake()->image('bill.jpg', 1200, 1600),
        ], ['Accept' => 'application/json']);
    }

    private function invoice(): array
    {
        return [
            'supplier_name' => 'Shree Ganesh Pharma Distributors',
            'supplier_gstin' => '27abcde1234f1z5',
            'invoice_no' => 'SG/26-27/0456',
            'invoice_date' => '2026-10-01',
            'items' => [
                [
                    'product_name' => 'DOLO 650 TAB', 'manufacturer' => 'MICRO', 'pack' => "15's",
                    'batch_no' => 'DOBS3975', 'expiry_date' => '2027-06', 'mfg_date' => '2025-07',
                    'quantity' => 10, 'free_quantity' => 2, 'mrp' => 30.91, 'purchase_rate' => 22.08,
                    'discount_percent' => 5, 'gst_percent' => 12, 'hsn' => '3004.90.99', 'barcode' => '',
                ],
                [
                    'product_name' => 'AZITHRAL 500 TAB', 'manufacturer' => 'ALEMBIC', 'pack' => "5's",
                    'batch_no' => '', 'expiry_date' => '', 'mfg_date' => '',
                    'quantity' => 4, 'free_quantity' => null, 'mrp' => '₹ 119.50', 'purchase_rate' => null,
                    'discount_percent' => null, 'gst_percent' => 12, 'hsn' => '', 'barcode' => '8901234567894',
                ],
                // Not a product line: no name, must be dropped.
                [
                    'product_name' => '', 'manufacturer' => '', 'pack' => '', 'batch_no' => '',
                    'expiry_date' => '', 'mfg_date' => '', 'quantity' => null, 'free_quantity' => null,
                    'mrp' => null, 'purchase_rate' => null, 'discount_percent' => null,
                    'gst_percent' => null, 'hsn' => '', 'barcode' => '',
                ],
            ],
            'notes' => '',
        ];
    }

    /** A chat completions reply carrying the JSON text. */
    private function reply(array|string $json, string $finish = 'stop', ?string $refusal = null): array
    {
        return [
            'id' => 'chatcmpl-test',
            'object' => 'chat.completion',
            'model' => 'qwen/qwen3.8-27b',
            'choices' => [[
                'index' => 0,
                'message' => [
                    'role' => 'assistant',
                    'content' => is_string($json) ? $json : json_encode($json),
                ] + ($refusal !== null ? ['refusal' => $refusal] : []),
                'finish_reason' => $finish,
            ]],
            'usage' => ['prompt_tokens' => 2100, 'completion_tokens' => 900, 'total_tokens' => 3000],
        ];
    }

    /** A real (tiny) JPEG: photos are checked before they are sent. */
    private function jpeg(): string
    {
        ob_start();
        imagejpeg(imagecreatetruecolor(40, 60));

        return (string) ob_get_clean();
    }

    /** Swaps the PDF converter for one that needs no Imagick/Ghostscript. */
    private function fakePdf(int $pages, bool $broken = false): void
    {
        $jpeg = $this->jpeg();
        $this->app->instance(PdfToImages::class, new class($pages, $broken, $jpeg) extends PdfToImages
        {
            public function __construct(private int $pages, private bool $broken, private string $jpeg) {}

            protected function pageCount(string $pdf): int
            {
                return $this->broken ? throw new RuntimeException('no PDF delegate (gs)') : $this->pages;
            }

            protected function render(string $pdf): array
            {
                return array_fill(0, $this->pages, $this->jpeg);
            }
        });
    }

    private function scanFor(User $user, ?string $content = null, string $mime = 'image/jpeg'): InvoiceScan
    {
        $content ??= $this->jpeg();
        $shop = app(ShopService::class)->forUser($user);
        $path = 'invoice-scans/'.$shop->id.'/'.Str::uuid().'.jpg';
        Storage::disk(InvoiceScan::DISK)->put($path, $content);

        return InvoiceScan::create([
            'shop_id' => $shop->id, 'user_id' => $user->id, 'file_path' => $path,
            'mime' => $mime, 'file_size' => strlen($content), 'status' => InvoiceScan::STATUS_QUEUED,
        ]);
    }

    private function runJob(InvoiceScan $scan, int $attempt = 1): ProcessInvoiceScan
    {
        $job = (new ProcessInvoiceScan($scan))->withFakeQueueInteractions();
        $job->job->attempts = $attempt;
        $job->handle(app(GroqInvoiceReader::class), app(InvoiceProductMatcher::class));

        return $job;
    }

    public function test_upload_stores_the_file_privately_and_queues_the_scan(): void
    {
        Queue::fake();
        $user = $this->user();

        $res = $this->upload($user)->assertStatus(202)
            ->assertJsonPath('scan.status', 'queued')
            ->assertJsonMissingPath('scan.file_path');

        $scan = InvoiceScan::findOrFail($res->json('scan.id'));
        $shopId = app(ShopService::class)->forUser($user)->id;
        $this->assertSame($shopId, $scan->shop_id);
        $this->assertSame('image/jpeg', $scan->mime);
        $this->assertStringStartsWith("invoice-scans/{$shopId}/", $scan->file_path);
        Storage::disk(InvoiceScan::DISK)->assertExists($scan->file_path);
        Queue::assertPushed(ProcessInvoiceScan::class, fn (ProcessInvoiceScan $job) => $job->scan->is($scan));
    }

    public function test_upload_validates_type_and_size(): void
    {
        Queue::fake();
        $user = $this->user();

        $this->withToken($user->issueToken('t'))
            ->postJson('/api/v1/invoices/scan', [])
            ->assertStatus(422)->assertJsonValidationErrors('file');
        $this->upload($user, UploadedFile::fake()->create('notes.txt', 10, 'text/plain'))
            ->assertStatus(422)->assertJsonValidationErrors('file');
        // Photos are capped lower than PDFs (the AI service's image limit).
        $this->upload($user, UploadedFile::fake()->create('big.jpg', 7500, 'image/jpeg'))
            ->assertStatus(422)->assertJsonValidationErrors('file');
        $this->upload($user, UploadedFile::fake()->create('huge.pdf', 11000, 'application/pdf'))
            ->assertStatus(422)->assertJsonValidationErrors('file');
        $this->upload($user, UploadedFile::fake()->create('ok.pdf', 9000, 'application/pdf'))
            ->assertStatus(202);

        $this->assertSame(1, InvoiceScan::count());
        Queue::assertPushed(ProcessInvoiceScan::class, 1);
    }

    public function test_upload_needs_a_login_and_an_active_plan(): void
    {
        Queue::fake();

        $this->post('/api/v1/invoices/scan', [], ['Accept' => 'application/json'])->assertStatus(401);
        $this->upload($this->user(trial: false))
            ->assertStatus(403)
            ->assertJsonPath('error', 'premium_required');

        $this->assertSame(0, InvoiceScan::count());
        Queue::assertNothingPushed();
    }

    public function test_a_scan_is_only_visible_to_its_own_shop(): void
    {
        Queue::fake();
        $owner = $this->user();
        $id = $this->upload($owner)->json('scan.id');

        $this->withToken($this->user()->issueToken('other'))
            ->getJson("/api/v1/invoices/scan/{$id}")
            ->assertStatus(404);
        $this->withToken($owner->issueToken('again'))
            ->getJson("/api/v1/invoices/scan/{$id}")
            ->assertOk()
            ->assertJsonPath('scan.id', $id)
            ->assertJsonPath('scan.status', 'queued')
            ->assertJsonPath('scan.result', null);
        $this->withToken($owner->issueToken('x'))
            ->getJson('/api/v1/invoices/scan/abc')
            ->assertStatus(404);
    }

    public function test_photo_is_read_and_lines_are_normalised(): void
    {
        Http::fake([self::GROQ => Http::response($this->reply($this->invoice()))]);
        $user = $this->user();

        // The test queue runs jobs inline, so the scan is read by now.
        $id = $this->upload($user)->assertStatus(202)->assertJsonPath('scan.status', 'done')->json('scan.id');

        $res = $this->withToken($user->issueToken('poll'))->getJson("/api/v1/invoices/scan/{$id}")
            ->assertOk()
            ->assertJsonPath('scan.status', 'done')
            ->assertJsonPath('scan.error', null)
            ->assertJsonPath('scan.result.supplier_name', 'Shree Ganesh Pharma Distributors')
            ->assertJsonPath('scan.result.supplier_gstin', '27ABCDE1234F1Z5')
            ->assertJsonPath('scan.result.invoice_no', 'SG/26-27/0456')
            ->assertJsonPath('scan.result.invoice_date', '2026-10-01')
            ->assertJsonPath('scan.result.notes', null)
            ->assertJsonCount(2, 'scan.result.items');

        $dolo = $res->json('scan.result.items.0');
        $this->assertSame('DOLO 650 TAB', $dolo['product_name']);
        $this->assertSame('2027-06-30', $dolo['expiry_date']);   // month-only expiry: end of month
        $this->assertSame('2025-07-01', $dolo['mfg_date']);
        $this->assertSame([10, 2], [$dolo['quantity'], $dolo['free_quantity']]);
        $this->assertEquals([30.91, 22.08, 5, 12], [$dolo['mrp'], $dolo['purchase_rate'], $dolo['discount_percent'], $dolo['gst_percent']]);
        $this->assertSame('30049099', $dolo['hsn']);
        $this->assertNull($dolo['barcode']);

        $azithral = $res->json('scan.result.items.1');
        $this->assertEquals(119.5, $azithral['mrp']);
        $this->assertNull($azithral['batch_no']);
        $this->assertNull($azithral['expiry_date']);
        $this->assertSame(0, $azithral['free_quantity']);
        $this->assertSame('8901234567894', $azithral['barcode']);

        $scan = InvoiceScan::findOrFail($id);
        $this->assertSame([2100, 900], [$scan->input_tokens, $scan->output_tokens]);
        $this->assertSame('qwen/qwen3.8-27b', $scan->model);

        Http::assertSentCount(1);
        Http::assertSent(function (HttpRequest $r) {
            [$system, $user] = $r['messages'];
            $format = $r['response_format'];
            $schema = $format['json_schema']['schema'];

            return $r->url() === self::GROQ
                && $r->hasHeader('Authorization', 'Bearer test-key')
                && $r['model'] === 'qwen/qwen3.8-27b'
                && $r['max_completion_tokens'] === 8192
                && $system['role'] === 'system'
                && $user['role'] === 'user'
                && count($user['content']) === 2
                && $user['content'][0]['type'] === 'image_url'
                && str_starts_with($user['content'][0]['image_url']['url'], 'data:image/jpeg;base64,')
                && $user['content'][1]['type'] === 'text'
                && $format['type'] === 'json_schema'
                && $format['json_schema']['strict'] === true
                && $schema['additionalProperties'] === false
                && $schema['required'] === array_keys($schema['properties'])
                && $schema['properties']['items']['items']['additionalProperties'] === false;
        });
    }

    public function test_an_oversized_photo_is_scaled_down_to_a_jpeg_before_sending(): void
    {
        Http::fake([self::GROQ => Http::response($this->reply($this->invoice()))]);
        // Noise doesn't compress: a PNG well over the AI service's image limit.
        $img = imagecreatetruecolor(1200, 1200);
        for ($y = 0; $y < 1200; $y++) {
            for ($x = 0; $x < 1200; $x++) {
                imagesetpixel($img, $x, $y, mt_rand(0, 0xFFFFFF));
            }
        }
        ob_start();
        imagepng($img, null, 0);
        $png = (string) ob_get_clean();
        $this->assertGreaterThan(GroqInvoiceReader::MAX_IMAGE_BYTES, strlen($png));

        $scan = $this->scanFor($this->user(), $png, 'image/png');
        $this->runJob($scan);

        $this->assertSame('done', $scan->refresh()->status);
        Http::assertSent(function (HttpRequest $r) {
            $url = $r['messages'][1]['content'][0]['image_url']['url'];
            $jpeg = base64_decode(substr($url, strlen('data:image/jpeg;base64,')), true);

            return str_starts_with($url, 'data:image/jpeg;base64,')
                && $jpeg !== false
                && strlen($jpeg) <= GroqInvoiceReader::MAX_IMAGE_BYTES
                && getimagesizefromstring($jpeg)['mime'] === 'image/jpeg';
        });
    }

    public function test_pdf_pages_are_sent_as_images(): void
    {
        Http::fake([self::GROQ => Http::response($this->reply($this->invoice()))]);
        $this->fakePdf(pages: 3);

        $this->upload($this->user(), UploadedFile::fake()->createWithContent('bill.pdf', "%PDF-1.4\n%%EOF"))
            ->assertStatus(202)
            ->assertJsonPath('scan.status', 'done');

        Http::assertSent(function (HttpRequest $r) {
            $content = $r['messages'][1]['content'];
            $images = array_filter($content, fn ($part) => $part['type'] === 'image_url'
                && str_starts_with($part['image_url']['url'], 'data:image/jpeg;base64,'));

            return count($content) === 4 && count($images) === 3 && end($content)['type'] === 'text';
        });
    }

    public function test_pdf_with_more_than_three_pages_is_refused_without_calling_the_api(): void
    {
        Http::fake();
        $this->fakePdf(pages: 4);

        $scan = $this->scanFor($this->user(), '%PDF-1.4', 'application/pdf');
        $this->runJob($scan)->assertNotReleased();

        $scan->refresh();
        $this->assertSame(['failed', 'too_many_pages'], [$scan->status, $scan->error_code]);
        $this->assertSame('This PDF has 4 pages. Scan up to 3 pages at a time.', $scan->error);
        Http::assertNothingSent();
    }

    public function test_pdf_fails_clearly_when_the_server_cannot_convert_it(): void
    {
        Http::fake();
        $this->fakePdf(pages: 1, broken: true);

        $scan = $this->scanFor($this->user(), '%PDF-1.4', 'application/pdf');
        $this->runJob($scan)->assertNotReleased();

        $scan->refresh();
        $this->assertSame(['failed', 'pdf_unsupported'], [$scan->status, $scan->error_code]);
        $this->assertStringContainsString('send a photo', $scan->error);
        Http::assertNothingSent();
    }

    public function test_lines_are_matched_to_the_shops_products_and_the_catalog(): void
    {
        Http::fake([self::GROQ => Http::response($this->reply($this->invoice()))]);
        $user = $this->user();
        $shop = app(ShopService::class)->forUser($user);
        $otherShop = app(ShopService::class)->forUser($this->user());
        $product = fn ($shopId, string $name) => Product::create([
            'id' => (string) Str::uuid(), 'shop_id' => $shopId, 'version' => 1,
            'name' => $name, 'name_norm' => Product::normalizeName($name), 'unit' => 'Strips',
        ]);
        $dolo = $product($shop->id, 'Dolo 650');           // typed without the form: still a match
        $product($otherShop->id, 'Azithral 500');            // another shop's: never a match
        $master = MedicineMaster::create([
            'name' => 'Azithral 500 Tablet', 'name_norm' => 'azithral 500 tablet',
            'manufacturer' => 'Alembic Pharmaceuticals Ltd', 'source' => 'seed',
        ]);

        $id = $this->upload($user)->json('scan.id');
        $items = InvoiceScan::findOrFail($id)->extracted['items'];

        $this->assertSame($dolo->id, $items[0]['match']['product_id']);
        $this->assertSame('Dolo 650', $items[0]['match']['product_name']);
        $this->assertNull($items[0]['match']['master_id']);
        $this->assertNull($items[1]['match']['product_id']);
        $this->assertSame($master->id, $items[1]['match']['master_id']);
        $this->assertSame('Alembic Pharmaceuticals Ltd', $items[1]['match']['master_manufacturer']);
    }

    public function test_malformed_model_output_fails_and_keeps_the_raw_text(): void
    {
        $garbage = 'Sorry, the photo is too blurry to read.';
        Http::fake([self::GROQ => Http::sequence()
            ->push($this->reply($garbage))
            ->push($this->reply('{"supplier_name": "ABC", "items": [{"product_name": "DOL'))]);
        $user = $this->user();

        foreach ([$garbage, '{"supplier_name": "ABC", "items": [{"product_name": "DOL'] as $raw) {
            $id = $this->upload($user)->assertStatus(202)->json('scan.id');
            $this->withToken($user->issueToken('p'))->getJson("/api/v1/invoices/scan/{$id}")
                ->assertJsonPath('scan.status', 'failed')
                ->assertJsonPath('scan.error_code', 'unreadable_output')
                ->assertJsonPath('scan.result', null)
                ->assertJsonMissingPath('scan.raw_output');
            $this->assertSame($raw, InvoiceScan::findOrFail($id)->raw_output);
        }
    }

    public function test_reply_without_any_medicine_line_fails_clearly(): void
    {
        $empty = ['supplier_name' => 'X', 'supplier_gstin' => '', 'invoice_no' => '', 'invoice_date' => '', 'items' => [], 'notes' => 'Not an invoice.'];
        Http::fake([self::GROQ => Http::response($this->reply($empty))]);

        $scan = $this->scanFor($this->user());
        $this->runJob($scan);

        $scan->refresh();
        $this->assertSame(['failed', 'no_items'], [$scan->status, $scan->error_code]);
        $this->assertNotNull($scan->raw_output);
    }

    public function test_missing_api_key_fails_with_a_clear_status_without_calling_the_api(): void
    {
        Http::fake();
        config(['services.groq.key' => null]);
        $user = $this->user();

        $id = $this->upload($user)->assertStatus(202)->json('scan.id');

        $this->withToken($user->issueToken('p'))->getJson("/api/v1/invoices/scan/{$id}")
            ->assertJsonPath('scan.status', 'failed')
            ->assertJsonPath('scan.error_code', 'not_configured');
        $this->assertStringContainsString('not set up', InvoiceScan::findOrFail($id)->error);
        Http::assertNothingSent();
    }

    public function test_refusal_and_cut_off_replies_fail_cleanly(): void
    {
        Http::fake([self::GROQ => Http::sequence()
            ->push($this->reply('', refusal: 'I can\'t help with that.'))
            ->push($this->reply('{"supplier_name": "ABC", "items": [', 'length'))]);
        $user = $this->user();

        $refused = $this->scanFor($user);
        $this->runJob($refused);
        $this->assertSame(['failed', 'refused'], [$refused->refresh()->status, $refused->error_code]);

        $long = $this->scanFor($user);
        $this->runJob($long);
        $this->assertSame(['failed', 'too_long'], [$long->refresh()->status, $long->error_code]);
        $this->assertSame('{"supplier_name": "ABC", "items": [', $long->raw_output);
    }

    public function test_busy_api_is_retried_within_the_request(): void
    {
        Http::fake([self::GROQ => Http::sequence()
            ->push(['error' => ['type' => 'rate_limit_exceeded', 'message' => 'Rate limit reached']], 429, ['retry-after' => '2'])
            ->push($this->reply($this->invoice()))]);

        $scan = $this->scanFor($this->user());
        $this->runJob($scan)->assertNotReleased();

        $this->assertSame('done', $scan->refresh()->status);
        Http::assertSentCount(2);
    }

    public function test_long_outage_releases_the_job_then_fails_on_the_last_attempt(): void
    {
        Http::fake([self::GROQ => Http::response(['error' => ['type' => 'internal_server_error', 'message' => 'Service unavailable']], 503)]);
        $scan = $this->scanFor($this->user());

        $this->runJob($scan, attempt: 1)->assertReleased(30);
        $this->assertSame('queued', $scan->refresh()->status);

        $this->runJob($scan, attempt: 3)->assertNotReleased();
        $scan->refresh();
        $this->assertSame(['failed', 'busy'], [$scan->status, $scan->error_code]);
        $this->assertSame(3, $scan->attempts);
    }

    public function test_bad_api_key_fails_without_retrying(): void
    {
        Http::fake([self::GROQ => Http::response(['error' => ['type' => 'invalid_request_error', 'message' => 'Invalid API Key']], 401)]);
        $scan = $this->scanFor($this->user());

        $this->runJob($scan)->assertNotReleased();

        $this->assertSame(['failed', 'auth'], [$scan->refresh()->status, $scan->error_code]);
        Http::assertSentCount(1);
    }

    public function test_a_scan_nobody_picks_up_fails_instead_of_waiting_forever(): void
    {
        Queue::fake(); // no worker running
        $user = $this->user();
        $id = $this->upload($user)->json('scan.id');
        $poll = fn () => $this->withToken($user->issueToken('p'))->getJson("/api/v1/invoices/scan/{$id}");

        $this->travel(10)->minutes();
        $poll()->assertJsonPath('scan.status', 'queued');

        $this->travel(10)->minutes();
        $poll()->assertJsonPath('scan.status', 'failed')->assertJsonPath('scan.error_code', 'stalled');

        // A worker that turns up late leaves it alone (no paid API call).
        Http::fake();
        $this->runJob(InvoiceScan::findOrFail($id));
        Http::assertNothingSent();
        $this->assertSame('stalled', InvoiceScan::findOrFail($id)->error_code);
    }

    public function test_upload_is_throttled_per_account(): void
    {
        Queue::fake();
        $user = $this->user();

        for ($i = 0; $i < 6; $i++) {
            $this->upload($user)->assertStatus(202);
        }
        $this->upload($user)->assertStatus(429)->assertHeader('Retry-After');
        $this->assertSame(6, InvoiceScan::count());
        // Another account has its own allowance.
        $this->upload($this->user())->assertStatus(202);
    }
}
