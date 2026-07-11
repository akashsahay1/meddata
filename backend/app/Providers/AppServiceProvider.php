<?php

namespace App\Providers;

use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        $this->configureRateLimiters();
    }

    /**
     * Named per-IP rate limiters. Each name gets its own counter bucket, so a
     * route can safely carry both the blanket 'api' limiter AND a stricter
     * auth limiter without the two interfering. (Stacking two UNNAMED throttle
     * middlewares shares one bucket and trips early, which is what we hit.)
     */
    private function configureRateLimiters(): void
    {
        RateLimiter::for('api', fn (Request $r) => Limit::perMinute(120)->by($r->ip()));
        RateLimiter::for('auth-register', fn (Request $r) => Limit::perMinute(5)->by($r->ip()));
        RateLimiter::for('auth-login', fn (Request $r) => Limit::perMinute(10)->by($r->ip()));
        RateLimiter::for('auth-forgot', fn (Request $r) => Limit::perMinute(5)->by($r->ip()));
        RateLimiter::for('auth-reset', fn (Request $r) => Limit::perMinute(10)->by($r->ip()));
    }
}
