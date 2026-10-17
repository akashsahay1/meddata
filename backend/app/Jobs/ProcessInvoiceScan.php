<?php

namespace App\Jobs;

use App\Models\InvoiceScan;
use App\Services\GroqInvoiceReader;
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
 * Bills are read one after another by the queue worker. A busy, limited or
 * unreachable AI service is waited out (see backoff) for up to WAIT_HOURS,
 * so a pile of bills uploaded together is read as Groq's limits allow,
 * overnight if need be. A reply with no lines or broken JSON is read again
 * at once, up to SLIP_TRIES reads. Everything else fails the scan with a
 * message the app shows as-is. While a retry waits the scan is back to
 * `queued` with attempts > 0, which the app shows as "trying again".
 */
class ProcessInvoiceScan implements ShouldQueue
{
    use Queueable;

    /** Reads of the same file when the model slips (no lines found, broken JSON). */
    public const SLIP_TRIES = 3;

    /** How long a bill keeps waiting for a busy or limited AI service. */
    public const WAIT_HOURS = 24;

    /** Unix time after which a busy AI service is no longer waited for. */
    public int $deadline;

    /** Seconds; above the API call timeout (services.groq.timeout) plus PDF conversion. */
    public int $timeout = 300;

    /** A file that timed out once would only time out again. */
    public bool $failOnTimeout = true;

    public bool $deleteWhenMissingModels = true;

    public function __construct(public InvoiceScan $scan)
    {
        $this->deadline = now()->addHours(self::WAIT_HOURS)->getTimestamp();
    }

    /** The worker keeps the job while this is ahead (attempts don't count). */
    public function retryUntil(): int
    {
        return $this->deadline;
    }

    /**
     * Seconds to wait before the 2nd, 3rd, ... attempt when the AI service is
     * busy: quick at first (a per-minute limit clears in a minute), then every
     * 5 minutes (a daily limit, or a long queue of other bills).
     */
    public function backoff(): array
    {
        return [15, 30, 45, 60, 60, 90, 90, 120, 120, 300];
    }

    public function handle(GroqInvoiceReader $reader, InvoiceProductMatcher $matcher): void
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
            $result = $this->read($reader, (string) $disk->get($scan->file_path), $scan->mime);
        } catch (InvoiceReadException $e) {
            if ($e->retryable && now()->getTimestamp() < $this->deadline) {
                $scan->forceFill(['status' => InvoiceScan::STATUS_QUEUED])->save();
                $backoff = $this->backoff();
                $this->release($backoff[min($this->attempts(), count($backoff)) - 1]);

                return;
            }
            $message = in_array($e->errorCode, ['busy', 'network'], true)
                ? $e->getMessage().' Please try again in a few minutes.' : $e->getMessage();
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

    /** The model sometimes slips on a page it reads fine the next time. */
    private function read(GroqInvoiceReader $reader, string $bytes, string $mime): array
    {
        for ($read = 1; ; $read++) {
            try {
                return $reader->read($bytes, $mime);
            } catch (InvoiceReadException $e) {
                if (! $e->slip || $read >= self::SLIP_TRIES) {
                    throw $e;
                }
            }
        }
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
