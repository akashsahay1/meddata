<?php

namespace App\Services;

use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\PendingRequest;
use Illuminate\Http\Client\RequestException;
use Illuminate\Http\Client\Response;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Throwable;

/**
 * Reads a purchase invoice (photo or PDF) with Groq through its
 * OpenAI-compatible chat completions API and returns the normalised lines.
 *
 * A PDF made by billing software carries its text: that text (PdfText) goes
 * to a text model, which only has to sort exact characters into columns:
 * every batch number right, a 48-line bill in ~15 s, a fifth of the cost.
 * A photo, or a PDF that is only a scan, goes to the vision model as images
 * (PdfToImages: one JPEG per page, at most 3 pages). Strict structured
 * outputs (a JSON schema) keep the reply machine-readable; the result is
 * still validated and normalised, because a cut-off reply can break it.
 *
 * Config: services.groq (GROQ_API_KEY, GROQ_MODEL, GROQ_TEXT_MODEL, ...).
 */
class GroqInvoiceReader
{
    /** HTTP statuses worth retrying: timeouts, rate limits, flex capacity, server errors. */
    private const TRANSIENT = [408, 429, 498, 500, 502, 503, 504];

    /**
     * Largest image file sent as is. Groq has capped base64 images at 4 MB;
     * base64 adds a third, so 3 MB of file stays under it. Bigger photos are
     * scaled down (the app already sends ~2576 px JPEGs, so this is rare).
     */
    public const MAX_IMAGE_BYTES = 3_000_000;

    private const SYSTEM = 'You transcribe purchase invoices (supplier bills) of Indian pharmacies into '
        .'structured data for the shop\'s inventory software. The shop owner reviews every line '
        .'before it is saved, so a blank is better than a guess: a wrong batch number, expiry date '
        .'or price is worse than a missing one.';

    private const INSTRUCTIONS = <<<'TXT'
        Read this purchase invoice and fill in the JSON.

        Header
        - supplier_name, supplier_gstin: the seller (distributor/wholesaler), not the pharmacy the bill is addressed to.
        - invoice_no, invoice_date (YYYY-MM-DD).

        items: one entry per product line, in printed order, across all pages (one image per page, in order). Leave out rows that are not products (totals, taxes, discounts, round-off, freight, outstanding balance, credit notes).
        - product_name: as printed, with strength and form (e.g. "DOLO 650 TAB") but without the pack size.
        - manufacturer: the company if the line shows it (often a short code like "MICRO"), else "".
        - pack: as printed, e.g. "15's", "1x10", "100ML".
        - batch_no: exactly as printed, every character.
        - expiry_date, mfg_date: "YYYY-MM" when only month and year are printed ("06/27" is "2027-06"), "YYYY-MM-DD" for a full date.
        - quantity: billed quantity in packs. free_quantity: free/scheme packs ("10+2" means quantity 10, free_quantity 2), 0 when none.
        - mrp: MRP per pack. purchase_rate: the shop's rate per pack (Rate/PTR) before discount and GST.
        - discount_percent: the line's discount as a percentage, null when none.
        - gst_percent: the line's total GST rate (CGST + SGST, or IGST), e.g. 12.
        - hsn: the HSN code. barcode: only if a barcode number is printed for the line.

        Use "" for text and null for numbers that are not printed or that you cannot read with confidence.
        notes: one or two sentences on anything the reviewer should double-check (unreadable or cut-off parts, a missing page, totals that don't add up), or "" if none.
        TXT;

    public function __construct(
        private readonly InvoiceNormalizer $normalizer,
        private readonly PdfToImages $pdf,
        private readonly PdfText $pdfText,
    ) {}

    public function isConfigured(): bool
    {
        return filled(config('services.groq.key'));
    }

    /**
     * @return array{data: array, model: ?string, input_tokens: ?int, output_tokens: ?int}
     *
     * @throws InvoiceReadException
     */
    public function read(string $bytes, string $mime): array
    {
        if (! $this->isConfigured()) {
            throw new InvoiceReadException('not_configured', 'AI invoice reading is not set up on the server yet.');
        }

        $payload = $this->payload($bytes, $mime);

        try {
            $response = $this->client()->post('/chat/completions', $payload);
        } catch (ConnectionException $e) {
            Log::warning('Invoice scan: Groq API unreachable: '.$e->getMessage());
            throw new InvoiceReadException('network', 'Could not reach the AI service.', retryable: true, previous: $e);
        }

        if ($response->failed()) {
            throw $this->httpError($response);
        }

        return $this->parse((array) $response->json());
    }

    /**
     * The chat completions request body: the PDF's own text when it has
     * some, else the page images.
     *
     * @throws InvoiceReadException when a PDF can't be turned into images
     */
    public function payload(string $bytes, string $mime): array
    {
        $text = $mime === 'application/pdf' ? $this->pdfText->extract($bytes) : null;
        if ($text !== null) {
            return $this->request(
                (string) config('services.groq.text_model', 'openai/gpt-oss-120b'),
                (int) config('services.groq.text_max_tokens', 16384),
                'The invoice below is the text of a PDF, extracted with its layout kept: columns line up by '
                    .'position and pages are separated by form feeds. '.self::INSTRUCTIONS."\n\nINVOICE TEXT:\n".$text,
                // Sorting text into columns needs little thought; low keeps
                // the reply (and the bill) about a fifth smaller.
                ['reasoning_effort' => 'low'],
            );
        }

        $images = $mime === 'application/pdf' ? $this->pdf->convert($bytes) : [$bytes];

        // The images go before the instructions (works best for vision).
        $content = array_map(fn (string $image) => [
            'type' => 'image_url',
            'image_url' => ['url' => $this->dataUrl($image)],
        ], $images);
        $content[] = ['type' => 'text', 'text' => self::INSTRUCTIONS];

        return $this->request(
            (string) config('services.groq.model', 'qwen/qwen3.8-27b'),
            (int) config('services.groq.max_tokens', 8192),
            $content,
        );
    }

    private function request(string $model, int $maxTokens, string|array $content, array $extra = []): array
    {
        return [
            'model' => $model,
            'max_completion_tokens' => $maxTokens,
            'messages' => [
                ['role' => 'system', 'content' => self::SYSTEM],
                ['role' => 'user', 'content' => $content],
            ],
            'response_format' => [
                'type' => 'json_schema',
                'json_schema' => ['name' => 'purchase_invoice', 'strict' => true, 'schema' => self::schema()],
            ],
        ] + $extra;
    }

    /**
     * Strict structured outputs need every field in `required` and no extra
     * properties. Text may be null too: the text model writes null for a
     * blank, and Groq rejects the whole reply when the schema forbids it.
     */
    public static function schema(): array
    {
        $text = ['type' => ['string', 'null']];
        $number = ['type' => ['number', 'null']];
        $item = [
            'type' => 'object',
            'properties' => [
                'product_name' => $text,
                'manufacturer' => $text,
                'pack' => $text,
                'batch_no' => $text,
                'expiry_date' => $text,
                'mfg_date' => $text,
                'quantity' => $number,
                'free_quantity' => $number,
                'mrp' => $number,
                'purchase_rate' => $number,
                'discount_percent' => $number,
                'gst_percent' => $number,
                'hsn' => $text,
                'barcode' => $text,
            ],
        ];
        $item['required'] = array_keys($item['properties']);
        $item['additionalProperties'] = false;

        $schema = [
            'type' => 'object',
            'properties' => [
                'supplier_name' => $text,
                'supplier_gstin' => $text,
                'invoice_no' => $text,
                'invoice_date' => $text,
                'items' => ['type' => 'array', 'items' => $item],
                'notes' => $text,
            ],
        ];
        $schema['required'] = array_keys($schema['properties']);
        $schema['additionalProperties'] = false;

        return $schema;
    }

    /**
     * A JPEG or PNG within MAX_IMAGE_BYTES goes as is; anything else (WebP,
     * an oversized photo) is re-encoded as a JPEG, scaled down until it fits.
     */
    private function dataUrl(string $bytes): string
    {
        $mime = getimagesizefromstring($bytes)['mime'] ?? null;
        if (in_array($mime, ['image/jpeg', 'image/png'], true) && strlen($bytes) <= self::MAX_IMAGE_BYTES) {
            return "data:{$mime};base64,".base64_encode($bytes);
        }

        $src = @imagecreatefromstring($bytes);
        if ($src === false) {
            throw new InvoiceReadException('bad_request',
                'The AI service could not read this file. Try a clear JPG/PNG photo or a PDF.');
        }
        [$w, $h] = [imagesx($src), imagesy($src)];
        $scale = min(1.0, sqrt(self::MAX_IMAGE_BYTES / max(1, strlen($bytes))));
        do {
            $dst = imagecreatetruecolor(max(1, (int) ($w * $scale)), max(1, (int) ($h * $scale)));
            imagefill($dst, 0, 0, imagecolorallocate($dst, 255, 255, 255));   // transparency → white
            imagecopyresampled($dst, $src, 0, 0, 0, 0, imagesx($dst), imagesy($dst), $w, $h);
            ob_start();
            imagejpeg($dst, null, 85);
            $jpeg = (string) ob_get_clean();
            $scale *= 0.8;
        } while (strlen($jpeg) > self::MAX_IMAGE_BYTES);

        return 'data:image/jpeg;base64,'.base64_encode($jpeg);
    }

    private function client(): PendingRequest
    {
        // Quick in-request retries for rate limits / overload; longer outages
        // are retried by the queue (ProcessInvoiceScan::backoff).
        return Http::baseUrl(rtrim((string) config('services.groq.base_url'), '/'))
            ->withToken((string) config('services.groq.key'))
            ->acceptJson()
            ->asJson()
            ->connectTimeout(15)
            ->timeout((int) config('services.groq.timeout', 120))
            ->retry(3, fn (int $attempt, mixed $e) => $this->retryDelay($attempt, $e),
                fn (Throwable $e) => $this->isTransient($e), throw: false);
    }

    private function isTransient(Throwable $e): bool
    {
        return $e instanceof RequestException && in_array($e->response->status(), self::TRANSIENT, true)
            && ! $this->overPlanLimit($e->response);
    }

    /**
     * A 429 for one request bigger than the account's per-minute allowance
     * (e.g. the free tier's 1,000 output tokens a minute): waiting never helps.
     */
    private function overPlanLimit(Response $response): bool
    {
        return $response->status() === 429
            && str_contains((string) $response->json('error.message'), 'Request too large');
    }

    /** Milliseconds before the next try: the server's retry-after in seconds (capped), else 2 s, 6 s. */
    private function retryDelay(int $attempt, mixed $e): int
    {
        $after = $e instanceof RequestException ? (int) $e->response->header('retry-after') : 0;

        return $after > 0 ? min($after, 30) * 1000 : [2000, 6000][$attempt - 1] ?? 6000;
    }

    private function httpError(Response $response): InvoiceReadException
    {
        $status = $response->status();
        Log::warning('Invoice scan: Groq API error', [
            'status' => $status,
            'type' => $response->json('error.type'),
            'message' => $response->json('error.message'),
        ]);

        return match (true) {
            $this->overPlanLimit($response) => new InvoiceReadException(
                'ai_limit', 'This invoice is too long for the AI service\'s current plan. Please contact Medikabiz support.'),
            in_array($status, self::TRANSIENT, true) => new InvoiceReadException(
                'busy', 'The AI service is busy right now.', retryable: true),
            in_array($status, [401, 403], true) => new InvoiceReadException(
                'auth', 'The AI service did not accept the server\'s API key.'),
            $status === 413 => new InvoiceReadException(
                'too_large', 'This file is too large for the AI service. Try a smaller photo or fewer pages.'),
            default => new InvoiceReadException(
                'bad_request', 'The AI service could not read this file. Try a clear JPG/PNG photo or a PDF.'),
        };
    }

    /** @return array{data: array, model: ?string, input_tokens: ?int, output_tokens: ?int} */
    private function parse(array $body): array
    {
        $choice = $body['choices'][0] ?? [];
        $text = is_string($choice['message']['content'] ?? null) ? $choice['message']['content'] : '';
        $raw = $text !== '' ? $text : null;

        $refusal = $choice['message']['refusal'] ?? null;
        if (filled($refusal) || ($choice['finish_reason'] ?? null) === 'content_filter') {
            throw new InvoiceReadException('refused',
                'The AI declined to read this file. Try a clear photo of the invoice.',
                raw: is_string($refusal) ? $refusal : $raw);
        }
        if (($choice['finish_reason'] ?? null) === 'length') {
            throw new InvoiceReadException('too_long',
                'This invoice is too long to read in one go. Scan fewer pages at a time.', raw: $raw);
        }

        $decoded = $this->decode($text);
        if ($decoded === null) {
            throw new InvoiceReadException('unreadable_output',
                'The AI reply could not be understood. Please try again.', raw: $raw, slip: true);
        }

        $data = $this->normalizer->normalize($decoded);
        if ($data['items'] === []) {
            throw new InvoiceReadException('no_items',
                'No medicines were found on this invoice. Try a clear, flat photo of the whole page.', raw: $raw, slip: true);
        }

        return [
            'data' => $data,
            'model' => isset($body['model']) ? (string) $body['model'] : null,
            'input_tokens' => isset($body['usage']['prompt_tokens']) ? (int) $body['usage']['prompt_tokens'] : null,
            'output_tokens' => isset($body['usage']['completion_tokens']) ? (int) $body['usage']['completion_tokens'] : null,
        ];
    }

    /** The JSON object in the reply, tolerating a code fence or stray text around it. */
    private function decode(string $text): ?array
    {
        $decoded = json_decode(trim($text), true);
        if (! is_array($decoded) && preg_match('/\{.*\}/s', $text, $m)) {
            $decoded = json_decode($m[0], true);
        }

        return is_array($decoded) && array_is_list($decoded) === false ? $decoded : null;
    }
}
