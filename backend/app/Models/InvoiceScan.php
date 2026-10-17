<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Prunable;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Facades\Storage;

/**
 * One uploaded purchase invoice (photo or PDF) and what the AI read from it.
 * Shop-scoped: a scan is only ever visible to its own shop.
 */
class InvoiceScan extends Model
{
    use Prunable;

    public const STATUS_QUEUED = 'queued';

    public const STATUS_PROCESSING = 'processing';

    public const STATUS_DONE = 'done';

    public const STATUS_FAILED = 'failed';

    /** The private disk uploads are stored on (storage/app/private). */
    public const DISK = 'local';

    /** Scans and their files are deleted after this many days. */
    public const KEEP_DAYS = 30;

    /**
     * A scan is given up on (so the app stops waiting) when nothing at all
     * has happened on the queue for this long: no queue worker running.
     * A bill waiting behind others, or for a busy AI service, is not stuck.
     */
    public const STALL_MINUTES = 15;

    /**
     * Failures that may well work on another try of the same file (POST
     * /invoices/scan/{id}/retry). Not: a file the server can't open, a PDF
     * with too many pages, a refused or oversized file, a missing API key.
     */
    public const RETRYABLE = ['busy', 'network', 'timeout', 'error', 'stalled', 'no_items', 'unreadable_output', 'bad_request', 'ai_limit'];

    protected $guarded = [];

    protected $hidden = ['file_path', 'raw_output'];

    protected function casts(): array
    {
        return [
            'extracted' => 'array',
            'started_at' => 'datetime',
            'finished_at' => 'datetime',
            'closed_at' => 'datetime',
        ];
    }

    public function shop(): BelongsTo
    {
        return $this->belongsTo(Shop::class);
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function isFinished(): bool
    {
        return in_array($this->status, [self::STATUS_DONE, self::STATUS_FAILED], true);
    }

    public function markFailed(string $code, string $message, ?string $raw = null): void
    {
        $this->forceFill([
            'status' => self::STATUS_FAILED,
            'error_code' => $code,
            'error' => $message,
            'raw_output' => $raw ?? $this->raw_output,
            'finished_at' => now(),
        ])->save();
    }

    /** Waiting for another try after a busy AI service. */
    public function isRetrying(): bool
    {
        return $this->status === self::STATUS_QUEUED && $this->attempts > 0;
    }

    /** Failed, and reading the same file again may work. */
    public function canRetry(): bool
    {
        return $this->status === self::STATUS_FAILED && in_array($this->error_code, self::RETRYABLE, true);
    }

    public function failIfStalled(): void
    {
        $since = now()->subMinutes(self::STALL_MINUTES);
        if ($this->isFinished() || ! $this->updated_at?->lt($since)) {
            return;
        }
        // The worker touches each scan it picks up, retries or finishes.
        if (self::query()->where('updated_at', '>=', $since)->exists()) {
            return;
        }
        $this->markFailed('stalled', 'The server could not read this invoice in time. Please try again.');
    }

    /** The shape the app polls for. */
    public function toApiArray(): array
    {
        return [
            'id' => $this->id,
            'status' => $this->status,
            'error_code' => $this->error_code,
            'error' => $this->error,
            'retrying' => $this->isRetrying(),
            'can_retry' => $this->canRetry(),
            'result' => $this->status === self::STATUS_DONE ? $this->extracted : null,
            'created_at' => $this->created_at?->toIso8601String(),
            'finished_at' => $this->finished_at?->toIso8601String(),
        ];
    }

    /** A row of the shop's list of bills: no lines, just what to show. */
    public function toListArray(): array
    {
        $done = $this->status === self::STATUS_DONE;

        return [
            'id' => $this->id,
            'status' => $this->status,
            'retrying' => $this->isRetrying(),
            'can_retry' => $this->canRetry(),
            'error' => $this->error,
            'file_name' => $this->original_name,
            'supplier_name' => $done ? ($this->extracted['supplier_name'] ?? null) : null,
            'invoice_no' => $done ? ($this->extracted['invoice_no'] ?? null) : null,
            'items_count' => $done ? count($this->extracted['items'] ?? []) : null,
            'created_at' => $this->created_at?->toIso8601String(),
        ];
    }

    /** `php artisan model:prune` (scheduled daily) removes old scans. */
    public function prunable(): Builder
    {
        return static::where('created_at', '<', now()->subDays(self::KEEP_DAYS));
    }

    protected function pruning(): void
    {
        Storage::disk(self::DISK)->delete($this->file_path);
    }
}
