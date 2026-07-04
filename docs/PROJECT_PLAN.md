# Project Plan — Medicine Stock & Expiry Tracker (v2)

## 1. Summary

Upgraded, offline-first Android app for pharmacy / medical-shop owners to add, track, and manage medicine stock, with expiry and low-stock reminders. Strictly **black & white** UI, built to run on **old, low-end Android phones**. Free tier = 7 medicines; paid tiers unlock unlimited + premium features. A minimal backend handles subscription validation and optional cloud backup only.

## 2. Goals & non-goals

**Goals**
- Fast, reliable, works fully offline.
- Never lose stock data; never miss an expiry.
- Installs and runs smoothly on cheap 1–2 GB RAM phones (Android 5.0+).
- Monochrome, distraction-free, easy for a busy, non-technical shop owner.
- Clear, honest free→paid upgrade path.

**Non-goals (v2)**
- No full POS / billing system, no GST invoicing, no multi-store chains (possible v3).
- No mandatory account/login for free users.
- No color theming or heavy visuals.

## 3. Target users

Independent pharmacy and medical-store owners in India (₹ pricing, English + Hindi), often on budget Android hardware, limited/intermittent internet, low tolerance for complexity.

## 4. Platform & compatibility

| Item | Decision |
|---|---|
| Framework | Flutter (stable), Dart 3 |
| Min Android | `minSdkVersion 23` (Android 6.0) — hard floor for Flutter 3.44 (engine rejects below 23), ~98% device coverage. Still below Flutter's default of 24, so older phones are supported |
| Target/Compile SDK | Latest required by Play Store |
| ABIs | `arm64-v8a` + `armeabi-v7a` (32-bit support for old phones) |
| App size | Target < 20 MB release AAB |
| RAM budget | Runs on 1 GB; smooth on 2 GB |
| Offline | Full core functionality with no network |

> If a dependency demands a higher minSdk, replace it with a lighter one instead of dropping old-phone support.

## 5. Architecture

**Client (Flutter) — layered:**
- `presentation/` — screens, widgets, controllers (Riverpod).
- `domain/` — entities, use-cases (expiry status, low-stock, gating).
- `data/` — SQLite (sqflite) DB, DAOs/repositories, models, migrations.
- `services/` — notifications (flutter_local_notifications + workmanager + timezone), billing (in_app_purchase), backup/export (csv/pdf/share), barcode (mobile_scanner).

**Source of truth:** local SQLite. Backend is optional and only for entitlement + cloud backup.

**Backend (Supabase or Firebase):**
- Purchase verification (Google Play Developer API).
- Entitlement store + fetch.
- RTDN (Real-Time Developer Notifications) webhook for subscription lifecycle.
- Encrypted cloud backup storage (premium).

## 6. Data model (high level)

`medicines` (name, brand, category, batch_no, barcode, quantity, unit, low_stock_threshold, purchase_price, selling_price, supplier_id, mfg_date, expiry_date, notes, timestamps, is_deleted) · `suppliers` · `categories` · `stock_movements` (audit) · key-value settings.
Indexes on `expiry_date`, `name`, `quantity`, `barcode`. Versioned migrations. Full schema in `BUILD_PROMPT.md` → DATA MODEL.

## 7. Key logic

- **Expiry status:** EXPIRED / EXPIRING (configurable window, default 30 days) / OK — shown as **text + outline icons + weight, never color.**
- **Low stock:** `quantity <= low_stock_threshold`.
- **Notifications:** daily background check (~9 AM) + per-item expiry reminders at chosen window; grouped, plain-text.
- **Free gating:** count non-deleted medicines; block 8th add; re-validate entitlement server-side.

## 8. Monetization

Free (7 medicines) → Premium Monthly / Yearly (Best Value) / Lifetime. Feature gating and pricing detailed in `SUBSCRIPTION_PLANS.md`. Server-side purchase verification to prevent tampering.

## 9. Design system (monochrome)

- Palette: `#FFFFFF`, `#F5F5F5`, `#E0E0E0`, `#9E9E9E`, `#616161`, `#000000`. No other colors.
- Dark mode: `#000000` background, `#FFFFFF` text — still monochrome.
- Components: bordered cards, thin dividers, outline icons only, text status chips, high contrast, large tap targets, scalable fonts.
- Charts: black/gray bars & lines, hatch/pattern fills to differentiate series (no color).
- Accessibility: WCAG-contrast, semantic labels, status never color-only.

## 10. Milestones (phases)

| Phase | Outcome |
|---|---|
| **0. Setup** | Repo, Flutter project, min/target SDK + ABIs, B&W theme, CI-lint. |
| **1. Core CRUD** | DB + models + migrations; Add/Edit/Detail/Home list; search/filter/sort; free-tier counter. |
| **2. Alerts** | Expiry & low-stock logic; local + background notifications; alerts center; settings for windows/time. |
| **3. Monetization** | Subscription screen (B&W), in_app_purchase integration, free-tier enforcement, restore purchases. |
| **4. Backend** | Supabase/Firebase; purchase verification + entitlement + RTDN webhook; wire client. |
| **5. Enhancements** | Barcode scan, suppliers, stock movements, reports/analytics, CSV/PDF export, backup/restore, CSV import, i18n (EN/HI). |
| **6. Polish & Release** | Dark mode, accessibility, empty/error states, tests, size optimization, signing, Play Console listing, release AAB. |

Detailed, checkable tasks per phase are in `TASKS.md`.

## 11. Risks & mitigations

- **Old-device compatibility** → keep deps light, test on real/emulated API 21 low-RAM devices, ship 32-bit ABI.
- **Play Billing complexity** → verify server-side, handle grace/cancel via RTDN, always cache last-known entitlement for offline.
- **Notification reliability on Android** → use workmanager + exact-alarm/notification permissions (Android 13+), test OEM battery-optimization behavior.
- **Data loss** → soft deletes + undo, local export always available, optional cloud backup.
- **Scope creep** → POS/GST explicitly deferred to v3.

## 12. Definition of done (v2)

All phases complete, tests passing, release AAB < ~20 MB installs and runs on Android 5.0 / 1–2 GB RAM, offline core verified, subscriptions purchasable + server-verified, monochrome design consistent in light & dark, EN/HI localized, docs updated.

## 13. How to resume in a new session

1. Read this file, then `TASKS.md` (check the last ticked task).
2. Read `BUILD_PROMPT.md` for the exact spec and constraints.
3. Read `SUBSCRIPTION_PLANS.md` before touching billing.
4. Continue from the first unchecked task; keep the B&W + old-phone constraints intact.
