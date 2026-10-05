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
 * Reads a purchase invoice (photo or PDF) with the Claude Messages API and
 * returns the normalised lines. Structured outputs (a JSON schema) keep the
 * reply machine-readable; the result is still validated and normalised,
 * because a refusal or a cut-off reply can break the schema.
 *
 * Config: services.anthropic (ANTHROPIC_API_KEY, ANTHROPIC_MODEL, ...).
 */
class ClaudeInvoiceReader
{
    public const API_VERSION = '2023-06-01';

    /** Beta header for `fallbacks: "default"` (server-side refusal fallback). */
    public const FALLBACK_BETA = 'server-side-fallback-2026-07-01';

    /** Models that accept `fallbacks: "default"`. */
    private const FALLBACK_MODELS = ['claude-opus-5-5', 'claude-opus-5', 'claude-fable-5-1', 'claude-sonnet-5-5'];

    /** HTTP statuses worth retrying: timeouts, rate limits, overload, server errors. */
    private const TRANSIENT = [408, 409, 429, 500, 502, 503, 504, 529];

    private const SYSTEM = 'You transcribe purchase invoices (supplier bills) of Indian pharmacies into '
        .'structured data for the shop\'s inventory software. The shop owner reviews every line '
        .'before it is saved, so a blank is better than a guess: a wrong batch number, expiry date '
        .'or price is worse than a missing one.';

    private const INSTRUCTIONS = <<<'TXT'
        Read this purchase invoice and fill in the JSON.

        Header
        - supplier_name, supplier_gstin: the seller (distributor/wholesaler), not the pharmacy the bill is addressed to.
        - invoice_no, invoice_date (YYYY-MM-DD).

        items: one entry per product line, in printed order, across all pages. Leave out rows that are not products (totals, taxes, discounts, round-off, freight, outstanding balance, credit notes).
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

    public function __construct(private readonly InvoiceNormalizer $normalizer) {}

    public function isConfigured(): bool
    {
        return filled(config('services.anthropic.key'));
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

        try {
            $response = $this->client()->post('/v1/messages', $this->payload($bytes, $mime));
        } catch (ConnectionException $e) {
            Log::warning('Invoice scan: Claude API unreachable: '.$e->getMessage());
            throw new InvoiceReadException('network', 'Could not reach the AI service.', retryable: true, previous: $e);
        }

        if ($response->failed()) {
            throw $this->httpError($response);
        }

        return $this->parse((array) $response->json());
    }

    /** The Messages API request body. */
    public function payload(string $bytes, string $mime): array
    {
        $source = ['type' => 'base64', 'media_type' => $mime, 'data' => base64_encode($bytes)];
        $file = $mime === 'application/pdf'
            ? ['type' => 'document', 'source' => $source]
            : ['type' => 'image', 'source' => $source];

        $outputConfig = ['format' => ['type' => 'json_schema', 'schema' => self::schema()]];
        if (filled($effort = config('services.anthropic.effort'))) {
            $outputConfig['effort'] = $effort;
        }

        $payload = [
            'model' => $this->model(),
            'max_tokens' => (int) config('services.anthropic.max_tokens', 16000),
            'system' => self::SYSTEM,
            // The file goes before the instructions (works best for vision).
            'messages' => [[
                'role' => 'user',
                'content' => [$file, ['type' => 'text', 'text' => self::INSTRUCTIONS]],
            ]],
            'output_config' => $outputConfig,
        ];
        if ($this->usesFallbacks()) {
            $payload['fallbacks'] = 'default';
        }

        return $payload;
    }

    /**
     * Every field is required (blank = "" / null) so the schema stays within
     * the structured-output limits on optional and nullable parameters.
     */
    public static function schema(): array
    {
        $text = ['type' => 'string'];
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

    private function model(): string
    {
        return (string) config('services.anthropic.model', 'claude-opus-5-5');
    }

    private function usesFallbacks(): bool
    {
        return config('services.anthropic.fallbacks') === 'default'
            && in_array($this->model(), self::FALLBACK_MODELS, true);
    }

    private function client(): PendingRequest
    {
        $headers = [
            'x-api-key' => (string) config('services.anthropic.key'),
            'anthropic-version' => self::API_VERSION,
        ];
        if ($this->usesFallbacks()) {
            $headers['anthropic-beta'] = self::FALLBACK_BETA;
        }

        // Quick in-request retries for rate limits / overload; longer outages
        // are retried by the queue (ProcessInvoiceScan::backoff).
        return Http::baseUrl(rtrim((string) config('services.anthropic.base_url'), '/'))
            ->withHeaders($headers)
            ->acceptJson()
            ->asJson()
            ->connectTimeout(15)
            ->timeout((int) config('services.anthropic.timeout', 240))
            ->retry(3, fn (int $attempt, mixed $e) => $this->retryDelay($attempt, $e),
                fn (Throwable $e) => $this->isTransient($e), throw: false);
    }

    private function isTransient(Throwable $e): bool
    {
        return $e instanceof RequestException && in_array($e->response->status(), self::TRANSIENT, true);
    }

    /** Milliseconds before the next try: the server's retry-after (capped), else 2 s, 6 s. */
    private function retryDelay(int $attempt, mixed $e): int
    {
        $after = $e instanceof RequestException ? (int) $e->response->header('retry-after') : 0;

        return $after > 0 ? min($after, 30) * 1000 : [2000, 6000][$attempt - 1] ?? 6000;
    }

    private function httpError(Response $response): InvoiceReadException
    {
        $status = $response->status();
        Log::warning('Invoice scan: Claude API error', [
            'status' => $status,
            'type' => $response->json('error.type'),
            'message' => $response->json('error.message'),
        ]);

        return match (true) {
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
        // Read blocks by type: thinking (and fallback markers) may come first.
        $text = collect($body['content'] ?? [])
            ->filter(fn ($block) => is_array($block) && ($block['type'] ?? null) === 'text')
            ->pluck('text')
            ->implode('');
        $raw = $text !== '' ? $text : null;

        $stop = $body['stop_reason'] ?? null;
        if ($stop === 'refusal') {
            throw new InvoiceReadException('refused',
                'The AI declined to read this file. Try a clear photo of the invoice.', raw: $raw);
        }
        if ($stop === 'max_tokens') {
            throw new InvoiceReadException('too_long',
                'This invoice is too long to read in one go. Scan fewer pages at a time.', raw: $raw);
        }

        $decoded = $this->decode($text);
        if ($decoded === null) {
            throw new InvoiceReadException('unreadable_output',
                'The AI reply could not be understood. Please try again.', raw: $raw);
        }

        $data = $this->normalizer->normalize($decoded);
        if ($data['items'] === []) {
            throw new InvoiceReadException('no_items',
                'No medicines were found on this invoice. Try a clear, flat photo of the whole page.', raw: $raw);
        }

        return [
            'data' => $data,
            'model' => isset($body['model']) ? (string) $body['model'] : null,
            'input_tokens' => isset($body['usage']['input_tokens']) ? (int) $body['usage']['input_tokens'] : null,
            'output_tokens' => isset($body['usage']['output_tokens']) ? (int) $body['usage']['output_tokens'] : null,
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
