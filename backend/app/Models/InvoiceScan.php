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
     * A scan with no progress for this long is given up on (no queue worker
     * running?), so the app stops waiting. Retries and the job's 300 s
     * timeout fit well inside it.
     */
    public const STALL_MINUTES = 15;

    protected $guarded = [];

    protected $hidden = ['file_path', 'raw_output'];

    protected function casts(): array
    {
        return [
            'extracted' => 'array',
            'started_at' => 'datetime',
            'finished_at' => 'datetime',
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

    public function failIfStalled(): void
    {
        if (! $this->isFinished() && $this->updated_at?->lt(now()->subMinutes(self::STALL_MINUTES))) {
            $this->markFailed('stalled', 'The server could not read this invoice in time. Please try again.');
        }
    }

    /** The shape the app polls for. */
    public function toApiArray(): array
    {
        return [
            'id' => $this->id,
            'status' => $this->status,
            'error_code' => $this->error_code,
            'error' => $this->error,
            'result' => $this->status === self::STATUS_DONE ? $this->extracted : null,
            'created_at' => $this->created_at?->toIso8601String(),
            'finished_at' => $this->finished_at?->toIso8601String(),
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
