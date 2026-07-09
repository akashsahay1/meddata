# Alok ji's changes — Custom subscriptions (Razorpay + trial + coupons)

Replaces Google Play Billing with an **admin-managed** subscription system.

## Requirements (confirmed)
1. **No Google Play Store plans** — remove `in_app_purchase` / Play Billing.
2. **7-day free trial** from first app launch. After it ends with no active subscription → **full app lock** (non-dismissible paywall).
3. **Plans come from the admin panel** (already served via `/api/v1/config`).
4. **Coupon codes** — admin generates codes; user enters a code in the app and it applies a discount. Coupon type is **percentage OR flat amount** (chosen from a dropdown in admin).
5. **Payment gateway = Razorpay**, managed from the backend admin panel.

## Entitlement model (app is "premium" if ANY of these)
- Within the **7-day trial** (device first-seen + 7 days), OR
- Has an **active paid subscription** (Razorpay payment verified, not expired / lifetime).

Otherwise → **locked** (full-screen subscribe paywall, cannot use the app).

## Data model additions (backend)
- **coupons**: `id`, `code` (unique), `type` (`percentage`|`flat`), `value` (decimal), `max_uses` (nullable), `used_count`, `min_amount` (nullable), `plan_id` (nullable — restrict to a plan), `valid_from` (nullable), `valid_until` (nullable), `is_active`, timestamps, soft deletes.
- **entitlements** (extend): `trial_started_at`, `trial_ends_at`, `source` (`trial`|`razorpay`|`manual`|`coupon`), `razorpay_payment_id`, `razorpay_order_id`, `coupon_id` (nullable). Keep `status`, `is_premium`, `expiry_time`, `product_id`, `plan_id`.
- **payments** (log): `id`, `device_id`, `plan_id`, `coupon_id` (nullable), `amount`, `currency`, `razorpay_order_id`, `razorpay_payment_id`, `status` (`created`|`paid`|`failed`), timestamps.
- **app_settings**: `razorpay_key_id`, `razorpay_key_secret`, `trial_days` (default 7).

## API contract (`/api/v1`)
- `GET  /config` — (existing) adds `trial_days`, `razorpay_key_id` (public key only).
- `POST /device/trial` — `{device_id}` → registers/returns trial: `{trial_ends_at, days_left, is_trial_active}`. Idempotent (first call sets trial_start).
- `GET  /entitlement?device_id=` — (existing, extended) returns `{premium, status, source, trial_ends_at, days_left, expiry_time}`. `premium=true` if trial active OR paid active.
- `POST /coupon/validate` — `{code, plan_id}` → `{valid, type, value, discount, final_amount, message}`.
- `POST /order/create` — `{device_id, plan_id, coupon_code?}` → creates Razorpay order → `{order_id, amount, currency, key_id}`. Applies coupon to compute amount.
- `POST /payment/verify` — `{device_id, razorpay_order_id, razorpay_payment_id, razorpay_signature, plan_id, coupon_code?}` → verifies signature → activates entitlement → `{premium, status, expiry_time}`.

All endpoints degrade gracefully; app keeps cached entitlement offline. Razorpay uses a **dev fallback** (no real charge) until real keys are set — mirrors `GooglePlayVerifier`.

## App flow
1. First launch → `POST /device/trial` (and store trial_start locally as backup). Show "X days left in trial" banner.
2. Entitlement = trial-active OR paid. If neither → **LockScreen** (full-screen, blocks app).
3. Subscribe screen: plans from `/config`; enter coupon → `/coupon/validate` → show discounted price; **Subscribe** → `/order/create` → open **Razorpay checkout** (`razorpay_flutter`) → on success → `/payment/verify` → unlock.

## Razorpay setup (go-live)
- Create a Razorpay account → get **Key ID** + **Key Secret** (test keys are free).
- Put them in `backend/.env`: `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET` (or edit in admin App Settings).
- Test mode works end-to-end with Razorpay test cards; no real money.

## Admin panel additions
- **Coupons** resource — CRUD + a **"Generate codes"** action (bulk random codes with a type/value).
- **Payments** resource — read-only log of orders/payments with filters.
- **App Settings** — Razorpay keys + trial_days editable.
