<?php

namespace App\Providers\Filament;

use Filament\Http\Middleware\Authenticate;
use Filament\Http\Middleware\AuthenticateSession;
use Filament\Http\Middleware\DisableBladeIconComponents;
use Filament\Http\Middleware\DispatchServingFilamentEvent;
use App\Filament\Pages\Dashboard;
use Filament\Navigation\NavigationGroup;
use Filament\Panel;
use Filament\PanelProvider;
use Filament\Support\Colors\Color;
use Filament\Support\Facades\FilamentView;
use Filament\View\PanelsRenderHook;
use Filament\Widgets\AccountWidget;
use Illuminate\Cookie\Middleware\AddQueuedCookiesToResponse;
use Illuminate\Cookie\Middleware\EncryptCookies;
use Illuminate\Foundation\Http\Middleware\PreventRequestForgery;
use Illuminate\Routing\Middleware\SubstituteBindings;
use Illuminate\Session\Middleware\StartSession;
use Illuminate\Support\HtmlString;
use Illuminate\View\Middleware\ShareErrorsFromSession;

class AdminPanelProvider extends PanelProvider
{
    public function panel(Panel $panel): Panel
    {
        // Inject the Font Awesome CDN stylesheet into the panel <head>.
        FilamentView::registerRenderHook(
            PanelsRenderHook::HEAD_END,
            fn (): string => new HtmlString('<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.2/css/all.min.css">'),
        );

        return $panel
            ->default()
            ->id('admin')
            ->path('')
            ->login()
            ->loginRouteSlug('/')
            // '/' is the login form, so send authenticated users to '/dashboard'
            // instead of the panel root (avoids a post-login redirect loop).
            ->homeUrl(fn (): string => Dashboard::getUrl())
            ->brandName('Meddata')
            ->brandLogo(asset('images/meddata_logo.png'))
            ->brandLogoHeight('2.2rem')
            ->favicon(asset('images/meddata_logo.png'))
            ->font('Poppins')
            ->colors([
                'primary' => Color::Amber,
            ])
            ->navigationGroups([
                // Icons live on the individual resources (Font Awesome), so groups
                // are label-only — Filament v5 forbids icons on both a group and its items.
                NavigationGroup::make('Customers & Stores'),
                NavigationGroup::make('Catalog'),
                NavigationGroup::make('Subscriptions'),
                NavigationGroup::make('System'),
            ])
            ->discoverResources(in: app_path('Filament/Resources'), for: 'App\Filament\Resources')
            ->discoverPages(in: app_path('Filament/Pages'), for: 'App\Filament\Pages')
            ->pages([
                Dashboard::class,
            ])
            ->discoverWidgets(in: app_path('Filament/Widgets'), for: 'App\Filament\Widgets')
            ->widgets([
                AccountWidget::class,
            ])
            ->middleware([
                EncryptCookies::class,
                AddQueuedCookiesToResponse::class,
                StartSession::class,
                AuthenticateSession::class,
                ShareErrorsFromSession::class,
                PreventRequestForgery::class,
                SubstituteBindings::class,
                DisableBladeIconComponents::class,
                DispatchServingFilamentEvent::class,
            ])
            ->authMiddleware([
                Authenticate::class,
            ]);
    }
}
