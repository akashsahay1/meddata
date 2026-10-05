<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Jobs\ProcessInvoiceScan;
use App\Models\InvoiceScan;
use App\Services\EntitlementService;
use App\Services\ShopService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

/**
 * AI purchase-invoice reading. The app uploads a photo or PDF, then polls
 * the scan until the queued job has read it, and lets the user review the
 * lines before adding them to stock itself.
 */
class InvoiceScanController extends Controller
{
    private const MAX_FILE_KB = 10240;

    /**
     * The AI service takes at most 10 MB of base64 per image (~7.5 MB of
     * file); the app downsizes photos well below this.
     */
    private const MAX_IMAGE_KB = 7168;

    private const EXTENSIONS = [
        'image/jpeg' => 'jpg',
        'image/png' => 'png',
        'image/webp' => 'webp',
        'application/pdf' => 'pdf',
    ];

    /**
     * Uploads per account (each one is a paid AI call). Counted here rather
     * than with throttle middleware, which runs before auth.token and so
     * could only count per IP (shared by many users behind mobile CGNAT).
     */
    private const LIMITS = ['minute' => [6, 60], 'day' => [100, 86400]];

    public function __construct(
        private readonly ShopService $shops,
        private readonly EntitlementService $entitlements,
    ) {}

    /**
     * POST /invoices/scan (multipart: file) -> 202 {scan}
     * Stores the file on the private disk and queues the AI read.
     */
    public function store(Request $request): JsonResponse
    {
        $user = $request->user();
        $ent = $this->entitlements->forUser($user);
        $ent->refreshStatus();
        if (! $ent->isActivePaid() && ! $ent->isTrialActive()) {
            return response()->json([
                'error' => 'premium_required',
                'message' => 'Reading invoices needs an active trial or subscription.',
            ], 403);
        }

        $request->validate([
            'file' => ['required', 'file', 'mimes:jpg,jpeg,png,webp,pdf', 'max:'.self::MAX_FILE_KB],
        ], [
            'file.required' => 'Choose a photo or PDF of the invoice.',
            'file.mimes' => 'Upload a photo (JPG, PNG or WebP) or a PDF of the invoice.',
            'file.max' => 'The file is too large (10 MB at most).',
        ]);

        $file = $request->file('file');
        $mime = (string) $file->getMimeType();
        $ext = self::EXTENSIONS[$mime] ?? null;
        if ($ext === null) {
            throw ValidationException::withMessages(['file' => 'Upload a photo (JPG, PNG or WebP) or a PDF of the invoice.']);
        }
        if ($ext !== 'pdf' && $file->getSize() > self::MAX_IMAGE_KB * 1024) {
            throw ValidationException::withMessages(['file' => 'The photo is too large (7 MB at most). Take it at a lower resolution, or upload a PDF.']);
        }

        if (($wait = $this->throttle($user->id)) !== null) {
            return response()->json([
                'message' => 'Too many invoices scanned. Please try again later.',
                'retry_after' => $wait,
            ], 429, ['Retry-After' => (string) $wait]);
        }

        $shop = $this->shops->forUser($user);
        $path = $file->storeAs('invoice-scans/'.$shop->id, Str::uuid().'.'.$ext, InvoiceScan::DISK);
        if ($path === false) {
            return response()->json(['message' => 'Could not save the upload. Please try again.'], 500);
        }

        $scan = InvoiceScan::create([
            'shop_id' => $shop->id,
            'user_id' => $user->id,
            'file_path' => $path,
            'mime' => $mime,
            'file_size' => (int) $file->getSize(),
            'original_name' => mb_substr((string) $file->getClientOriginalName(), 0, 255) ?: null,
            'status' => InvoiceScan::STATUS_QUEUED,
        ]);

        ProcessInvoiceScan::dispatch($scan);

        return response()->json(['scan' => $scan->fresh()->toApiArray()], 202);
    }

    /** Counts one upload; returns the seconds to wait instead when over a limit. */
    private function throttle(int $userId): ?int
    {
        foreach (self::LIMITS as $window => [$max]) {
            $key = "invoice-scan:{$window}:{$userId}";
            if (RateLimiter::tooManyAttempts($key, $max)) {
                return max(1, RateLimiter::availableIn($key));
            }
        }
        foreach (self::LIMITS as $window => [, $decay]) {
            RateLimiter::hit("invoice-scan:{$window}:{$userId}", $decay);
        }

        return null;
    }

    /**
     * GET /invoices/scan/{id} -> {scan}: status, error and, once done, the
     * extracted invoice. Only the scan's own shop can see it (404 otherwise).
     */
    public function show(Request $request, int $id): JsonResponse
    {
        $shop = $this->shops->forUser($request->user());
        $scan = InvoiceScan::where('shop_id', $shop->id)->whereKey($id)->first();
        if (! $scan) {
            return response()->json(['message' => 'Not found'], 404);
        }
        $scan->failIfStalled();

        return response()->json(['scan' => $scan->toApiArray()]);
    }
}
