# Build Prompt — Medicine Stock & Expiry Tracker (v2 "Pro")

> Copy everything between the horizontal rules below into a fresh AI coding session (or hand to a developer) to generate the full application. It is written to be self-contained. Companion docs: `PROJECT_PLAN.md`, `TASKS.md`, `SUBSCRIPTION_PLANS.md`.

---

## ROLE & GOAL

You are a senior Flutter + backend engineer. Build a production-ready, **offline-first** Android application called **"Medicine Stock & Expiry Tracker"** for pharmacy and medical-shop owners, plus a lightweight backend used only for subscription validation and optional cloud backup. This is an **upgraded v2** of an existing app; keep it simple and fast on cheap, older Android phones.

The app helps a shop owner add medicines, track stock quantities, get expiry and low-stock reminders, search/update quickly, and never lose data. Free tier allows **7 medicines**; paid tiers unlock unlimited medicines and premium features.

## NON-NEGOTIABLE CONSTRAINTS

1. **Design: strictly black & white.** Pure monochrome UI — white background (`#FFFFFF`), black text/lines (`#000000`), plus grayscale shades (`#F5F5F5`, `#E0E0E0`, `#9E9E9E`, `#616161`) for separation. **No color anywhere. No colorful icons, no gradients, no illustrations.** Status (expired / expiring soon / low stock) must be conveyed with **text labels, outline icons, borders, and typographic weight — never color.** Support a full dark mode that is pure black background / white text (still monochrome).
2. **Runs on old, basic Android phones.** Configure `minSdkVersion 23` (Android 6.0 Marshmallow — the hard floor for Flutter 3.44; the engine rejects anything lower. Still well below Flutter's default of 24 and covers ~98% of active devices), `targetSdkVersion` = latest required by Play Store, `compileSdk 36` (required by current plugins). Force plugin subprojects to compileSdk 36 via a root `subprojects { afterEvaluate { … } }` block. Keep the release APK/AAB small (target < 20 MB), avoid heavy animations, avoid large image assets, and keep memory use low so it runs on 1–2 GB RAM devices. Provide both `arm64-v8a` and `armeabi-v7a` (32-bit) ABIs so 32-bit-only phones can install. If any needed package requires a higher minSdk, choose a lighter alternative instead of raising the floor.
3. **Offline-first.** All core features work with zero internet. Local database is the source of truth. Network is used only for (a) subscription purchase/validation and (b) optional cloud backup/restore. The app must be fully usable if the backend is unreachable.
4. **Free tier limit = 7 medicines.** Enforce on the client and re-validate entitlement; show an upgrade screen when the user hits the limit or taps a premium feature.

## TECH STACK

- **Flutter** (stable channel, null-safe), **Dart 3**.
- **State management:** Riverpod (or Provider if simpler) — keep it lightweight.
- **Local DB:** `sqflite` (SQLite) as source of truth. (Use `drift` only if you want type-safe queries; sqflite keeps the app smaller.)
- **Local notifications:** `flutter_local_notifications` + `timezone` for scheduled expiry/low-stock alerts; `workmanager` for periodic background checks.
- **Barcode scanning (enhancement):** `mobile_scanner` (camera-based) — gate behind a runtime permission and make it optional so no-camera devices still work.
- **Export/Reports:** `csv` + `pdf` + `printing` (or `share_plus`) for CSV/PDF export.
- **Billing:** `in_app_purchase` (Google Play Billing) for subscriptions.
- **Backend:** Choose **Supabase** (Postgres + Edge Functions, generous free tier) **or Firebase** (Firestore + Cloud Functions). Backend responsibilities are minimal — see below. Provide a clean data-access layer so the backend can be swapped.
- **Local prefs:** `shared_preferences` for flags (theme, onboarding done, cached entitlement).

## APP INFORMATION ARCHITECTURE (screens)

1. **Splash / init** — load DB, theme, cached entitlement.
2. **Onboarding** (first launch only, 2–3 plain monochrome slides) — value prop + "Get Started".
3. **Home / Dashboard**
   - Summary tiles (monochrome, bordered): Total Medicines, Expiring Soon (≤30 days), Expired, Low Stock.
   - Search bar (name / batch / barcode).
   - Filter & sort (All / Expiring / Expired / Low stock; sort by name, expiry, quantity).
   - List of medicines: name, quantity, expiry date, and a **text status chip** ("EXPIRED", "EXPIRES IN 12 DAYS", "LOW STOCK", "OK") rendered with borders/weight, no color.
   - FAB "+ Add Medicine".
   - Free-tier counter "X / 7 medicines" with upgrade link.
4. **Add / Edit Medicine** — form: name*, brand/manufacturer, category, batch/lot no., barcode (with optional scan), quantity*, unit (tablets/strips/bottles/ml…), low-stock threshold, purchase price, selling price (MRP), supplier, manufacture date, **expiry date***, notes. Validation + save. Enforce 7-item cap on add for free users.
5. **Medicine Detail** — full record, quick actions: adjust quantity (+/−), edit, delete (with undo), mark restocked.
6. **Alerts / Notifications center** — upcoming expiries and low-stock items grouped; tap to open detail.
7. **Reports / Analytics (premium)** — stock value, expiring-soon count over time, top categories, export CSV/PDF. Charts must be **monochrome** (bars/lines in black/gray, patterns not colors).
8. **Suppliers (enhancement)** — simple supplier list + contact; link medicines to a supplier.
9. **Backup & Restore** — local export/import (CSV/JSON to device storage) always available; cloud backup/restore = premium.
10. **Subscription / Upgrade** — plans, feature comparison, purchase, restore purchases, manage subscription (deep-link to Play). Redesign the existing screen to pure B&W (see `SUBSCRIPTION_PLANS.md` for tiers/pricing).
11. **Settings** — theme (System/Light/Dark, all monochrome), notification timing & daily reminder time, expiry-warning window (e.g. warn 30/15/7 days before), language (English + Hindi), currency (₹ default), about, privacy policy link, restore purchases.

## DATA MODEL (SQLite tables)

- **medicines**: `id` (uuid/text PK), `name`, `brand`, `category`, `batch_no`, `barcode`, `quantity` (int), `unit`, `low_stock_threshold` (int), `purchase_price` (real), `selling_price` (real), `supplier_id` (nullable FK), `mfg_date` (int/epoch, nullable), `expiry_date` (int/epoch), `notes`, `created_at`, `updated_at`, `is_deleted` (int, soft delete for sync/undo).
- **suppliers**: `id`, `name`, `phone`, `email`, `address`, `created_at`, `updated_at`.
- **categories**: `id`, `name`. (Or store category as text on medicine + suggest from distinct values.)
- **stock_movements** (enhancement/audit): `id`, `medicine_id`, `change` (+/− int), `reason` (add/sell/adjust/restock), `created_at`.
- **settings/meta**: key-value (or use shared_preferences).

Index `medicines(expiry_date)`, `medicines(name)`, `medicines(quantity)`, `medicines(barcode)` for fast search/sort. Include a versioned migration system (`onCreate`/`onUpgrade`) so future schema changes are safe.

## CORE LOGIC

- **Expiry status** computed from `expiry_date` vs now: `EXPIRED` (past), `EXPIRING` (within warning window, default 30 days, configurable), `OK`. Show remaining days as text.
- **Low stock** when `quantity <= low_stock_threshold` (default threshold configurable, e.g. 10).
- **Notifications:** schedule a **daily background check** (workmanager, e.g. 9:00 AM local) that queries expiring/expired/low-stock items and posts a grouped local notification. Also schedule per-item expiry reminders at the configured window. Notifications are plain text, no color.
- **Free-tier enforcement:** count non-deleted medicines; block the 8th add for free users and route to Upgrade. Re-check entitlement on app resume from cached value; refresh from backend/billing when online.

## BACKEND (minimal)

Purpose: **subscription validation + optional cloud backup.** The app must never require it for core use.

Provide:
1. **Purchase verification endpoint** — receives the Google Play purchase token, verifies it server-side against the Google Play Developer API, stores the entitlement (`user_id`/device_id, plan, status, expiry, purchase_token), and returns the current entitlement. This prevents client-side tampering of the "unlimited" unlock.
2. **Entitlement fetch endpoint** — returns current subscription status for a device/account.
3. **Real-Time Developer Notifications (RTDN)** webhook (Pub/Sub) — receive Google Play subscription lifecycle events (renew, cancel, grace period, expire) and update stored entitlement.
4. **Cloud backup (premium):** authenticated endpoints/bucket to upload and download an encrypted backup blob (the exported JSON/SQLite). Use anonymous/device auth or email sign-in (keep optional; free users never need an account).

Recommended: **Supabase** (Postgres tables `entitlements`, `backups`; Edge Functions for verify + RTDN webhook; Storage bucket for backup blobs) **or Firebase** (Firestore + Cloud Functions + Storage). Document environment variables and keys in a `.env.example`; never commit secrets. Include the Play service-account setup steps in the README.

Backend tables:
- `entitlements`: `id`, `device_id`/`user_id`, `product_id`, `plan`, `status` (active/grace/expired/canceled), `purchase_token`, `expiry_time`, `updated_at`.
- `backups`: `id`, `user_id`, `blob_path`, `size`, `created_at`.

## ENHANCEMENTS TO INCLUDE (beyond the original app)

Original app features: add/manage medicines, expiry reminders, low-stock alerts, offline storage, quick search, simple UI, 7-item free limit. **Add these upgrades:**

1. **Barcode/QR scan** to add or look up a medicine quickly (optional, camera-gated).
2. **Batch/lot number & multiple expiry batches** per medicine name.
3. **Purchase & selling price → stock value & basic profit view** in Reports.
4. **Stock movement history / audit log** (restock, sell, adjust) with undo.
5. **Supplier management** and per-supplier medicine list.
6. **Configurable expiry warning window** (30/15/7 days) and **daily reminder time.**
7. **Reports & analytics** (monochrome charts): total stock value, expiring-soon trend, expired losses, top categories; **export to CSV & PDF.**
8. **Backup & restore** — local (always free) + cloud (premium).
9. **Bulk import** medicines from CSV.
10. **Multi-language** (English + Hindi) and **currency** setting (₹ default).
11. **Dark mode** (pure black/white monochrome).
12. **Undo delete**, swipe actions, and empty-state guidance.
13. **Duplicate detection** (warn if same name+batch exists).
14. **Home widget / quick "today's expiries"** (optional, only if it doesn't raise minSdk).
15. **Accessibility:** large-tap targets, scalable text, screen-reader labels, and status conveyed without relying on color (already required).

## SUBSCRIPTION TIERS (summary — full detail in SUBSCRIPTION_PLANS.md)

- **Free:** up to **7 medicines**, basic expiry & low-stock alerts, local backup, search. Ads optional (keep none for clean B&W feel, or a single non-intrusive banner — decide with owner).
- **Premium Monthly:** unlimited medicines + all premium features.
- **Premium Yearly (Best Value):** unlimited + all premium features, discounted vs monthly.
- **Lifetime (one-time, optional):** unlimited + all premium features forever.
- **Premium features:** unlimited medicines, advanced/configurable expiry alerts, reports & analytics, cloud backup & multi-device restore, CSV/PDF export, priority support.
Use Play Console product IDs (e.g. `premium_monthly`, `premium_yearly`, `premium_lifetime`). Verify server-side.

## QUALITY, TESTING & DELIVERY

- Clean architecture: `data/` (db, models, repositories), `domain/` (entities, use-cases), `presentation/` (screens, widgets, controllers), `services/` (notifications, billing, backup). One responsibility per file.
- **Unit tests** for expiry/low-stock logic and free-tier gating; **widget tests** for Add/Edit and Home; a smoke integration test for the add→list→notify flow.
- Handle permissions gracefully (notifications on Android 13+, camera optional).
- Graceful offline & error states everywhere; never crash on no network.
- Provide `flutter build appbundle --release` config, signing instructions, ProGuard/R8 rules, and a small app size. Localize strings via `flutter_localizations` + ARB files.
- Deliverables: full Flutter project, backend project, `README.md` (setup, env, Play Console + service account, build & release steps), and seed/sample data for testing.

## OUTPUT FORMAT

Generate the project incrementally following `TASKS.md` milestones. For each milestone: create the files, explain key decisions briefly, and keep the B&W + old-phone constraints intact. Start with project scaffolding, data model, and the Add/List/Detail core, then notifications, then subscriptions + backend, then reports/backup, then polish.

---

*End of build prompt. Keep this file in sync with the other docs if scope changes.*
