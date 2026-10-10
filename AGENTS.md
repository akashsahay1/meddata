# Meddata — notes for coding agents

Handover written 10 Oct 2026 (Claude Code → Codex CLI). Read this, then
`docs/MEDDATA.md` (the full project document: architecture, data model, API,
task list in §8, locked decisions in §9, deploy checklist in §10).

## What this is

Offline-first pharmacy inventory + GST billing for small Indian medical shops.
`app/` is Flutter (Android + Windows desktop; iOS/macOS build but are not
targets), `backend/` is Laravel 13 + Filament 5. All devices of a shop sync
through the server. Built privately for one owner (a family contact): shipped
as a directly installed APK and a Windows installer, **not** the Play Store —
so Play listing, upload keystore and app bundles are out of scope; build
`flutter build apk --release`.

## State on 10 Oct 2026

`main` at `a3c782f`, **20 commits ahead of `origin/main` (not pushed)**. Working
tree clean. Tests: app 432 pass + 1 skipped (`test/integration/
sync_two_devices_test.dart`, needs a live server); backend 148 pass.

Done recently (see §8 "P5 — Pack sizes" and "Journey follow-ups" in
`docs/MEDDATA.md`):

- **Pack sizes**: `products.pack_size` per medicine; stock always in pieces;
  strips + loose entry/display. **Prices are per strip** when the pack size
  applies (`PackSize.pricePack`); every amount is `round(price × qty / pack)`
  once per line, same maths in `app/lib/domain/gst.dart` and
  `backend/app/Support/GstMath.php` (shared test vectors — keep them in step).
- Unit change on a medicine with stock asks, then converts every batch.
- Typed supplier bills (Purchases → Add supplier bill → Type the bill); AI scan
  still there.
- Reports reachable (Profile → Accounts → Reports, Home "Stock value" card),
  open during the trial.
- Plan re-checked while the app stays open (resume + hourly; lock at trial end).
- Bill: a strip medicine is added a strip at a time; low-stock in strips;
  expiry typed MM/YY (`widgets/expiry_picker.dart`), locale en-IN.
- Passwords 8 chars (app = server); coupon re-applied on plan change.
- Hindi **removed** on purpose (owner's decision) — English only.

## Open work (most useful first)

1. Profit report doesn't subtract sale returns (credit notes).
2. Owner decisions still listed in `docs/MEDDATA.md` §8/§9 ("confirm"), and a
   CA should review GSTR-1/3B output.
3. Real-device checks: Android phone sync, notifications under battery
   optimisation, Windows installer (`app/tool/build_windows_installer.ps1`,
   needs Inno Setup), USB barcode scanner.
4. Deploy checklist `docs/MEDDATA.md` §10 (fresh migrate, `APP_ENV=production`,
   live Razorpay keys, queue worker, upload limits, rotate old passwords).

## How to run

```bash
cd backend && php artisan test                   # all backend tests
cd app && flutter analyze && flutter test        # all app tests
cd app && flutter run -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1
```
Windows builds need Visual Studio 2026 with "Desktop development with C++" and
the C++ ATL component; run `flutter clean` once after pulling plugin changes.

## Working rules (from the owner)

- **Fix the root cause.** Never add a "temporarily unavailable" message, a
  disabled button or a fallback branch to hide a broken feature.
- Prices and money are integer paise. Never introduce a per-tablet price when
  the medicine is priced per strip.
- Every behaviour change gets a test that fails on the old code; keep the full
  suites green; `flutter analyze` must report no issues.
- Commit one fix per commit with a plain-English message saying what was wrong
  and what changed; update `docs/MEDDATA.md` (§8 task list, §9 decisions) when
  behaviour or decisions change. Don't push unless asked.
- Schema changes: edit the create migrations in place (no upgrade migrations
  while there are no real users; deploy does `migrate:fresh`).
- Plain UI copy: short, concrete, no jargon (staff use it at the counter).
- Accessibility test (`app/test/widget/accessibility_test.dart`) enforces 48dp
  targets, labels and contrast; small muted text must be w600.

## Gotchas we hit

- The machine has 8 GB RAM: a Windows Flutter build + PHP server + browser can
  run out of memory. Close the browser before long Windows runs.
- `php artisan serve` handles one request at a time (and can't fork workers on
  Windows); the app's first sync pull can make other calls time out in dev.
- Flutter tests: `find.text` doesn't see text inside TextFields (check the
  controller); lazy lists don't build off-screen children (scroll first);
  dialogs stacked on dialogs make `find.text('OK')` ambiguous.
- An end-to-end Windows journey harness and its report live in the worktree
  `.claude/worktrees/agent-a766879892c4ace96` (branch
  `worktree-agent-a766879892c4ace96`, `app/integration_test/` and
  `docs/reports/`). It is not merged into `main`; the report summarises what a
  real shop owner hits over 3–4 months.
