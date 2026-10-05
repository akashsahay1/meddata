# Meddata

Multi-device pharmacy inventory app — phones (Android/iOS) + Windows desktop. Offline-first, server-synced inventory, Razorpay subscriptions.

## Repository layout

```
meddata/
├── app/          Flutter app (Android, iOS, Windows desktop)
├── backend/      Laravel 12 + Filament admin (REST API)
├── docs/         Project documentation
│   └── MEDDATA.md   ← single source of truth (architecture, tasks, API, how to run)
└── README.md     This file
```

## Quick start

```bash
# App
cd app && flutter pub get && flutter run

# Backend
cd backend && composer install && php artisan migrate:fresh --seed && php artisan serve
```

Full setup instructions, API docs, task list, and architecture details → **[docs/MEDDATA.md](docs/MEDDATA.md)**

## Resuming in a new session

Open `docs/MEDDATA.md` §8 (Task list), find the first unchecked `[ ]`, and continue.
