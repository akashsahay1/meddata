<?php

use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\BackupController;
use App\Http\Controllers\Api\ConfigController;
use App\Http\Controllers\Api\CouponController;
use App\Http\Controllers\Api\DeviceController;
use App\Http\Controllers\Api\EntitlementController;
use App\Http\Controllers\Api\PaymentController;
use App\Http\Controllers\Api\PurchaseController;
use App\Http\Controllers\Api\TrialController;
use Illuminate\Support\Facades\Route;

Route::prefix('v1')->group(function () {
    Route::get('config', [ConfigController::class, 'index']);

    Route::post('register-device', [DeviceController::class, 'register']);

    Route::get('entitlement', [EntitlementController::class, 'show']);

    // Custom subscriptions (Razorpay + trial + coupons)
    Route::post('device/trial', [TrialController::class, 'register']);
    Route::post('coupon/validate', [CouponController::class, 'validateCode']);
    Route::post('order/create', [PaymentController::class, 'createOrder']);
    Route::post('payment/verify', [PaymentController::class, 'verify']);

    Route::post('purchase/verify', [PurchaseController::class, 'verify']);
    Route::post('rtdn', [PurchaseController::class, 'rtdn']);

    Route::post('backup', [BackupController::class, 'store']);
    Route::get('backup/latest', [BackupController::class, 'latest']);

    // Email auth (custom Bearer token, no Sanctum)
    Route::post('auth/register', [AuthController::class, 'register']);
    Route::post('auth/login', [AuthController::class, 'login']);
    Route::post('auth/forgot-password', [AuthController::class, 'forgotPassword']);
    Route::post('auth/reset-password', [AuthController::class, 'resetPassword']);

    Route::middleware('auth.token')->group(function () {
        Route::post('auth/logout', [AuthController::class, 'logout']);
        Route::get('auth/me', [AuthController::class, 'me']);
    });
});
