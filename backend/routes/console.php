<?php

use App\Models\InvoiceScan;
use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

// Uploaded purchase invoices (and what was read from them) are deleted after
// InvoiceScan::KEEP_DAYS. Needs the scheduler cron: `php artisan schedule:run`.
Schedule::command('model:prune', ['--model' => [InvoiceScan::class]])->daily();
