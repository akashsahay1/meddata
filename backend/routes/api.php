<?php

use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\BackupController;
use App\Http\Controllers\Api\ConfigController;
use App\Http\Controllers\Api\CouponController;
use App\Http\Controllers\Api\DeviceController;
use App\Http\Controllers\Api\EntitlementController;
use App\Http\Controllers\Api\MedicineController;
use App\Http\Controllers\Api\PaymentController;
use App\Http\Controllers\Api\PurchaseController;
use App\Http\Controllers\Api\TrialController;
use Illuminate\Support\Facades\Route;

// A baseline per-IP rate limit on the whole API surface (named limiter so it
// never shares a counter bucket with the stricter per-route auth limiters).
Route::prefix('v1')->middleware('throttle:api')->group(function () {

    // ---- Public (no auth) ----
    Route::get('config', [ConfigController::class, 'index']);
    Route::post('register-device', [DeviceController::class, 'register']);

    // Google Play server-to-server webhook (called by Google, not the app).
    Route::post('rtdn', [PurchaseController::class, 'rtdn']);

    // ---- Auth (public, tightly throttled to blunt brute-force / spam) ----
    Route::post('auth/register', [AuthController::class, 'register'])->middleware('throttle:auth-register');
    Route::post('auth/login', [AuthController::class, 'login'])->middleware('throttle:auth-login');
    Route::post('auth/forgot-password', [AuthController::class, 'forgotPassword'])->middleware('throttle:auth-forgot');
    Route::post('auth/reset-password', [AuthController::class, 'resetPassword'])->middleware('throttle:auth-reset');

    // ---- Authenticated: everything money/data/entitlement related ----
    // These were previously keyed on a client-supplied device_id with no auth,
    // which allowed trial farming and cross-user data access (IDOR). They are
    // now strictly scoped to the authenticated user.
    Route::middleware('auth.token')->group(function () {
        Route::post('auth/logout', [AuthController::class, 'logout']);
        Route::get('auth/me', [AuthController::class, 'me']);
        Route::patch('auth/profile', [AuthController::class, 'updateProfile']);
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
    });
});
