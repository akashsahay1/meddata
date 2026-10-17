<?php

use Illuminate\Support\Facades\Route;

// The public website. The Filament admin panel is at /admin (AdminPanelProvider).
Route::view('/', 'website')->name('website');
