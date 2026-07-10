<?php

use Illuminate\Support\Facades\Route;

// The Filament admin panel is mounted at the site root ('/'), which serves the LOGIN
// form (AdminPanelProvider::loginRouteSlug), with the dashboard moved to '/dashboard'.
//
// Filament resolves its "home" URL (post-login fallback, brand-logo link, and the
// redirect for an already-authenticated visitor to '/') via a route named
// 'filament.admin.home'. It never registers one itself, so without this the home URL
// falls back to '/' — i.e. the login page — causing a redirect loop after logging in
// directly at '/'. Registering it here points that home URL at the dashboard instead.
Route::get('/home', fn () => redirect()->route('filament.admin.pages.dashboard'))
    ->name('filament.admin.home');
