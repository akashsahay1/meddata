<x-filament-panels::page>
    <div class="prose dark:prose-invert max-w-none">

        <x-filament::section>
            <x-slot name="heading">Overview</x-slot>
            <p>
                This is the admin backend for <strong>Meddata — Medicine Stock &amp; Expiry Tracker</strong>,
                an offline-first pharmacy inventory app. The app works fully offline; this backend is used
                for <strong>subscription validation</strong>, <strong>optional cloud backup</strong>, and
                <strong>managing customers, stores, medicines and plans</strong>.
            </p>
        </x-filament::section>

        <x-filament::section>
            <x-slot name="heading">Navigation &amp; management pages</x-slot>
            <ul>
                <li><strong>Customers &amp; Stores</strong> — Customers (shop owners) and their Stores. Full add / edit / list, search, filters, Trash (soft-delete) and pagination.</li>
                <li><strong>Catalog</strong> — Medicines synced/managed from the backend (name, batch, expiry, quantity, price) with expiry/low-stock filters.</li>
                <li><strong>Subscriptions</strong> — <strong>Plans</strong> (create/edit price, badge, features), <strong>Entitlements</strong> (who is premium) and <strong>Purchase Logs</strong>.</li>
                <li><strong>System</strong> — <strong>App Settings</strong> (free-tier limit, warning days, etc.), <strong>Backups</strong>, <strong>Users</strong> (admins) and this <strong>Documentation</strong>.</li>
            </ul>
            <p>Every list supports column search, multiple filters, and restore/force-delete for trashed rows.</p>
        </x-filament::section>

        <x-filament::section>
            <x-slot name="heading">Managing subscription plans</x-slot>
            <p>Open <strong>Subscriptions → Plans</strong> to create or edit a plan. Editable fields:</p>
            <ul>
                <li><strong>Product ID</strong> — must match the Google Play product id (<code>premium_monthly</code>, <code>premium_yearly</code>, <code>premium_lifetime</code>).</li>
                <li><strong>Price / currency / billing period</strong>, <strong>badge</strong> (e.g. "BEST VALUE"), <strong>Best value</strong> toggle, <strong>Active</strong> toggle, <strong>sort order</strong>.</li>
                <li><strong>Features</strong> — an editable tag list shown on the app paywall.</li>
            </ul>
            <p>Changes appear in the app instantly via the <code>/api/v1/config</code> endpoint.</p>
        </x-filament::section>

        <x-filament::section>
            <x-slot name="heading">API endpoints (used by the app)</x-slot>
            <div style="overflow-x:auto">
                <table>
                    <thead>
                        <tr><th>Method</th><th>Path</th><th>Purpose</th></tr>
                    </thead>
                    <tbody>
                        <tr><td>GET</td><td><code>/api/v1/config</code></td><td>Free-tier limit, warning days, and the plan list for the paywall.</td></tr>
                        <tr><td>POST</td><td><code>/api/v1/register-device</code></td><td>Register an anonymous device (no login for free users).</td></tr>
                        <tr><td>GET</td><td><code>/api/v1/entitlement?device_id=…</code></td><td>Current premium/subscription status for a device.</td></tr>
                        <tr><td>POST</td><td><code>/api/v1/purchase/verify</code></td><td>Verify a Google Play purchase token and store the entitlement.</td></tr>
                        <tr><td>POST</td><td><code>/api/v1/rtdn</code></td><td>Google Play Real-Time Developer Notifications webhook (renew/cancel/expire).</td></tr>
                        <tr><td>POST</td><td><code>/api/v1/backup</code></td><td>Upload an encrypted cloud backup (premium).</td></tr>
                        <tr><td>GET</td><td><code>/api/v1/backup/latest?device_id=…</code></td><td>Fetch the latest cloud backup (premium).</td></tr>
                    </tbody>
                </table>
            </div>
        </x-filament::section>

        <x-filament::section>
            <x-slot name="heading">Google Play verification (go-live)</x-slot>
            <p>
                Purchase verification currently uses a safe development fallback. For production, create a
                <strong>Google Play Developer API service account</strong>, then set in <code>backend/.env</code>:
            </p>
            <pre><code>GOOGLE_PLAY_CREDENTIALS=/absolute/path/to/service-account.json
GOOGLE_PLAY_PACKAGE=com.medstock.med_stock</code></pre>
            <p>Point Google Play RTDN (Pub/Sub push) at <code>/api/v1/rtdn</code> to keep entitlements current.</p>
        </x-filament::section>

        <x-filament::section>
            <x-slot name="heading">Running the backend</x-slot>
            <pre><code>cd backend
php artisan migrate --seed --force   # schema + admin + plans + settings + demo data
php artisan serve --port=8000        # admin at /admin</code></pre>
            <p>Admin login is created by the seeder. Database: MariaDB <code>med_stock</code>.</p>
        </x-filament::section>

    </div>
</x-filament-panels::page>
