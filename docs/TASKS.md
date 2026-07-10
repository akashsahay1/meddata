# Task List — Medicine Stock & Expiry Tracker (v2)

Check off tasks as you go (`[x]`). Each phase maps to `PROJECT_PLAN.md` § 10. Keep the two hard constraints in mind for **every** task: **strictly black & white UI** and **runs on old Android phones (minSdk 21, 32-bit ABI, small & light).**

---

## Phase 0 — Project setup
- [x] Install Flutter stable; `flutter doctor` clean.
- [x] `flutter create` project (org id, e.g. `com.<yourname>.medstock`).
- [x] Set `minSdkVersion 23` (Flutter 3.44 engine floor; 21 is rejected), `compileSdk 36` (required by file_picker/lifecycle plugins) in `android/app/build.gradle.kts`.
- [x] Enable ABIs `arm64-v8a` + `armeabi-v7a`; enable R8/ProGuard shrink for release. _(release builds split per ABI)_
- [x] Add base dependencies: riverpod, sqflite, path, shared_preferences, flutter_local_notifications, timezone, workmanager, intl, flutter_localizations.
- [x] Create folder structure: `data/`, `domain/`, `presentation/`, `services/`.
- [x] Build monochrome `ThemeData` (light + dark), typography, spacing, reusable widgets (BorderedCard, StatusChip, PrimaryButton). **No color values except grayscale.**
- [x] Add lint rules (`flutter_lints`), format. _(`flutter analyze` clean; no CI step yet)_
- [x] Splash + app shell + bottom/nav routing.

## Phase 1 — Core CRUD (offline)
- [x] SQLite helper: open DB, versioned `onCreate`/`onUpgrade`.
- [x] Tables: `medicines`, `suppliers`, `categories`, `stock_movements`, settings KV; add indexes.
- [x] Models + repositories (Medicine, Supplier) with CRUD.
- [x] Home/Dashboard: summary tiles (Total, Expiring, Expired, Low stock) — monochrome bordered.
- [x] Medicine list with **text status chips** (no color), quantity, expiry.
- [x] Search (name/batch/barcode) + filter (All/Expiring/Expired/Low) + sort (name/expiry/qty).
- [x] Add/Edit Medicine form + validation (name, quantity, expiry required).
- [x] Medicine Detail + quick qty +/−, edit, delete with **undo**.
- [x] Duplicate detection (same name+batch warning).
- [x] Free-tier counter "X / 7" on Home + block 8th add → route to Upgrade.
- [x] Empty states & guidance.
- [x] Unit tests: expiry status, low-stock, free-tier gating.

## Phase 2 — Alerts & notifications
- [x] Expiry status use-case (EXPIRED / EXPIRING within window / OK) + days-remaining.
- [x] Low-stock use-case (`qty <= threshold`).
- [x] `flutter_local_notifications` setup + `timezone` init; Android 13+ notification permission flow.
- [x] `workmanager` daily background check (~9 AM) → grouped notification of expiring/expired/low items.
- [x] Per-item expiry reminders scheduled at configured window(s).
- [x] Alerts center screen (grouped upcoming expiries + low stock; tap → detail).
- [x] Settings: warning window (30/15/7), daily reminder time, enable/disable alert types.
- [ ] Verify notification reliability under battery optimization (test on real OEM device).

## Phase 3 — Monetization (client)
> **Superseded:** Google Play Billing / `in_app_purchase` was removed in favour of a
> **7-day trial → full app lock** model with **Razorpay** checkout + coupons. See `docs/ALOK_CHANGES.md`.
- [x] Redesign Subscription screen to **pure B&W** (replace green in existing screenshot).
- [x] Feature-comparison table (Free vs Premium) — monochrome.
- [~] ~~Integrate `in_app_purchase`; product IDs~~ → **Razorpay** checkout (`subscribe_view.dart`); plans fetched from backend.
- [x] Purchase flow, loading/error states, success unlock (+ dev-mode test-pay).
- [~] ~~Restore purchases~~ — n/a with Razorpay; access follows server entitlement tied to the user account.
- [x] Entitlement service + cached entitlement (shared_preferences) for offline.
- [x] Gate premium features (unlimited items, reports, cloud backup, export) behind entitlement / lock screen.
- [~] ~~"Manage subscription" deep-link to Play~~ — n/a. See `SUBSCRIPTION_PLANS.md`.

## Phase 4 — Backend (validation + backup)
> Built on **Laravel + Filament (MariaDB)** rather than Supabase/Firebase; RTDN/Play-token
> verification replaced by Razorpay order/verify + custom email auth (Bearer tokens).
- [x] Scaffold project; `.env.example` (no secrets committed).
- [x] Tables: `entitlements` (+ `user_id`), coupons, payments, `api_tokens`, `password_reset_codes`.
- [~] ~~Play Console app + subscription products + service account (Google Play Developer API)~~ — n/a (Razorpay).
- [~] ~~Verify Play purchase token server-side~~ → `payment/verify` (Razorpay signature) → store entitlement.
- [x] Endpoint: fetch current entitlement by user id (auth token) / device.
- [~] ~~RTDN Pub/Sub webhook~~ — n/a (Razorpay one-time/plan verify).
- [x] Email auth: `/auth/{register,login,logout,me,forgot-password,reset-password}` (custom Bearer token, no Sanctum). Payment calls carry the token → subscription tied to user.
- [x] Wire client to verify after purchase and refresh entitlement on resume/online.
- [ ] Cloud backup upload/download (encrypted blob) — premium only. _(local `backup_service` exists; cloud sync not wired)_
- [x] Fail-safe: app fully works if backend unreachable (use cached entitlement).

## Phase 5 — Enhancements
- [x] Barcode/QR scan (`mobile_scanner`) — camera-permission-gated, add/lookup by barcode.
- [ ] Batch/lot tracking (multiple expiry batches per medicine name).
- [x] Stock movement audit log (add/sell/adjust/restock) + view history.
- [ ] Supplier management + per-supplier medicine list. _(model/repo exist; no UI screen)_
- [x] Reports/Analytics (premium): stock value, expiring-soon trend, expired losses, top categories — **monochrome charts.**
- [x] Export CSV + PDF (`csv`, `pdf`, `printing`/`share_plus`).
- [x] Backup/restore: local export/import (JSON/CSV) always free; cloud = premium (cloud pending).
- [ ] Bulk CSV import of medicines.
- [x] Localization: English + Hindi (ARB files, `flutter_localizations`); ₹ currency default.
- [ ] Optional: home-screen "today's expiries" widget (only if it doesn't raise minSdk).

## Phase 6 — Polish, QA & release
- [x] Dark mode pass (pure black/white) across all screens.
- [ ] Accessibility: tap targets, scalable text, semantic labels, status-without-color audit.
- [x] Error/offline states everywhere; no crash on no network.
- [ ] Widget tests (Add/Edit, Home) + smoke integration test (add→list→notify).
- [x] App-size optimization (remove unused assets/deps, R8, split ABIs) → target < 20 MB. _(armeabi-v7a 23.8MB)_
- [ ] Test on Android 5.0 emulator + a real low-RAM device.
- [ ] Signing config + keystore; `flutter build appbundle --release`.
- [ ] Play Store listing: monochrome icon, screenshots, description (reuse marketing copy), privacy policy URL, data-safety form.
- [ ] Final README (setup, env, Razorpay keys, build & release).
- [ ] Update all `docs/` if scope changed.

---

## Progress log (update each session)
- 2026-07-09 — Email auth (Alok): **no Sanctum** — custom Bearer token (api_tokens SHA-256 hash +
  AuthenticateApiToken middleware). App: AuthService, Login/Signup/Forgot-password screens (6-digit
  reset code), gate onboarding→login→access→home, Settings logout, payment calls carry the token so
  the subscription ties to the user account. Backend: /api/v1/auth/{register,login,logout,me,
  forgot-password,reset-password}; entitlement.user_id; forgot returns dev_code in debug. 27 backend
  tests pass; verified E2E (register→trial 7d, login, wrong-pw 422, me 401 w/o token, forgot→code,
  reset→login with new pw 200). App builds clean.

- 2026-07-09 — Alok ji's changes (docs/ALOK_CHANGES.md): removed Google Play Billing; added
  **7-day trial → full app lock**, **Razorpay** gateway, **coupons** (percentage/flat). App:
  razorpay_flutter, SettingsService.hasAccess, LockScreen, SubscribeView (plans from backend +
  coupon + Razorpay checkout, dev-mode test-pay). Backend: coupons (+ admin Generate codes),
  payments log, RazorpayService, endpoints device/trial · coupon/validate · order/create ·
  payment/verify; 17 tests pass. Verified end-to-end (trial 7d, WELCOME20 20% → ₹799.2, order
  dev fallback). App label Meddata + colored launcher icon regenerated. Both build clean.

- 2026-07-04 — Created v2 docs (build prompt, plan, tasks, subscription plans).
- 2026-07-04 — Built the app end-to-end (Phases 0–5 in code): Flutter 3.44 project; monochrome
  theme (light/dark); SQLite DB + migrations; medicine/supplier/movement models & repos; Home
  dashboard + search/filter/sort; Add/Edit (with barcode scan) / Detail (+/- qty, history, undo);
  alerts screen; local + WorkManager notifications; B&W subscription screen + in_app_purchase +
  entitlement caching + gating; reports (monochrome charts + PDF); CSV/JSON export & import;
  EN/HI localization. Unit tests pass (expiry, low-stock, gating). Dart `flutter analyze` clean.
  Backend: Laravel + Filament admin (MariaDB), API (config/entitlement/verify/rtdn/backup) tested
  end-to-end, super admin + plans + settings seeded; expansion to Customers/Stores/Medicines
  management in progress.
- Backend URL default: http://med-stock-api.test/api/v1 (override with --dart-define=API_BASE_URL).
- 2026-07-04 — Debug + **release** APKs build clean (`--split-per-abi`: armeabi-v7a 23.8MB, arm64-v8a
  27.6MB, x86_64 30.2MB; minSdk 24, compileSdk/targetSdk 36). Backend expanded (subagent) with
  Customers/Stores/Medicines/Plans management, many filters, soft-delete Trash, pagination, editable
  plan features, Google Fonts (Poppins) + Font Awesome; 30 customers/40 stores/120 medicines seeded;
  backend tests 6/6 green. **Project split into `app/` (Flutter) + `backend/` (Laravel) folders.**
- Fixes made during build: workmanager 0.5→0.9 (dead embedding API), file_picker→file_selector
  (file_picker hardcoded compileSdk 34 / old Groovy KGP broke the build), compileSdk 36.
- minSdk note: toolchain re-applies Flutter's default 24 on each build; 23 (Android 6.0) needs a
  one-line change to the flutter SDK's FlutterExtension.kt (see docs/HOWTO_RUN.md).
