# Backend — Laravel + Herd + MariaDB (decision record)

Supersedes the "Supabase/Firebase" option in the earlier docs. The backend is a **Laravel** app served by **Laravel Herd**, using **MariaDB/MySQL**, with a full **Filament admin panel** where everything is editable.

## Environment
- **Server:** Laravel Herd (macOS). App served at `http://med-stock-api.test` (Herd auto-domain from folder name).
- **DB:** MariaDB (via Herd), `DB_HOST=127.0.0.1`, `DB_DATABASE=med_stock`, `DB_USERNAME=root`, `DB_PASSWORD=<your DB password>`.
- **Admin panel:** [Filament](https://filamentphp.com) (free) at `/admin`.

## Seeded super admin
- Name: **Akash Sahay**
- Email: **akash.sahay1@gmail.com**
- Password: the `ADMIN_PASSWORD` from `.env` (seeded by `php artisan db:seed`)

## What the admin panel can edit (requirement: "everything editable")
- **Users / customers** — device/account, current plan, status.
- **Plans** — name, product_id, price, currency, billing period, feature flags, "Best Value" badge, active/inactive.
- **Entitlements** — subscription status per user (active/grace/expired/canceled), expiry, purchase token.
- **App settings** — free-tier limit (default 7), expiry warning days, low-stock default, support contact, force-update flag, maintenance mode.
- **Feature toggles** — which features are premium.
- **Backups** — list/download user cloud backups (premium).
- **Purchase logs** — Play verification results / RTDN events.
- **Admins/roles** — manage admin users.

## API surface (consumed by the Flutter app)
- `POST /api/v1/purchase/verify` — verify Google Play purchase token, upsert entitlement, return status.
- `GET  /api/v1/entitlement?device_id=…` — current entitlement.
- `POST /api/v1/rtdn` — Google Play Real-Time Developer Notifications webhook (Pub/Sub push).
- `GET  /api/v1/config` — remote app config (free-tier limit, warning days, plan list for the paywall).
- `POST /api/v1/backup` / `GET /api/v1/backup/latest` — encrypted cloud backup upload/download (premium, authenticated).
- `POST /api/v1/register-device` — anonymous device registration (no login required for free users).

App remains fully functional if this API is unreachable (cached entitlement + local-only backup).

## Build steps (Phase 4)
1. `composer create-project laravel/laravel backend` (in project root, served by Herd).
2. Configure `.env` DB creds above; `php artisan migrate`.
3. Install Filament: `composer require filament/filament`; `php artisan filament:install --panels`.
4. Migrations + models: `users`, `plans`, `entitlements`, `app_settings`, `backups`, `purchase_logs`, `devices`.
5. Filament resources for each model (editable CRUD).
6. Seeder: super admin (above) + default plans (Free/Monthly/Yearly/Lifetime) + default app settings.
7. API controllers + routes (`routes/api.php`), Sanctum for auth on backup endpoints.
8. Google Play verification service (service-account JSON) + RTDN webhook handler.
9. Point the Flutter app's API base URL at the Herd domain.
