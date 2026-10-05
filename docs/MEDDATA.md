# Meddata — Project Document

> Multi-device pharmacy inventory app for phones + Windows  
> Repo: `D:\meddata` (branch `main`)  
> Last updated: 5 Oct 2026

---

## 1. What is Meddata

An offline-first inventory app for Indian pharmacy / medical-shop owners. Each shop gets one account; all devices (Android phones, Windows PCs) share the same inventory through the server. The owner can add medicines, track stock and expiry by batch, get alerts, and see reports. Free 7-day trial, then Razorpay-based paid subscription.

### Target users

Independent pharmacy and medical-store owners in India (₹ pricing, English + Hindi), often on budget Android hardware, limited/intermittent internet.

### Repository layout

```
meddata/
├── app/          Flutter app (Android, iOS, Windows desktop)
├── backend/      Laravel 12 + Filament admin (REST API, SQLite/MariaDB)
├── docs/         This file
└── README.md
```

---

## 2. Architecture

### Client (Flutter)

```
app/lib/
├── core/           Platform detection, constants, formatters
├── data/
│   ├── db/         SQLite database (database_helper.dart — products, batches, movements, outbox, sync_state)
│   ├── models/     Medicine, StockMovement, SubscriptionPlan
│   └── repositories/  MedicineRepository (CRUD against local DB)
├── domain/         ExpiryAlertPlan, MedicineStatus, ProductStock
├── l10n/           EN + HI localization
├── presentation/
│   ├── screens/    Home, Inventory, ProductDetail, AddEdit, Alerts, Settings, Login/Signup,
│   │               Subscribe, LockScreen, Onboarding, SyncIssues, RazorpayCheckout, Reports
│   └── widgets/    MedicineListTile, StatusChip, SummaryTile, SyncBadge, UIKit
├── services/       AuthService, SubscriptionService, NotificationService, SettingsService,
│                   ApiClient, BackupService, DeviceId
├── state/          MedicineProvider (reactive state via ChangeNotifier + Provider)
├── sync/           SyncEngine (push/pull), Outbox (local mutation queue)
└── theme/          AppTheme (green #0A302E + orange #FF6B2C, GoogleSansFlex font)
```

- **State management:** Provider / ChangeNotifier
- **Local DB:** sqflite (+ sqflite_common_ffi for Windows desktop)
- **Notifications:** flutter_local_notifications + timezone (scheduled expiry/low-stock alerts)
- **Barcode:** mobile_scanner (phones only; desktop uses USB scanner typing into the field)
- **Payments:** Razorpay — WebView checkout on phones, browser redirect on desktop
- **Export:** csv + pdf + printing + share_plus
- **Auth:** Custom Bearer token (no Sanctum) → email/password login → api_tokens table (SHA-256 hash)

### Backend (Laravel 12 + Filament)

```
backend/
├── app/
│   ├── Http/Controllers/Api/   AuthController, SyncController, ShopController,
│   │                           PaymentController, BrowserCheckoutController,
│   │                           ConfigController, EntitlementController, etc.
│   ├── Models/                 User, Shop, Product, Batch, StockMovement,
│   │                           PriceChange, Entitlement, Payment, Coupon, etc.
│   ├── Filament/Resources/     Admin panel: ShopResource, ProductResource,
│   │                           MasterCatalog, CouponResource, PaymentResource
│   └── Services/               RazorpayService
├── routes/api.php              All API routes under /api/v1
├── database/migrations/        Schema
└── database/database.sqlite    Dev database
```

### Platform targets

| Platform | Min version | Notes |
|----------|-------------|-------|
| Android  | minSdk 24 (Android 7.0) | arm64-v8a + armeabi-v7a (32-bit). 24 is the effective floor: Flutter's default, and plugins such as flutter_secure_storage need it |
| iOS      | 14.0 | |
| Windows  | 10+ | sqflite FFI, side navigation, browser payment |

### Design system

- **Brand green:** `#0A302E` (darkest), `#0E4D4A` (primary), `#12615C` (mid)
- **Accent orange:** `#FF6B2C` (CTAs, FAB)
- **Status colors:** green `#12A47C`, amber `#EA8C1F`, red `#E5484D`
- **Font:** GoogleSansFlex (variable weight)
- **Dark mode:** dark teal surfaces, same palette
- **Radii:** 12px inputs, 16px buttons, 18px cards

---

## 3. Data model

### App (local SQLite)

| Table | Purpose |
|-------|---------|
| **products** | id, name, name_norm, manufacturer, category, composition, unit, pack_size, hsn, gst_rate_bp, barcode, low_stock_threshold_units, discount_bp, master_id, notes, version, created_at, updated_at, is_deleted |
| **batches** | id, product_id (FK), batch_no, expiry_date, mfg_date, mrp_paise, purchase_rate_paise, server_qty_units, version, created_at, updated_at, is_deleted |
| **inv_movements** | id, batch_id, product_id, delta_units, reason (add/sell/adjust/restock), ref_type, ref_id, occurred_at, synced |
| **price_changes** | id, batch_id, field, old_paise, new_paise, device_id, created_at |
| **outbox** | seq (auto), mutation_id, table_name, op (upsert/delete/movement), row_id, base_version, data (JSON), status (pending/conflict/rejected), result, created_at |
| **sync_state** | key-value (cursor, linked_user) |

Prices are stored in **paise** (integer). Stock = `server_qty_units` + sum of unsynced `inv_movements`.

### Backend (mirrored + admin tables)

Same products/batches/stock_movements/price_changes per shop, plus: users, shops, devices, entitlements, payments, coupons, master_medicines (shared catalog), app_settings, api_tokens, password_reset_codes.

---

## 4. Server sync protocol

Every device in a shop shares inventory through the server. The sync engine (60s periodic + 2s debounce after edits):

1. **Push** — Send outbox mutations (batch of 200). Each carries `mutation_id` (dedup), `table`, `op`, `row_id`, `base_version`, `data`. Server responds per-mutation: `ok` (with new version), `conflict` (with server's current row), or `rejected`.
2. **Pull** — Cursor-based: `GET sync/pull?since=<cursor>&limit=500`. Server returns changed products, batches, stock_movements, price_changes since cursor.
3. **Conflicts** — On conflict, the server's row is applied locally immediately (so stale prices are never shown). The user's change stays in `issues` for "Use theirs / Keep mine" resolution.
4. **Account linking** — First sync checks if server shop already has data. If both local and server have data → prompt user to merge or discard local.
5. **Stock** — Never overwritten by sync. Local stock = server_qty_units + unsynced local movements. Movements sync separately.

### Price safety flow

1. Phone edits a batch's MRP → sends the `base_version` it last saw
2. Server: version matches → accept, record in `price_changes` audit table
3. Windows sends an edit based on a stale version → server returns `conflict` + current row
4. Windows shows server price immediately, user chooses "Use theirs / Keep mine"
5. (Future, P3) Billing will re-verify price/version at bill time — stale price = bill refused

---

## 5. API surface (`/api/v1`)

### Public (no auth)
| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | `/config` | App config: trial_days, razorpay_key_id, plans |
| POST | `/register-device` | Anonymous device registration |
| POST | `/payment/return` | Razorpay redirect callback |
| GET | `/pay/{order}` | Browser checkout page (desktop) |
| POST | `/pay/complete` | Browser checkout completion |
| POST | `/rtdn` | Google Play webhook (legacy) |

### Auth (public, throttled)
| Method | Endpoint | Purpose |
|--------|----------|---------|
| POST | `/auth/register` | Create account |
| POST | `/auth/login` | Login → Bearer token |
| POST | `/auth/forgot-password` | Request reset code |
| POST | `/auth/reset-password` | Reset with code |

### Authenticated (Bearer token)
| Method | Endpoint | Purpose |
|--------|----------|---------|
| POST | `/auth/logout` | Revoke token |
| GET | `/auth/me` | Current user profile |
| PATCH | `/auth/profile` | Update profile |
| POST/DELETE | `/auth/avatar` | Profile photo |
| POST | `/auth/change-password` | Change password |
| GET/PATCH | `/shops/current` | Current shop details |
| GET | `/sync/status` | Sync cursor + counts |
| GET | `/sync/pull` | Pull changes since cursor |
| POST | `/sync/push` | Push outbox mutations |
| GET | `/entitlement` | Current subscription status |
| POST | `/device/trial` | Register/check trial |
| POST | `/coupon/validate` | Validate coupon code |
| POST | `/order/create` | Create Razorpay order |
| POST | `/payment/verify` | Verify Razorpay payment |
| POST | `/backup` | Upload backup |
| GET | `/backup/latest` | Download latest backup |
| GET | `/medicines/search` | Search master catalog |

---

## 6. Subscription & monetization

### Model (Razorpay — not Google Play Billing)

- **7-day free trial** from first login. After trial with no paid subscription → full app lock (LockScreen paywall).
- **Plans** defined in admin panel, served via `/config`.
- **Payment:** Razorpay checkout — WebView on phones, browser redirect on desktop.
- **Coupons:** admin-generated, percentage or flat discount.

### Entitlement logic

App is unlocked if ANY of:
- Within 7-day trial (`trial_ends_at` in future), OR
- Active paid subscription (Razorpay payment verified, not expired / lifetime)

Otherwise → LockScreen.

### Coupon data model

`code` (unique), `type` (percentage|flat), `value`, `max_uses`, `used_count`, `min_amount`, `plan_id` (nullable), `valid_from`, `valid_until`, `is_active`.

### Payment flow

1. User taps plan → optional coupon → `POST /order/create` (applies coupon)
2. Razorpay checkout opens (WebView on phone, browser on desktop)
3. On success → `POST /payment/verify` (signature check) → entitlement activated
4. App caches entitlement locally (works offline)
5. Desktop: browser opens `/pay/{order}`, server verifies and activates, app auto-refreshes

---

## 7. How to run

### Flutter app

```bash
cd app
flutter pub get
flutter gen-l10n                    # localization (EN/HI)
flutter run                         # connected device / emulator
flutter build apk --release --split-per-abi   # release APK
flutter build windows --release     # Windows (needs Visual Studio C++ workload)
```

**Backend URL override:**
```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
```

### Laravel backend

```bash
cd backend
composer install
cp .env.example .env               # set DB, ADMIN_EMAIL, ADMIN_PASSWORD, Razorpay keys
php artisan migrate:fresh --seed    # schema + admin + plans + settings
php artisan medicines:import <csv>  # import master catalog (CSV path is required)
php artisan serve --host=0.0.0.0 --port=8000
```

- **Admin panel:** `/admin` → login with ADMIN_EMAIL / ADMIN_PASSWORD from `.env`

### Tests

```bash
# Backend (58 tests: sync, catalog, browser payment, payment security, admin)
cd backend && php artisan test

# App unit tests (27 tests: repository, product stock, expiry, status, auth token storage)
cd app && flutter test

# Two-device integration (3 tests: stock sync, price edit, offline, merge)
cd app && flutter test test/integration/
```

---

## 8. Task list

### P0 — Security cleanup ✅ Done

- [x] Remove hardcoded DB password and admin password from repo
- [x] Tests run on in-memory SQLite
- [x] Admin login via .env ADMIN_EMAIL / ADMIN_PASSWORD
- [x] ⚠️ Old passwords still in git history — rotate them

### P0b — Security fixes ✅ Done (Oct 2026)

- [x] Payments: no plan without a real Razorpay signature outside `APP_ENV` local/testing (`/order/create` → 503 without keys; `/payment/verify` and browser checkout refuse). Previously a blank Razorpay key in the admin panel let the app "pay" in test mode and get Premium for free
- [x] A used payment can't be replayed to restart a plan (each order activates exactly once, row-locked); `/payment/verify` reports the plan's real state
- [x] Legacy Google Play `/purchase/verify` fails closed (it accepted any token)
- [x] App: test-mode payment and the 7-tap Developer section exist only in debug builds; release shows "Payments are not available right now"
- [x] App: auth token in `flutter_secure_storage` (moved from shared_preferences on first launch); logs out only on a 401, never when offline; logout clears cached premium/trial
- [x] Verified with tests: logging in with another user's device_id can't take over their plan; forgot-password `dev_code` only in local/testing
- [ ] Follow-up: a 401 during sync doesn't log out yet (checked at app start and after payment only)

### P1 — Products, batches, sync, Windows 🔧 12/14 done

- [x] Server sync API: per-user shop; products, batches, stock movements; sync/status, sync/pull, sync/push; shop data isolation
- [x] Price safety: edit_version conflict check, price_changes audit table
- [x] App local DB v2: products, batches, inv_movements (stock ledger), outbox, sync_state; prices in paise
- [x] Sync engine: push outbox first, then pull changes; conflict → server value shown immediately, user's change held for "use theirs / keep mine"
- [x] Sync UI: badge (Synced / Syncing / Offline / Need attention), sync issues screen, new-device merge/discard prompt
- [x] Expiry notifications fix: 60-day lookahead scheduling, "daily reminder time" setting actually used
- [x] Master catalog growth: shop's new medicines auto-added (max 200/shop/day); medicines:import does upsert not truncate
- [x] Migration consolidation: add-column migrations merged into create migrations (fresh DB needed on deploy)
- [x] Fresh-schema cleanup: removed v1→v2 upgrade code, medicines_legacy, old supplier code
- [x] Product-wise screens: inventory shows batches grouped under medicine; product detail screen; low stock on product total, expiry on stocked batches
- [x] Admin panel cleanup: removed demo Customers/Stores/Medicines; added Shops page (list + detail with devices & products), Master catalog page, dashboard widgets (recent shops, growth, categories)
- [x] Desktop browser payment: app creates order, opens Razorpay page in browser, payment verified server-side, app auto-refreshes; 3 tests
- [ ] **Windows app build** — code ready (sqflite FFI, camera/scanner hidden on desktop, side menu for large screens, Windows notifications, Meddata branding). Blocked on Visual Studio "Desktop development with C++" install. Installer (MSIX or Inno Setup) also pending.
- [ ] **Phone sync UI testing** — real-device test of sync flow (phone was disconnected)

### P2 — Onboarding ⬜ Next

- [x] Barcode lookup: search shop products first, then master catalog
  - Inventory search has a scan button (camera on phones; on Windows a dialog a USB scanner types into). Shop's own product → opens it; else master-catalog match (`GET /medicines/search?barcode=`) → Add screen prefilled; else Add screen with only the barcode filled. The free-plan limit applies before a new medicine.
  - Add screen (new medicine only): after a scan, or Enter from a USB scanner in the barcode field, a barcode the shop already has offers "Add batch" to that product; a catalog match prefills name, manufacturer, unit and MRP (asks first if a name is already typed).
- [ ] Excel/CSV import wizard: column mapping UI, preview, row validation, batch import
- [ ] AI invoice reading (server-side): photo/PDF → extract purchase entry. Needs queue worker on server (`supervisor` for `queue:work`)

### P3 — GST billing ⬜ Planned

- [ ] Counter sale screen: earliest-expiry batch auto-selected first (FEFO)
- [ ] Tax calculation: CGST/SGST (intra-state) / IGST (inter-state)
- [ ] Invoice PDF generation: A4 format + 80mm thermal printer format
- [ ] WhatsApp invoice sharing
- [ ] **Billing is online-only**: bill created on server, invoice number assigned server-side (per-shop, per-financial-year, gap-free series like `PREFIX/26-27/000042`)
- [ ] Price re-verification at bill time: if batch price changed since device loaded it → bill refused, device shows "₹X is now ₹Y"
- [ ] Internet check: if offline → bill screen blocked. Inventory continues to work offline.

### P4 — Accounting ⬜ Planned

- [ ] Parties table: unified customers + suppliers
- [ ] Ledgers: per-party running balance
- [ ] Payments in/out tracking
- [ ] Sale returns and purchase returns
- [ ] GSTR-1 / GSTR-3B style reports (get output reviewed by a CA)
- [ ] Stock valuation report
- [ ] Profit calculation
- [ ] Expiry loss tracking

### Remaining from original task list

- [ ] Verify notification reliability under battery optimization (real OEM device test)
- [ ] Supplier management UI (model/repo exist, no screen)
- [ ] Bulk CSV import of medicines (being replaced by P2 import wizard)
- [ ] Accessibility audit: tap targets, scalable text, semantic labels
- [ ] Widget tests (Add/Edit, Home) + smoke integration test
- [ ] Final README update
- [ ] Home-screen "today's expiries" widget (optional, only if doesn't raise minSdk)

---

## 9. Architecture decisions (locked in)

| Decision | Details |
|----------|---------|
| Server sync | All devices in a shop share data through the server |
| One login per shop | No staff roles yet; may add later |
| Price safety | `edit_version` conflict check + `price_changes` audit — no "main device", any device can edit prices |
| Windows payment | Browser-based Razorpay checkout (no in-app payment on desktop) |
| Offline billing | Blocked — Internet required for bills. Inventory works offline |
| Schema changes | Wipe DB + re-upload (no upgrade migrations while there are no real users) |
| Master catalog | Shop's new medicines auto-added without moderation (max 200/shop/day) |
| AI invoice | Server-side processing, not on-device |
| Pricing | Plan prices not finalized yet |

---

## 10. Deploy checklist (before going live)

- [ ] `php artisan migrate:fresh --seed` (schema changed, fresh DB required; no real users yet)
- [ ] `php artisan medicines:import <csv>` (CSV path is now a required argument)
- [ ] Set `ADMIN_EMAIL` and `ADMIN_PASSWORD` in `.env`
- [ ] Set `APP_ENV=production` (with `local` and no Razorpay keys the server still accepts fake payments) and `APP_DEBUG=false`, then run `php artisan config:cache`
- [ ] Use live `rzp_live_` Razorpay keys (with `rzp_test_` keys anyone can "pay" with test cards)
- [ ] Rotate old DB password and admin password (exposed in git history)
- [ ] Set Support WhatsApp number in admin panel
- [ ] Log in to admin, verify Shops + Master catalog pages
- [ ] Add live site URL to Razorpay dashboard (for desktop browser payment `/api/v1/pay/...`)
- [ ] Set up `queue:work` under supervisor (needed for P2 AI invoice)
- [ ] Build and test Windows installer (Visual Studio needs "Desktop development with C++" **and** the "C++ ATL for latest build tools" component, for flutter_secure_storage)
- [ ] Cross-device testing: Windows ↔ phone sync, price conflicts, offline edits, USB barcode scanner

---

## 11. Commit history

Newest first. Run `git log --oneline` for the live state.

| SHA | Description |
|-----|-------------|
| `c6b15b4` | Security: payment bypasses closed, debug-only test tools, secure token storage |
| `7edea47` | App: barcode lookup — shop products first, then master catalog |
| `bd2caa4` | Docs unified into docs/MEDDATA.md |
| `1635c23` | App: Windows desktop support (build pending Visual Studio) |
| `e7ce9e4` | Payments: desktop browser checkout |
| `a778ff0` | Admin: demo tables removed; Shops + Master catalog pages |
| `0e6f92d` | App: product-wise inventory, batches under medicine |
| `b39db8b` | Migrations consolidated into create migrations |
| `1c62cfe` | Master catalog grows from shop medicines |
| `1f43cd0` | App: fresh local schema, v1 migration + legacy code removed |
| `c0914ab` | App: expiry alerts on time; reminder time setting works |
| `0f09f45` | App: sync badge, conflicts screen, merge prompt |
| `ae322c0` | App: sync engine (push, pull, conflicts) |
| `80ef687` | Sync: conflict check on edit_version |
| `4cc408a` | App: local DB v2 (products, batches, ledger, outbox) |
| `1996006` | Backend: shops, product/batch inventory, sync API |
| `64a61ee` | Security: hardcoded DB/admin passwords removed |
| `a834f6a` | Trial days by calendar date; "Low" without "In stock" |
| `0e9eca5` | Support chat + feedback via WhatsApp |
| `fc8a13c` | Inventory status filters (All / Low / Expiring / Expired) |
| `833f568` | Snackbars above bottom bar |
| `53fb762` | Profile photo upload/replace/remove |
| `9b8da5c` | Profile: Log out above bottom bar |
| `09d9d4f` | Block future mfg date and mfg-before-expiry |
| `3e7a3cf` | ml unit shows ML; edit removes old "Required" |
| `0d79744` | Paywall/checkout polish, logo, splash |
| `2666e93` | Payment + logo changes re-applied |

---

## 12. How to resume in a new session

1. Read this file (`docs/MEDDATA.md`).
2. Check the task list in §8 — find the first unchecked item.
3. Run `git log --oneline -5` to see what was last done.
4. Continue from the next unchecked task.
