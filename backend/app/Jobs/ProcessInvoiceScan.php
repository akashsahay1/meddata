<?php

namespace App\Jobs;

use App\Models\InvoiceScan;
use App\Services\ClaudeInvoiceReader;
use App\Services\InvoiceProductMatcher;
use App\Services\InvoiceReadException;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;
use Illuminate\Queue\TimeoutExceededException;
use Illuminate\Support\Facades\Storage;
use Throwable;

/**
 * Reads one uploaded purchase invoice with the AI and stores the normalised
 * lines (with product / catalog matches) on the scan. Needs a queue worker
 * (`php artisan queue:work`, under supervisor in production).
 *
 * A busy or unreachable AI service is retried (see backoff); everything else
 * fails the scan at once with a message the app shows as-is.
 */
class ProcessInvoiceScan implements ShouldQueue
{
    use Queueable;

    public int $tries = 3;

    /** Seconds; above the API call timeout (services.anthropic.timeout). */
    public int $timeout = 300;

    /** A file that timed out once would only time out again. */
    public bool $failOnTimeout = true;

    public bool $deleteWhenMissingModels = true;

    public function __construct(public InvoiceScan $scan) {}

    /** Seconds to wait before the 2nd and 3rd attempt. */
    public function backoff(): array
    {
        return [30, 120];
    }

    public function handle(ClaudeInvoiceReader $reader, InvoiceProductMatcher $matcher): void
    {
        $scan = $this->scan->refresh();
        if ($scan->isFinished()) {
            return;
        }

        if (! $reader->isConfigured()) {
            $scan->markFailed('not_configured',
                'AI invoice reading is not set up on the server yet. Please add the medicines by hand for now.');

            return;
        }

        $disk = Storage::disk(InvoiceScan::DISK);
        if (! $disk->exists($scan->file_path)) {
            $scan->markFailed('file_missing', 'The uploaded file is missing. Please upload it again.');

            return;
        }

        $scan->forceFill([
            'status' => InvoiceScan::STATUS_PROCESSING,
            'attempts' => $this->attempts(),
            'started_at' => $scan->started_at ?? now(),
        ])->save();

        try {
            $result = $reader->read((string) $disk->get($scan->file_path), $scan->mime);
        } catch (InvoiceReadException $e) {
            if ($e->retryable && $this->attempts() < $this->tries) {
                $scan->forceFill(['status' => InvoiceScan::STATUS_QUEUED])->save();
                $this->release($this->backoff()[$this->attempts() - 1] ?? 120);

                return;
            }
            $message = $e->retryable ? $e->getMessage().' Please try again in a few minutes.' : $e->getMessage();
            $scan->markFailed($e->errorCode, $message, $e->raw);

            return;
        }

        $data = $result['data'];
        $data['items'] = $matcher->annotate($scan->shop, $data['items']);

        $scan->forceFill([
            'status' => InvoiceScan::STATUS_DONE,
            'error_code' => null,
            'error' => null,
            'extracted' => $data,
            'model' => $result['model'],
            'input_tokens' => $result['input_tokens'],
            'output_tokens' => $result['output_tokens'],
            'finished_at' => now(),
        ])->save();
    }

    /** Out of attempts, timed out or crashed: never leave the app polling forever. */
    public function failed(?Throwable $e): void
    {
        $scan = $this->scan->fresh();
        if ($scan && ! $scan->isFinished()) {
            $scan->markFailed(
                $e instanceof TimeoutExceededException ? 'timeout' : 'error',
                $e instanceof TimeoutExceededException
                    ? 'Reading this invoice took too long. Try a clearer photo or fewer pages.'
                    : 'Reading the invoice failed. Please try again.',
            );
        }
    }
}
