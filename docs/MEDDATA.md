# Meddata — Project Document

> Multi-device pharmacy inventory app for phones + Windows  
> Repo: `D:\meddata` (branch `main`)  
> Last updated: 8 Oct 2026 (P0b, P2, P3, P4 done; pack sizes)

---

## 1. What is Meddata

An offline-first inventory app for Indian pharmacy / medical-shop owners. Each shop gets one account; all devices (Android phones, Windows PCs) share the same inventory through the server. The owner can add medicines, track stock and expiry by batch, get alerts, and see reports. Free 7-day trial, then Razorpay-based paid subscription.

### Target users

Independent pharmacy and medical-store owners in India (₹ pricing, English; dates day/month/year), often on budget Android hardware, limited/intermittent internet.

### Repository layout

```
meddata/
├── app/          Flutter app (Android, iOS, Windows desktop)
├── backend/      Laravel 13 + Filament 5 admin (REST API, SQLite/MariaDB)
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
├── presentation/
│   ├── screens/    Home, Inventory, ProductDetail, AddEdit, Alerts, Settings, Login/Signup,
│   │               billing/ (NewBill, Bills, BillDetail, ShopSettings), import/ (ImportWizard), InvoiceScan,
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
- **Export / import:** csv + pdf + printing + share_plus; .xlsx read with `archive` + `xml` (pure Dart)
- **Auth:** Custom Bearer token (no Sanctum) → email/password login → api_tokens table (SHA-256 hash)

### Backend (Laravel 13 + Filament 5)

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
| **sync_state** | key-value (cursor, linked_account = server user id, linked_email) |

Prices are stored in **paise** (integer). Stock = `server_qty_units` + sum of unsynced `inv_movements`.

**Pack size.** Stock and bill quantities are always in the product's `unit`. `products.pack_size` is how many pieces one pack holds (tablets per strip, ml per bottle — e.g. 6, 1, 10, 15; it is never assumed). It only *does* anything when the unit counts pieces (`Tablets`, `Capsules`, `ML`) and is more than 1 (`PackSize.applies`): then the Add/Edit screen takes stock as strips + loose, the bill screen takes quantities as strips + loose, and bills/invoices read "2 strips + 3 tablets" (`app/lib/domain/pack_size.dart`, `App\Support\PackSize`). A medicine counted in `Strips`/`Bottles` keeps its pack size (from the catalog label, the invoice pack text or the import's "10's") but is counted in whole packs. `bill_items.pack_size` and `sale_return_items.pack_size` are copied at bill time, like `unit`.

**Prices are per price pack.** A batch's `mrp_paise` and `purchase_rate_paise` are per `pricePack` pieces = the pack size when it applies, else one unit. So a strip of 15 at ₹35.50 is stored as 3550 for 15 tablets — never a rounded per-tablet price. Every amount is worked out on the whole line and rounded once: `GstMath.line(..., packSize)` does `gross = round(mrp × qty / packSize)` (same on the server), stock valuation, expiry loss and the profit report do `round(qty × price / pricePack)`, and a purchase entry stores the supplier's per-pack rate as `round(rate × pricePack / units_per_pack)` (the same number when the packs agree). Selling 23 tablets of that strip bills ₹54.43; 30 tablets bill exactly ₹71.00.

### Backend (mirrored + admin tables)

Same products/batches/stock_movements/price_changes per shop, plus: users, shops, devices, entitlements, payments, coupons, master_medicines (shared catalog), app_settings, api_tokens, password_reset_codes, invoice_scans (AI invoice uploads: file, status, extracted JSON, token usage), bills + bill_items (one item row per batch sold, all amounts in paise, seller details, unit and pack_size copied at bill time), invoice_series (per shop + FY counter). Shops gain `legal_name` and `default_gst_rate_bp` (500 = 5%). Stock movement reasons include `sale`, `sale_cancel`, `purchase`, `purchase_free`, `purchase_cancel`, `expiry_writeoff`. Accounting tables: parties, purchases + purchase_items, party_payments, sale_returns + items, purchase_returns + items, document_series (CN/DN counters); bills gain a nullable `party_id`.

---

## 4. Server sync protocol

Every device in a shop shares inventory through the server. The sync engine (60s periodic + 2s debounce after edits):

1. **Push** — Send outbox mutations (batch of 200). Each carries `mutation_id` (dedup), `table`, `op`, `row_id`, `base_version`, `data`. Server responds per-mutation: `ok` (with new version), `conflict` (with server's current row), or `rejected`.
2. **Pull** — Cursor-based: `GET sync/pull?since=<cursor>&limit=500`. Server returns changed products, batches, stock_movements, price_changes since cursor.
3. **Conflicts** — On conflict, the server's row is applied locally immediately (so stale prices are never shown). The user's change stays in `issues` for "Use theirs / Keep mine" resolution.
4. **Account linking** — Local data is linked to the server user id (an email change keeps it). First sync checks if server shop already has data. If both local and server have data → prompt user to merge or discard local. Another account's unsynced changes are never dropped without asking.
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
| GET | `/bills` | Bills by date range/search/status, paginated, with range total |
| POST | `/bills` | Create bill (201; 200 + `replayed` on retry; 409 price changed; 422 stock/batch) |
| GET | `/bills/{id}` | Bill with items + GST summary (other shop → 404) |
| POST | `/bills/{id}/cancel` | Cancel bill: stock back, number stays used |
| GET/POST | `/parties` | List (type, search, balances) / create (retry-safe uuid; 422 bad/duplicate GSTIN) |
| GET/PATCH/DELETE | `/parties/{id}` | Party with balance and open documents / update / soft delete (422 `balance_not_zero`) |
| GET | `/parties/{id}/ledger` | Running-balance ledger (`from`, `to`) |
| GET/POST | `/payments` | Payments in/out (422 `over_allocated`, `not_payable`) |
| POST | `/payments/{id}/cancel` | Cancel a payment |
| GET/POST | `/purchases` | Supplier bills; server adds the stock (422 `duplicate_invoice`, `party_not_supplier`, `plan_limit`, …) |
| GET | `/purchases/{id}` | Purchase with outstanding and returned qty |
| POST | `/purchases/{id}/cancel` | Takes the stock back out (422 `has_returns`, `has_payments`, `insufficient_stock`) |
| GET/POST | `/sale-returns`, GET `/sale-returns/{id}` | Credit notes (422 `return_exceeds_sold`, `bill_cancelled`) |
| GET/POST | `/purchase-returns`, GET `/purchase-returns/{id}` | Debit notes (422 `return_exceeds_bought`, `insufficient_stock`) |
| GET | `/gst/gstr1`, `/gst/gstr3b` | Monthly GST summaries (`month=Y-m`), for CA review |
| GET | `/reports/profit` | Profit by day/product/category from bills (`from`, `to`) |
| GET | `/medicines/search` | Search master catalog (`?q=` name prefix or `?barcode=`) |
| POST | `/invoices/scan` | Upload purchase invoice photo/PDF for AI reading (202) |
| GET | `/invoices/scan/{id}` | Scan status + extracted lines |

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
touch database/database.sqlite      # SQLite dev DB (gitignored)
cp .env.example .env               # set DB, ADMIN_EMAIL, ADMIN_PASSWORD, Razorpay keys, ANTHROPIC_API_KEY
php artisan migrate:fresh --seed    # schema + admin + plans + settings
php artisan medicines:import <csv>  # import master catalog (CSV path is required)
php artisan serve --host=0.0.0.0 --port=8000
php artisan queue:work database   # needed for AI invoice reading
```

**AI invoice env:** `ANTHROPIC_API_KEY` (required for invoice scans), `ANTHROPIC_MODEL=claude-opus-5-5`; optional `ANTHROPIC_EFFORT`, `ANTHROPIC_MAX_TOKENS`, `ANTHROPIC_TIMEOUT`, `ANTHROPIC_FALLBACKS` (`off` disables the refusal fallback), `ANTHROPIC_BASE_URL`, `DB_QUEUE_RETRY_AFTER=600`.

- **Admin panel:** `/admin` → login with ADMIN_EMAIL / ADMIN_PASSWORD from `.env`

### Tests

```bash
# Backend (148 tests: sync, catalog, browser payment, payment security, invoice scans, billing + GST maths incl. per-pack, admin)
cd backend && php artisan test   # accounting: parties, purchases, payments, returns, ledgers, GSTR

# App tests (417 tests - 416 pass, 1 skipped two-device test: repository, product stock, pack sizes + per-pack GST, expiry, status, auth token storage, invoice drafts/scan,
#   Excel/CSV import, billing (GST maths, FEFO, cart, invoice PDF, new-bill screen),
#   widget tests for Add/Edit + Home/Inventory + import wizard,
#   accessibility on every screen, add→alert smoke test)
cd app && flutter test

# Two-device integration (needs a running backend; skipped otherwise)
cd app && flutter test test/integration/
```

---

## 8. Task list

### Status at a glance (8 Oct 2026)

| Area | Status |
|------|--------|
| P0 / P0b Security | ✅ Done |
| P1 Products, batches, sync, Windows | 🔧 12/14 — remaining 2 need a Windows PC with Visual Studio and a real phone |
| P2 Onboarding (barcode lookup, Excel/CSV import, AI invoice reading) | ✅ Done |
| P3 GST billing | ✅ Done — a few decisions to confirm (§9) |
| P4 Accounting (parties, ledgers, payments, purchases, returns, GSTR, valuation, profit, expiry loss) | ✅ Done — decisions to confirm, GSTR needs CA review |
| Needs the owner | Windows build + installer, real-device tests (sync, notifications), deploy checklist (§10), brand-colour contrast decision (status pills, plan toggle), confirm billing/accounting decisions (§8 P3/P4, §9), CA review of GSTR output |

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
- [x] A 401 during background sync, billing or invoice reading signs out (`AuthService.sessionRejected`); offline, timeouts and 5xx never do; unsynced changes stay on the device and upload when the same account signs in again; the login screen says the session expired (`test/session_expiry_test.dart`)
- [x] Local data is tied to the server user id, not the email (`sync_state.linked_account`): changing the email keeps everything and uploads waiting changes; an older email link migrates with no prompt (`test/account_link_test.dart`)
- [x] Another account signing in while the device has changes not uploaded: sync stops and the app asks — sign back in to that account (login pre-filled) or remove them after a confirmation; with nothing waiting, the old copy is cleared as before
- [x] Login / Forgot password loading spinners are visible (ink) on the disabled button

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
- [ ] **Windows app build and installer verification** — desktop UI and an Inno Setup per-user installer recipe are in place (`app/tool/build_windows_installer.ps1`). Build and smoke-test on Windows with Visual Studio "Desktop development with C++" and the C++ ATL component; install Inno Setup 7 (or 6) to produce the setup executable.
- [ ] **Phone sync UI testing** — real-device test of sync flow (phone was disconnected)

### P2 — Onboarding ✅ Done

- [x] Barcode lookup: search shop products first, then master catalog
  - Inventory search has a scan button (camera on phones; on Windows a dialog a USB scanner types into). Shop's own product → opens it; else master-catalog match (`GET /medicines/search?barcode=`) → Add screen prefilled; else Add screen with only the barcode filled. The free-plan limit applies before a new medicine.
  - Add screen (new medicine only): after a scan, or Enter from a USB scanner in the barcode field, a barcode the shop already has offers "Add batch" to that product; a catalog match prefills name, manufacturer, unit and MRP (asks first if a name is already typed).
- [x] Excel/CSV import wizard: Settings → Data → "Import stock from Excel / CSV" (also on the empty Inventory)
  - Steps: pick .xlsx/.csv → sheet + header row (found automatically, even below title rows) → match columns (auto-guessed from English and distributor headers: Item Name, Batch, Exp, MRP, Qty, Pack, Rate, Mfr, Closing Stock, PTR…, checked against the column's values) → check every row (what imports, what is skipped and why) → import with progress and a results screen
  - Parsing/validation in `app/lib/services/import/` (pure Dart, runs in a background isolate): format detected from content (CSV in UTF-8/UTF-16/Latin-1 with `,` `;` tab `|`; .xlsx via `archive` + `xml`; old .xls/.ods get a clear message); dates dd/MM/yyyy, dd-MM-yy, MM/yy, MMM-yy, dd-MMM-yyyy, yyyy-MM-dd and Excel serials (month-only expiry = end of month); prices like ₹1,234.50 / 45/- / 1,00,000; "10+2" qty = 12; units from pack text (10's/1x10 → Strips, 100ML → Bottles)
  - Rows join an existing medicine with the same name when maker/unit agree; same medicine + batch (or same expiry without batch) = duplicate → skip or add quantity; zero-qty rows skipped by default; free-plan limit explained before importing
  - Saved in one transaction via `MedicineRepository.importStock` (products, batches, opening/purchase movements, outbox — same as adding by hand). The old fixed-column CSV import is removed; JSON backup restore kept
- [x] AI invoice reading (server-side): photo/PDF → extract purchase entry
  - `POST /invoices/scan` (photo ≤7 MB / PDF ≤10 MB; trial or paid plan; 6/min and 100/day per account) → queued `ProcessInvoiceScan` job reads it with Claude (`claude-opus-5-5`, effort medium, fixed JSON schema via `output_config.format`, server-side refusal fallback `fallbacks: "default"`) → `GET /invoices/scan/{id}`, shop-scoped
  - Dates/numbers/GSTIN/HSN normalised; each line matched to the shop's products and the master catalog (barcode, then exact name, then loose name); retries with backoff; clear failure codes (`not_configured`, `refused`, `too_long`, `unreadable_output`, `no_items`, `auth`, `busy`, `stalled` after 15 min); files deleted after 30 days
  - App "Scan invoice" button on Add Medicine: camera/gallery/PDF on phones, file picker on desktop; online-only; editable review (fix/remove lines, duplicate-batch warning) → adds through `MedicineProvider.addFromInvoice` → `MedicineRepository.insert` like a manual add (known medicine = new batch); free-plan limit respected
  - [x] Scanned HSN and GST% saved on new medicines (a known medicine keeps its own)

### P3 — GST billing ✅ Done (Oct 2026)

- [x] Counter sale screen ("New bill" on Home, Bills tab): FEFO — earliest-expiry batch with stock auto-selected, spills to the next batch, batch can be changed, expired batches never sold; qty/line discount, optional customer name/phone/GSTIN/state, payment cash/UPI/card/credit (credit needs a customer name)
- [x] Tax calculation from MRP-inclusive prices: CGST = SGST intra-state, IGST inter-state (customer state ≠ shop state); half-up paise rounding, total rounded to the rupee; same maths in the app preview (`app/lib/domain/gst.dart`) and the server (`App\Support\GstMath`), with shared test vectors
- [x] Invoice PDF: A4 tax invoice + 80mm thermal receipt (shop details, GSTIN, HSN/batch/expiry, GST summary by rate, amount in words, round-off); ₹ printed via embedded GoogleSansFlex subsets (also fixes the reports PDF)
- [x] WhatsApp sharing: PDF via the share sheet; on phones a wa.me text summary to the customer's number
- [x] **Online-only billing**: `POST /bills` with a device-made uuid (retry-safe: a repeat returns the same bill); gap-free invoice numbers per shop per FY, `PREFIX/26-27/000042` (prefix ≤3 letters/digits, default `INV`, so the number fits GST's 16 characters), allocated under a shop row lock; a refused bill uses no number
- [x] Price re-verification: any batch edit since the device loaded it → 409, the line shows "₹X is now ₹Y", accept and retry; 422 shows stock left or an expired/deleted batch
- [x] Internet check: offline → bill screen blocked; inventory keeps working offline. After a bill the app syncs so local stock drops
- [x] Bills tab: date range/search, reprint/share, cancel (stock back via `sale_cancel` movements, number stays used); Shop & invoice details screen (legal name, address, GSTIN — state filled from it, DL no., invoice prefix, default GST rate); HSN and GST rate on medicines; Filament: read-only Bills + Shop "Edit invoice details"
- Default GST 5% for products without a rate (owner decision: retail medicines, OTC, AYUSH, vaccines, devices and kits are 5%; set 0% per medicine for exempt life-saving drugs, blood, contraceptives). Decisions to confirm (see §9): phone bottom bar is now Home · Inventory · + · Bills · Alerts (Profile opens from the Home avatar; the desktop rail shows all); shops without a GSTIN print "INVOICE" with no tax breakup; bill dates/FY use India time

### P4 — Accounting ✅ Done (Oct 2026) — app: Settings → Accounts (Parties, Purchases, GST returns); Reports tabs

- [x] Parties: customers + suppliers in one table (type, phone, GSTIN → state, address, opening balance; **+ = owed to the shop, − = shop owes**; one party per GSTIN); CRUD API, app list/search/balance, detail, add/edit; Filament read-only Parties
- [x] Bills link to a customer party (picker / add on New bill fills the customer); credit bills need one; cash bills still take a typed name
- [x] Purchases (supplier bills): the **server** creates/attaches batches and records `purchase` / `purchase_free` movements, which devices pull — stock is counted once; retry-safe uuid; the same supplier invoice can't be entered twice; input CGST/SGST or IGST by supplier state; cancel takes the stock out (`purchase_cancel`; refused once sold, returned or paid). The AI invoice scan records a purchase when online with a supplier chosen (found by GSTIN), else adds stock locally as before
- [x] Ledgers: per-party running balance (opening, credit bills, purchases, payments in/out, credit notes on account, debit notes; cancelled ones left out); `GET /parties/{id}/ledger`; "Statement of account" PDF to print/share
- [x] Payments in/out: cash/UPI/card/bank/cheque, reference, date, notes, optionally against a credit bill / purchase (no over-allocation); cancel instead of delete
- [x] Sale returns: credit notes `CN/YY-YY/NNNNNN` (gap-free), qty ≤ sold − returned, stock back, GST reversed with GstMath, PDF. Purchase returns: debit notes `DN/...` against a purchase or from stock, stock out, input GST reversed. A bill with a credit note or payment can't be cancelled
- [x] GSTR-1 (B2B by GSTIN, B2CL, B2CS, CDNR/CDNUR, nil, HSN, documents) and GSTR-3B (outward tax, ITC less debit notes, set-off, cash payable) per month; app screen with month picker and CSV/JSON export, labelled "for review by your CA"
- [x] Accounting calls sign out on a 401, like billing
- Decisions to confirm (§9): only credit bills go on a party's account (cash/UPI/card don't); purchase rates are before GST and the total is rounded to the rupee (may differ from the supplier's printed total by paise); free goods can't be on debit notes; GSTR basis — B2CL = inter-state > ₹1,00,000, ITC by supplier invoice date, CN against B2CS netted, HSN summary uses the stock unit (not UQC), a bill cancelled after its month isn't adjusted — **have a CA review the GSTR output**
- [x] Stock valuation report (Reports → Valuation): stock per batch at purchase rate (cost) and MRP, by category; expired and near-expiry shown apart; as of today or any past date, worked out from the local stock ledger (works offline)
- [x] Profit calculation (Reports → Profit): `GET /reports/profit?from&to` (final bills only, ≤366 days) — revenue = taxable value after discount, cost = qty × batch purchase rate (excl. GST, current rate); profit and margin by day, product, category; sales with no purchase rate flagged, never counted as 100% margin
- [x] Expiry loss tracking (Reports → Expiry): value expiring in 30/60/90 days; expired-unsold value per expiry month (written off vs still on the shelf); "Write off" records an `expiry_writeoff` movement through the repository + outbox so it syncs and leaves valuation. PDF (₹ font) + CSV export per tab
  - To confirm: purchase rate is excl. GST (the manual field may need an "(excl. GST)" hint); profit uses the batch's current purchase rate and ignores free-quantity schemes; expiry loss grouped by expiry month
- [ ] Follow-up: profit report doesn't yet subtract sale returns (credit notes)

### P5 — Pack sizes ✅ Done (8 Oct 2026)

- [x] `pack_size` is a real per-medicine field: "Tablets per strip" / "Capsules per strip" / "ML per bottle" on Add/Edit (shown for piece units), prefilled from the master catalog's pack label ("strip of 10 tablets"), the AI invoice's pack text (the shop's own pack size wins for a known medicine) and the import wizard's pack column; synced like any product field
- [x] Add/Edit with a pack size: stock as **Strips + Loose tablets** ("= 63 tablets in stock"), purchase price and MRP **per strip**; stored per tablet. Clearing the pack size (or choosing a whole-pack unit) switches back to a plain quantity, converting what was typed
- [x] New bill: search results show "23 Tablets (2 strips + 3 tablets) · MRP ₹3.00 (₹30.00/strip)"; quantity dialog takes strips + loose; "− 1 strip / + 1 strip" buttons; the line reads "= 2 strips + 3 tablets"
- [x] Bill detail, A4 invoice and 80 mm receipt print the strips + loose breakdown under the item; the server copies `pack_size` onto `bill_items` (migration edited in place — fresh DB, as per §9)
- [x] Product detail and batch detail show the breakdown; tests: `pack_size_test`, Add/Edit widget tests (enter, edit, clear, catalog), cart, draft, repository, PDF, backend billing
- [x] Per-pack pricing (8 Oct): batch MRP and purchase rate are per strip when the pack size applies (see §3 "Prices are per price pack"); `GstMath.line` / `GstMath::line` and `purchaseLine` take `packSize` and round once per line; valuation, expiry loss, profit, sale returns (`sale_return_items.pack_size`), purchases from invoices (`lines.*.product.pack_size` now validated and saved) and the catalog price all follow. Shared vectors added to `gst_math_test.dart` / `GstMathTest.php`
- [x] Unit change with stock (9 Oct): changing a medicine between a whole-pack unit (Strips, Bottles…) and pieces (Tablets, Capsules, ML) asks first ("It has 16 strips in stock across 2 batches. At 15 tablets a strip, that becomes 240 tablets. Prices stay per strip.") and converts every batch with synced 'adjust' movements; Tablets → Strips is refused while any batch has loose tablets, and needs the pack size

### Journey follow-ups ✅ (9 Oct 2026)

- [x] **Purchases typed by hand**: Purchases → "Add supplier bill" → *Type the bill* (or *Scan a photo or PDF*). The typed bill uses the scan's review screen from an empty bill: "Add item" per medicine (packs, free, pack size, rate and MRP per pack, batch, expiry), matched to the shop's medicines by name; supplier, invoice no./date, duplicate-invoice check and "Record purchase" as for a scan
- [x] **Reports reachable**: Profile → Accounts → Reports, and the Home "Stock value" card; open during the trial
- [x] Home summary cards took no taps on their top 40px (overlap with the header was a separate list item)
- [x] Plan re-checked while the app stays open (resume + hourly; lock at the trial-end moment); Reports overview counts medicines, not batches; bill dialogs no longer crash on close
- [x] Journey follow-ups, round 2 (9 Oct): a strip medicine goes on a bill a strip at a time (or what's left); "Low-stock at (strips)" in strips mode; expiry typed as MM/YY (month's last day, "Pick a day" for full dates) and the app locale en-IN (day/month/year); passwords 8 characters in the app as on the server; switching plan re-applies the coupon
- [x] Hindi removed (owner's decision, 9 Oct): the app is English only; the unused l10n files (17 strings) and the language setting are gone
- Still open: GST % / HSN not editable on a typed purchase line (the medicine's or the shop's default rate applies)

### Remaining from original task list

- [ ] Verify notification reliability under battery optimization (real OEM device test)
- [x] ~~Supplier management UI~~ — replaced by P4 parties (customers + suppliers)
- [x] ~~Bulk CSV import of medicines~~ → replaced by the P2 import wizard
- [x] Accessibility audit: 48dp touch targets (`TapTarget` in ui_kit), screen-reader names and statuses in words, muted text raised to AA (`#5B726F`), no overflow at 1.3x/1.5x text; enforced by `test/widget/accessibility_test.dart` (a new undersized or unlabelled button fails it)
- [x] Accessibility coverage for screens added since the audit (billing, invoice scan + review, all import wizard steps, signed-in Profile): 48dp targets, labels, contrast, no overflow at 1.3x/1.5x, spoken statuses and amounts
- [~] Contrast in brand colours: orange primary buttons now use ink text app-wide (5.0:1; orange unchanged). Status pills (2.2–3.4:1) and the Subscribe plan toggle (4.0:1) still need a design decision
- [x] Contrast guideline on small muted text: 12–13 px `AppColors.muted` at weight 400/500 fails `textContrastGuideline` (it samples rendered pixels; the thin strokes never reach the full colour, so it reads ~1.35:1 against the canvas). Fixed by using w600 for the version line, the import file name and header-row hint, and the theme's `helperStyle`. Rule: muted text under 14 px is w600 or heavier
- [x] Widget tests (Add/Edit 14, Home/Inventory 8) + smoke test add → list → expiry alerts scheduled (`test/integration/smoke_add_to_alert_test.dart`, no server needed)
- [x] Fix: clearing a batch's manufacture date on Edit now saves (and syncs)
- [x] Final README update
- [x] Android release signing reads `android/key.properties` (falls back to the debug key when absent)
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
| Default GST rate | 5% (`default_gst_rate_bp` = 500) for products with no rate — decided by the owner. Per medicine: 0% for exempt drugs (life-saving list, blood, contraceptives); the picker offers 0/5/12/18/28%. Editable per shop |
| Invoice number | `PREFIX/YY-YY/NNNNNN`, prefix ≤3 chars (default `INV`), gap-free per shop per FY |
| Phone navigation | Home · Inventory · + · Bills · Alerts; Profile from the Home avatar — **confirm** |
| Party balance sign | + = party owes the shop (to collect), − = shop owes the party (to pay) — **confirm** |
| Purchases add stock on the server | A purchase entry creates the batches/movements server-side; devices pull them (never counted twice) |
| Bill refusal | Any edit to a batch since the device loaded it refuses the bill (409), even if the price is unchanged |
| Schema changes | Wipe DB + re-upload (no upgrade migrations while there are no real users) |
| Master catalog | Shop's new medicines auto-added without moderation (max 200/shop/day) |
| AI invoice | Server-side processing, not on-device |
| Pricing | Plan prices not finalized yet |
| Pack size | Per medicine (`products.pack_size`), never assumed; stock stays in pieces; strips + loose is an entry/display convenience. Only applies to Tablets / Capsules / ML |
| Prices per price pack | Batch MRP / purchase rate are per strip when the pack size applies, else per unit; line amounts = price × qty / pack, rounded once (both sides). Invoices print MRP and rate per strip with the quantity in tablets |
| Unit change with stock | Ask, then convert every batch ×/÷ pack size (owner's decision, 9 Oct); refused when not whole strips. Prices are per strip either way, so they stay |
| Desktop layout | Decided by width (`AdaptiveLayout.isDesktop`, ≥ 900 px), not by OS; the Windows window has a 900×620 minimum so it always gets the rail |

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
- [ ] Set `ANTHROPIC_API_KEY`; keep `QUEUE_CONNECTION=database`
- [ ] Run the queue worker under supervisor: `php artisan queue:work database --sleep=3 --tries=3 --timeout=330 --max-time=3600` (`autorestart=true`, `stopwaitsecs=360`); `php artisan queue:restart` after each deploy
- [ ] Raise upload limits to ~12 MB: PHP `upload_max_filesize` + `post_max_size` (currently 2 MB) and nginx `client_max_body_size`
- [ ] Cron: `* * * * * php artisan schedule:run` (daily cleanup of old invoice scans)
- [ ] Android: create an upload keystore and `app/android/key.properties` (`storePassword`, `keyPassword`, `keyAlias`, `storeFile` relative to `android/app`); without it release builds are signed with the debug key
- [ ] Build and test Windows installer (run `app/tool/build_windows_installer.ps1`; Visual Studio needs "Desktop development with C++" **and** the "C++ ATL for latest build tools" component, for flutter_secure_storage; Inno Setup 7 or 6 is also required)
  - `permission_handler` was removed (its Windows plugin passes `/await`, which Visual Studio 2026 rejects): `mobile_scanner` and `image_picker` ask for camera permission themselves, and `app_settings` opens the app's settings page. After pulling, run `flutter clean` before `flutter build windows`
- [ ] Cross-device testing: Windows ↔ phone sync, price conflicts, offline edits, USB barcode scanner

---

## 11. Commit history

Newest first. Run `git log --oneline` for the live state.

| SHA | Description |
|-----|-------------|
| `0b37e34` | App: accounting calls sign out on a 401, like billing |
| `e8b09b7` | App tests: accounting logic, accounts screens, scan-to-purchase, a11y |
| `3d183ef` | App: accounts - parties, ledgers, payments, purchases, returns, GST reports |
| `4d579bd` | Backend: P4 accounting - parties, purchases, payments, returns, ledgers, GSTR-1/3B |
| `48770bf` | App: visible loading spinner on Log in and Send reset code |
| `4ff9f15` | App: tie local data to the account id, ask before dropping unsynced changes |
| `94bb058` | App: Reports - stock valuation, profit and expiry loss tabs |
| `5af1b98` | App: invoice scan saves HSN and GST rate per line |
| `50c2d57` | Backend: profit report endpoint (GET /reports/profit) |
| `dd734bf` | Docs: sync 401, a11y coverage |
| `e16b12c` | App: accessibility coverage for billing, invoice scan, import wizard |
| `145e2a0` | App: a 401 from sync, billing or invoice reading signs out |
| `5d8836b` | Docs: P3 GST billing done |
| `8ad5fe8` | App: New bill button contrast; tests follow billing + secure token |
| `d53c7f0` | App: GST billing — counter sale, invoices (A4 + 80 mm), bills list |
| `fc395d5` | Backend: GST billing — bills API, invoice series, Filament Bills |
| `ea61dfa` | Docs: import wizard done (P2 complete) |
| `893fddf` | App: Excel/CSV stock import wizard |
| `910f0d6` | Android release signing from key.properties; docs |
| `ad51dd5` | README: final update |
| `70eadeb` | App a11y: 48dp touch targets, screen-reader names, AA muted text, large text |
| `e289628` | App a11y: password toggles and settings switches named; auth links wrap |
| `17774cd` | App tests: widget tests Add/Edit, Home, Inventory + add-to-alert smoke test |
| `6dcc51b` | App: clearing a batch's manufacture date now saves |
| `af5ddf3` | Docs: AI invoice reading |
| `fb518f9` | AI invoice reading: server-side Claude extraction + app review screen |
| `d3bfa60` | Docs: security fixes, deploy notes |
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
