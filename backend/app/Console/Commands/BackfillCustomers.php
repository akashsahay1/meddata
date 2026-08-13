<?php

namespace App\Console\Commands;

use App\Models\User;
use App\Services\CustomerSyncService;
use Illuminate\Console\Command;

class BackfillCustomers extends Command
{
    protected $signature = 'customers:backfill';

    protected $description = 'Mirror every existing (non-admin) app user into the customers table';

    public function handle(CustomerSyncService $customers): int
    {
        $count = 0;

        User::where('is_admin', false)
            ->orderBy('id')
            ->chunkById(200, function ($users) use ($customers, &$count): void {
                foreach ($users as $user) {
                    if ($customers->syncFromUser($user) !== null) {
                        $count++;
                    }
                }
            });

        $this->info("Synced {$count} user(s) into the customers table.");

        return self::SUCCESS;
    }
}
