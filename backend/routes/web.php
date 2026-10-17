<?php

use Illuminate\Support\Facades\Route;

// The public website. The Filament admin panel is at /admin (AdminPanelProvider).
Route::view('/', 'website')->name('website');

// Legal pages, linked from the footer (Razorpay asks for these).
foreach ([
    'privacy-policy' => 'privacy',
    'terms' => 'terms',
    'refund-policy' => 'refund',
    'delivery-policy' => 'delivery',
    'cookie-policy' => 'cookies',
    'disclaimer' => 'disclaimer',
    'contact' => 'contact',
] as $path => $view) {
    Route::view($path, "legal.{$view}")->name("legal.{$view}");
}
