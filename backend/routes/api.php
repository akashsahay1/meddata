<?php

use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\BackupController;
use App\Http\Controllers\Api\BillController;
use App\Http\Controllers\Api\BrowserCheckoutController;
use App\Http\Controllers\Api\ConfigController;
use App\Http\Controllers\Api\CouponController;
use App\Http\Controllers\Api\DeviceController;
use App\Http\Controllers\Api\EntitlementController;
use App\Http\Controllers\Api\InvoiceScanController;
use App\Http\Controllers\Api\MedicineController;
use App\Http\Controllers\Api\PaymentController;
use App\Http\Controllers\Api\PurchaseController;
use App\Http\Controllers\Api\ReportController;
use App\Http\Controllers\Api\ShopController;
use App\Http\Controllers\Api\SyncController;
use App\Http\Controllers\Api\TrialController;
use Illuminate\Support\Facades\Route;

// A baseline per-IP rate limit on the whole API surface (named limiter so it
// never shares a counter bucket with the stricter per-route auth limiters).
Route::prefix('v1')->middleware('throttle:api')->group(function () {

    // ---- Public (no auth) ----
    Route::get('config', [ConfigController::class, 'index']);
    Route::post('register-device', [DeviceController::class, 'register']);

    // Razorpay redirect-mode callback: the checkout WebView lands here after
    // the bank/3DS page. It only relays the result to the app, which then
    // calls payment/verify with its token.
    Route::post('payment/return', [PaymentController::class, 'checkoutReturn']);

    // Browser checkout for the desktop app: the server verifies the payment
    // and activates the subscription; the app just refreshes afterwards.
    Route::get('pay/{order}', [BrowserCheckoutController::class, 'show'])
        ->where('order', '[A-Za-z0-9_]+');
    Route::post('pay/complete', [BrowserCheckoutController::class, 'complete']);

    // Google Play server-to-server webhook (called by Google, not the app).
    Route::post('rtdn', [PurchaseController::class, 'rtdn']);

    // ---- Auth (public, tightly throttled to blunt brute-force / spam) ----
    Route::post('auth/register', [AuthController::class, 'register'])->middleware('throttle:auth-register');
    Route::post('auth/login', [AuthController::class, 'login'])->middleware('throttle:auth-login');
    Route::post('auth/forgot-password', [AuthController::class, 'forgotPassword'])->middleware('throttle:auth-forgot');
    Route::post('auth/reset-password', [AuthController::class, 'resetPassword'])->middleware('throttle:auth-reset');

    // Profile photos (public; file names carry a random token).
    Route::get('avatars/{file}', [AuthController::class, 'showAvatar']);

    // ---- Authenticated: everything money/data/entitlement related ----
    // These were previously keyed on a client-supplied device_id with no auth,
    // which allowed trial farming and cross-user data access (IDOR). They are
    // now strictly scoped to the authenticated user.
    Route::middleware('auth.token')->group(function () {
        Route::post('auth/logout', [AuthController::class, 'logout']);
        Route::get('auth/me', [AuthController::class, 'me']);
        Route::patch('auth/profile', [AuthController::class, 'updateProfile']);
        Route::post('auth/avatar', [AuthController::class, 'uploadAvatar']);
        Route::delete('auth/avatar', [AuthController::class, 'deleteAvatar']);

        // Shop + multi-device inventory sync.
        Route::get('shops/current', [ShopController::class, 'current']);
        Route::patch('shops/current', [ShopController::class, 'update']);
        Route::get('sync/status', [SyncController::class, 'status']);
        Route::get('sync/pull', [SyncController::class, 'pull']);
        Route::post('sync/push', [SyncController::class, 'push']);

        // GST billing (online-only; numbers and tax come from the server).
        Route::get('bills', [BillController::class, 'index']);
        Route::post('bills', [BillController::class, 'store']);
        Route::get('bills/{bill}', [BillController::class, 'show'])->whereUuid('bill');
        Route::post('bills/{bill}/cancel', [BillController::class, 'cancel'])->whereUuid('bill');

        // Reports from server data: profit from bills (P4).
        Route::get('reports/profit', [ReportController::class, 'profit']);

        Route::post('auth/change-password', [AuthController::class, 'changePassword']);

        Route::get('entitlement', [EntitlementController::class, 'show']);
        Route::post('device/trial', [TrialController::class, 'register']);

        Route::post('coupon/validate', [CouponController::class, 'validateCode']);
        Route::post('order/create', [PaymentController::class, 'createOrder']);
        Route::post('payment/verify', [PaymentController::class, 'verify']);
        Route::post('purchase/verify', [PurchaseController::class, 'verify']);

        Route::post('backup', [BackupController::class, 'store']);
        Route::get('backup/latest', [BackupController::class, 'latest']);

        Route::get('medicines/search', [MedicineController::class, 'search']);

        // AI purchase-invoice reading: upload (rate-limited per account in the
        // controller), then poll until it is read.
        Route::post('invoices/scan', [InvoiceScanController::class, 'store']);
        Route::get('invoices/scan/{id}', [InvoiceScanController::class, 'show'])->whereNumber('id');
    });
});
