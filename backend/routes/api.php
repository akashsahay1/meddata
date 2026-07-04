<?php

use App\Http\Controllers\Api\BackupController;
use App\Http\Controllers\Api\ConfigController;
use App\Http\Controllers\Api\DeviceController;
use App\Http\Controllers\Api\EntitlementController;
use App\Http\Controllers\Api\PurchaseController;
use Illuminate\Support\Facades\Route;

Route::prefix('v1')->group(function () {
    Route::get('config', [ConfigController::class, 'index']);

    Route::post('register-device', [DeviceController::class, 'register']);

    Route::get('entitlement', [EntitlementController::class, 'show']);

    Route::post('purchase/verify', [PurchaseController::class, 'verify']);
    Route::post('rtdn', [PurchaseController::class, 'rtdn']);

    Route::post('backup', [BackupController::class, 'store']);
    Route::get('backup/latest', [BackupController::class, 'latest']);
});
