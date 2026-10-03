# How to Run — Medicine Stock & Expiry Tracker

Two parts, in separate folders: the **Flutter app** (`app/`) and the **Laravel backend** (`backend/`).

## Prerequisites (already set up on this machine)

- Flutter 3.44.4 stable at `~/development/flutter` → add to PATH:
  `export PATH="$HOME/development/flutter/bin:$PATH"`
- Android SDK at `~/Library/Android/sdk`, JDK from Android Studio.
- Laravel Herd (PHP 8.4 + Composer) → `export PATH="$HOME/Library/Application Support/Herd/bin:$PATH"`
- MariaDB running via Herd; database `med_stock` (root / your local DB password).

## Flutter app

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
cd /Users/akash/Desktop/meddata/app
flutter pub get
flutter gen-l10n            # generate localization (EN/HI)
flutter run                 # on a connected device / emulator
# Release build (small, split ABIs for old phones):
flutter build apk --release --split-per-abi
# or an app bundle for Play:
flutter build appbundle --release
```

- **Min Android:** the build currently ships **minSdk 24 (Android 7.0 Nougat, ~95% of active devices)** — Flutter 3.44's default, which the toolchain re-applies on every build. Flutter's hard floor is **23 (Android 6.0)**; to pin 23, set `val minSdkVersion: Int = 23` in `~/development/flutter/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt` (a local-SDK change), since editing only `android/app/build.gradle.kts` gets normalized back to `flutter.minSdkVersion`. Both 23 and 24 are far below "latest-only" and support old phones. Ships `armeabi-v7a` (32-bit) + `arm64-v8a` + `x86_64`.
- **Backend URL:** set at build time if not using the Herd default:
  `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1`
  (Android emulator reaches the host machine at `10.0.2.2`.)

## Laravel backend

```bash
export PATH="$HOME/Library/Application Support/Herd/bin:$PATH"
cd /Users/akash/Desktop/meddata/backend
php artisan migrate --seed --force     # schema + admin + plans + settings (+ demo data)
php artisan serve --port=8000 --host=0.0.0.0         # or serve via Herd domain
```

- **Admin panel:** `/admin` → login **akash.sahay1@gmail.com** / the `ADMIN_PASSWORD` you set in `.env`
- **API base:** `/api/v1` (`config`, `register-device`, `entitlement`, `purchase/verify`, `rtdn`, `backup`).
- The app works fully **offline**; the backend is only for subscription validation + optional cloud backup.

## Tests

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
cd /Users/akash/Desktop/meddata/app
flutter test        # domain unit tests (expiry, low-stock, free-tier gating)
```

## Go-live follow-ups (need real credentials — see docs/TASKS.md Phase 6)

- Create the app + subscription products in Google Play Console (`premium_monthly`, `premium_yearly`, `premium_lifetime`).
- Create a Play Developer API service account; set `GOOGLE_PLAY_CREDENTIALS` in `backend/.env` to enable real server-side purchase verification (a safe local-dev fallback is used until then).
- Configure RTDN (Pub/Sub) to `POST /api/v1/rtdn`.
- Add a real release keystore and replace the debug signing config.
