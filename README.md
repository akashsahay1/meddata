# Medicine Stock & Expiry Tracker — v2 ("Pro")

Upgraded, **offline-first**, **strictly black & white** Android app for pharmacy / medical-shop owners to track medicine stock, expiry, and low-stock alerts. Built to run on **old, low-end Android phones** (Android 5.0+, 32-bit supported). Free tier = 7 medicines; paid tiers unlock unlimited + premium features. Minimal backend for subscription validation and optional cloud backup.

## Repository layout

```
meddata/
├── app/          Flutter mobile app (offline-first, B&W) — see app/lib, app/android
├── backend/      Laravel 12 + Filament admin + REST API (MariaDB)
├── docs/         Project docs (build prompt, plan, tasks, subscriptions, run guide)
└── README.md     This file
```

Run the app from `app/` (`cd app && flutter run`); run the backend from `backend/` (`php artisan serve`). Full commands in `docs/HOWTO_RUN.md`.

## Documentation (read in this order)

1. **[docs/BUILD_PROMPT.md](docs/BUILD_PROMPT.md)** — full copy-paste prompt to generate the app + backend (constraints, tech stack, screens, data model, enhancements).
2. **[docs/PROJECT_PLAN.md](docs/PROJECT_PLAN.md)** — architecture, platform targets, milestones, risks, definition of done.
3. **[docs/TASKS.md](docs/TASKS.md)** — detailed, checkable task list by phase (the working checklist).
4. **[docs/SUBSCRIPTION_PLANS.md](docs/SUBSCRIPTION_PLANS.md)** — tiers, pricing, feature gating, Play Billing flow.

## Hard constraints (apply to everything)
- **Monochrome only** — white/black/grayscale. No color, no colorful icons, status conveyed by text + outline icons + weight.
- **Old-phone friendly** — `minSdkVersion 21`, `arm64-v8a` + `armeabi-v7a`, small AAB (< ~20 MB), low RAM, works on 1–2 GB phones.
- **Offline-first** — local SQLite is the source of truth; network only for billing + optional cloud backup.

## Resuming in a new session
Open `docs/TASKS.md`, find the last `[x]`, and continue. Keep the two hard constraints intact.
