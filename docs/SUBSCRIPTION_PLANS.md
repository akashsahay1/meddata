# Subscription Plans — Medicine Stock & Expiry Tracker (v2)

Monetization model: **freemium**. Free tier is genuinely useful (up to 7 medicines) so small shops can try it; paid tiers unlock unlimited medicines and premium tools. All purchases go through **Google Play Billing** (`in_app_purchase`) and are **verified server-side** (see backend in `PROJECT_PLAN.md` / `BUILD_PROMPT.md`).

## 1. Tiers

| Tier | Product ID | Price (₹, suggested) | Billing | Best for |
|---|---|---|---|---|
| **Free** | — | ₹0 | — | Trying the app / very small shops |
| **Premium Monthly** | `premium_monthly` | **₹99 / month** | Auto-renewing | Short-term / seasonal |
| **Premium Yearly** ⭐ *Best Value* | `premium_yearly` | **₹999 / year** (~₹83/mo) | Auto-renewing | Most shop owners |
| **Lifetime** *(optional)* | `premium_lifetime` | **₹2,499 one-time** | One-time (non-consumable) | Owners who dislike subscriptions |

> Prices are suggestions aligned to the existing ₹999/year in the current app. Confirm final pricing with the owner and set localized prices in Play Console. Consider a **7-day free trial** or **intro offer** on the yearly plan to boost conversion. Yearly should always read as the "Best Value" default-highlighted option (in monochrome: bold border + "BEST VALUE" text tag, not color).

## 2. Feature matrix

| Feature | Free | Premium (Monthly / Yearly / Lifetime) |
|---|---|---|
| Medicines tracked | **Up to 7** | **Unlimited** |
| Add / edit / delete medicines | ✓ | ✓ |
| Basic expiry & low-stock alerts | ✓ | ✓ |
| Search / filter / sort | ✓ | ✓ |
| Local backup & restore (export/import) | ✓ | ✓ |
| Configurable/advanced expiry alerts (30/15/7, per-item) | Basic only | ✓ |
| Reports & analytics (stock value, trends, losses) | — | ✓ |
| Export to CSV / PDF | — | ✓ |
| Barcode scan add/lookup | Limited | ✓ |
| Cloud backup & multi-device restore | — | ✓ |
| Suppliers & stock-movement history | Basic | ✓ |
| Priority support | — | ✓ |
| Ads | Optional single banner or none | None |

*(Keep Free ad-free if possible to preserve the clean B&W feel; if ads are used, a single non-intrusive monochrome banner only.)*

## 3. Free-tier enforcement

- Count **non-deleted** medicines. On attempt to add the **8th**, block and route to the Upgrade screen with message: *"Free plan holds 7 medicines. Upgrade to add unlimited."*
- Show a persistent Home counter: **"X / 7 medicines"** with an "Upgrade" link.
- Premium features (reports, cloud backup, export, advanced alerts) show a lock affordance (outline lock icon + "Premium") and open Upgrade when tapped.
- **Entitlement source of truth:** server-verified entitlement, cached locally (`shared_preferences`) so the app respects paid status **offline**. Re-check on app resume when online.

## 4. Purchase & validation flow

1. User taps a plan → `in_app_purchase` launches Play purchase sheet.
2. On success, client sends the **purchase token** to the backend verify endpoint.
3. Backend verifies against **Google Play Developer API**, stores/updates `entitlements`, returns status.
4. Client caches entitlement, unlocks premium.
5. **RTDN webhook** keeps entitlement current on renew / cancel / grace-period / expire.
6. **Restore purchases** button re-queries Play + backend to re-unlock on a new device/reinstall.
7. **Manage subscription** deep-links to the Play subscriptions page.

## 5. Edge cases to handle

- Offline at purchase time → complete when online; never lose a paid unlock.
- Grace period / account hold → keep premium during grace, then downgrade to Free (data preserved; if >7 medicines exist, keep them visible **read-only**, block new adds until re-subscribed or count ≤7).
- Refund / chargeback via RTDN → revoke entitlement.
- Lifetime purchase → non-consumable, always active; skip renewal logic.
- Multiple devices → tie entitlement to account (if signed in) or restore via Play account.

## 6. Play Console setup checklist

- [ ] Create app + monochrome store assets.
- [ ] Create subscription base plans/offers: `premium_monthly`, `premium_yearly` (+ optional intro/trial).
- [ ] Create one-time product `premium_lifetime` (optional).
- [ ] Set localized prices (₹ for India; add others as needed).
- [ ] Create a **service account** with access to the Google Play Developer API for server verification.
- [ ] Configure **RTDN** (Pub/Sub topic) for subscription notifications.
- [ ] Fill Data Safety form (local storage; optional cloud backup) + privacy policy URL.

## 7. Redesign note for the existing Subscription screen

The current screen (see screenshot) is green-themed. Rebuild it **pure black & white**:
- Free plan card: bordered, "1 / 7 Medicines", progress shown as a **monochrome bar** (black fill on gray track) + "6 more medicines available".
- Premium features list with **outline icons only** (no color).
- Plan cards stacked: Yearly (bold border + "BEST VALUE" tag), Monthly, Lifetime — price in bold, period in gray.
- Primary CTA: solid black button, white text ("Upgrade" / "Subscribe"). Secondary: "Restore purchases".
