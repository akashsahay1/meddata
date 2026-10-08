# Meddata

Offline-first stock and expiry tracker for Indian pharmacies and medical shops. One account per shop; every device (Android phones, Windows PCs) shares the shop's inventory through the server. Medicines are tracked by batch (stock, MRP, expiry), with low-stock and expiry alerts, reports, barcode lookup, a 7-day trial and Razorpay subscriptions.

**[docs/MEDDATA.md](docs/MEDDATA.md) is the source of truth**: architecture, data model, sync protocol, API, task list and deploy checklist.

## Repository layout

```
meddata/
├── app/        Flutter app: Android, iOS, Windows (local SQLite + sync engine)
├── backend/    Laravel 13 + Filament 5: REST API (/api/v1) and admin panel (/admin)
├── docs/
│   └── MEDDATA.md
└── README.md
```

## Prerequisites

- **Flutter 3.44.4** (Dart 3.12), with the Android SDK for phone builds
- **PHP 8.4** (composer.json allows ^8.3) with `pdo_sqlite`, plus `pdo_mysql` for MariaDB/MySQL
- **Composer 2**
- For Windows builds: a Windows PC with Visual Studio 2026 and the *Desktop development with C++* workload

## Quick start

### Backend

```bash
cd backend
composer install
cp .env.example .env              # then set ADMIN_EMAIL / ADMIN_PASSWORD
php artisan key:generate
touch database/database.sqlite    # dev database (DB_CONNECTION=sqlite)
php artisan migrate:fresh --seed  # schema, admin user, plans, settings
php artisan medicines:import path/to/medicines.csv   # optional: master catalog
php artisan serve --host=0.0.0.0 --port=8000
```

Admin panel: <http://localhost:8000/admin>, signing in with `ADMIN_EMAIL` / `ADMIN_PASSWORD`.

### App

```bash
cd app
flutter pub get
flutter run                       # uses the live API by default
# against a local backend from the Android emulator:
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
```

For a phone on USB, run `adb reverse tcp:8000 tcp:8000` and use `API_BASE_URL=http://127.0.0.1:8000/api/v1`.

## Configuration (`backend/.env`)

| Variable | What it is for |
|---|---|
| `DB_CONNECTION` | `sqlite` for development. In production use `mariadb`/`mysql` with `DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD` |
| `ADMIN_EMAIL`, `ADMIN_PASSWORD` | Filament admin created or updated by `db:seed`. If no password is set, the seeder prints a generated one |
| `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET` | Razorpay checkout. Leave empty in development (dev fallback, no real charges) |
| `APP_DEBUG` | Set `false` in production, then run `php artisan config:cache` |
| `ANTHROPIC_API_KEY` | *Upcoming (P2):* server-side AI invoice reading |
| `QUEUE_CONNECTION` | `database`. *Upcoming:* invoice reading runs as queued jobs, so production needs `php artisan queue:work` kept running (e.g. under supervisor) |

The app has one build-time setting: `API_BASE_URL` (`--dart-define`), which defaults to the live server.

## Tests

```bash
cd app && flutter analyze && flutter test   # unit, widget, accessibility and smoke tests
cd backend && php artisan test              # API, sync, payments, admin (in-memory SQLite)
```

- App widget tests run on an in-memory database with a fake backend, so they need no server or device. They cover Add/Edit, Home and Inventory, accessibility (48dp touch targets, screen-reader labels, contrast, 1.3x/1.5x text) and a smoke test from adding a medicine to its scheduled expiry alerts.
- The two-device sync test needs a running backend and is skipped otherwise:

  ```bash
  flutter test test/integration/sync_two_devices_test.dart \
    --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1 --dart-define=SYNC_IT=true
  ```

## Release builds

**Android**

```bash
cd app
flutter build apk --release --split-per-abi   # one APK per ABI, in build/app/outputs/flutter-apk/
flutter build appbundle --release             # for Google Play
```

Release builds are still signed with the debug key (`app/android/app/build.gradle.kts`). Set up a real upload keystore before publishing.

**Windows**

```bash
flutter build windows --release               # output in build\windows\x64\runner\Release\
```

This must be run on Windows with the Visual Studio C++ workload. To produce a per-user installer, install Inno Setup 7 (or 6) and run this from the repository root in PowerShell:

```powershell
./app/tool/build_windows_installer.ps1
```

The installer is written to `app/build/installer/Meddata-Setup-<version>.exe`. Windows builds need Visual Studio 2026 with the Desktop development with C++ workload and the C++ ATL component. Pass `-SkipBuild` to package an existing release build.

## Picking up work

Open [docs/MEDDATA.md](docs/MEDDATA.md) §8 (task list), take the first unchecked item, and check `git log --oneline -5` for the latest changes.
