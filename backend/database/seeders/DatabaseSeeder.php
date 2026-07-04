<?php

namespace Database\Seeders;

use App\Models\AppSetting;
use App\Models\Plan;
use App\Models\User;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;

class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        // ---- Super admin (logs into the Filament panel at /admin) ----
        User::updateOrCreate(
            ['email' => 'akash.sahay1@gmail.com'],
            [
                'name' => 'Akash Sahay',
                'password' => Hash::make('Akash243@#$'),
                'is_admin' => true,
                'email_verified_at' => now(),
            ],
        );

        // ---- Default subscription plans (editable in admin) ----
        $premiumFeatures = [
            'Track unlimited medicines',
            'Advanced expiry alerts',
            'Detailed reports & analytics',
            'Secure cloud backup & restore',
            'Export to CSV & PDF',
            'Priority support',
        ];

        $plans = [
            [
                'name' => 'Free Plan',
                'product_id' => 'free',
                'billing_period' => 'free',
                'price' => 0,
                'currency' => 'INR',
                'badge' => null,
                'is_best_value' => false,
                'sort_order' => 0,
                'features' => ['Up to 7 medicines', 'Basic expiry & low-stock alerts', 'Local backup'],
            ],
            [
                'name' => 'Yearly Plan',
                'product_id' => 'premium_yearly',
                'billing_period' => 'yearly',
                'price' => 999,
                'currency' => 'INR',
                'badge' => 'BEST VALUE',
                'is_best_value' => true,
                'sort_order' => 1,
                'features' => $premiumFeatures,
            ],
            [
                'name' => 'Monthly Plan',
                'product_id' => 'premium_monthly',
                'billing_period' => 'monthly',
                'price' => 99,
                'currency' => 'INR',
                'badge' => null,
                'is_best_value' => false,
                'sort_order' => 2,
                'features' => $premiumFeatures,
            ],
            [
                'name' => 'Lifetime',
                'product_id' => 'premium_lifetime',
                'billing_period' => 'lifetime',
                'price' => 2499,
                'currency' => 'INR',
                'badge' => null,
                'is_best_value' => false,
                'sort_order' => 3,
                'features' => $premiumFeatures,
            ],
        ];

        foreach ($plans as $plan) {
            Plan::updateOrCreate(['product_id' => $plan['product_id']], $plan);
        }

        // ---- Default app settings (editable in admin) ----
        $settings = [
            ['key' => 'free_tier_limit', 'value' => '7', 'type' => 'int', 'label' => 'Free tier medicine limit', 'group' => 'limits'],
            ['key' => 'expiry_warning_days', 'value' => '30', 'type' => 'int', 'label' => 'Default expiry warning (days)', 'group' => 'alerts'],
            ['key' => 'low_stock_default', 'value' => '10', 'type' => 'int', 'label' => 'Default low-stock threshold', 'group' => 'alerts'],
            ['key' => 'support_email', 'value' => 'akash.sahay1@gmail.com', 'type' => 'string', 'label' => 'Support email', 'group' => 'general'],
            ['key' => 'maintenance_mode', 'value' => '0', 'type' => 'bool', 'label' => 'Maintenance mode', 'group' => 'general'],
            ['key' => 'force_update', 'value' => '0', 'type' => 'bool', 'label' => 'Force app update', 'group' => 'general'],
        ];

        foreach ($settings as $s) {
            AppSetting::updateOrCreate(['key' => $s['key']], $s);
        }

        // ---- Demo data for the management backend (customers / stores / medicines) ----
        // Only seed when the customers table is empty so re-running the seeder stays idempotent.
        if (\App\Models\Customer::count() === 0) {
            $this->call(DemoDataSeeder::class);
        }
    }
}
