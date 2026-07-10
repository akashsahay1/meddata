<?php

namespace App\Filament\Pages;

use Filament\Pages\Dashboard as BaseDashboard;

/**
 * Dashboard moved off the panel root ('/') to '/dashboard' so the login form
 * can live at '/' (see AdminPanelProvider::loginRouteSlug).
 */
class Dashboard extends BaseDashboard
{
    protected static string $routePath = '/dashboard';
}
