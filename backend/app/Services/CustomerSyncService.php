<?php

namespace App\Services;

use App\Models\Customer;
use App\Models\User;

/**
 * Mirrors app users into the `customers` table so people who register/log in
 * from the mobile app show up in the admin "Customers" section.
 *
 * App users live in `users`; the admin Customers view reads the separate
 * `customers` table. Without this sync, signups never appear there.
 */
class CustomerSyncService
{
    /**
     * Upsert a customer row for the given app user (matched by email).
     *
     * Admins are skipped. Only the app-owned fields (name/phone/device_id) are
     * written, so admin-entered fields (city/state/status/plan/notes) are
     * preserved on existing rows. `status` falls back to the DB default
     * ('active') for brand-new rows.
     */
    public function syncFromUser(User $user, ?string $deviceId = null): ?Customer
    {
        if ($user->is_admin) {
            return null;
        }

        $attributes = array_filter([
            'name' => $user->name,
            'phone' => $user->phone,
            'device_id' => $deviceId,
        ], static fn ($value) => $value !== null);

        return Customer::updateOrCreate(['email' => $user->email], $attributes);
    }
}
