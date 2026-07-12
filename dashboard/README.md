# dashboard

Flutter client for the Apple Quality Classification & IoT Active Learning System. See the [repository root README](../README.md) for the full system architecture.

## Setup

```powershell
flutter pub get
```

## Supabase credentials

The app reads its Supabase URL and anon key from `--dart-define` at build/run time — they are **not** committed to source control. Set them in your shell before running:

```powershell
$env:SUPABASE_URL = "https://<your-project>.supabase.co"
$env:SUPABASE_ANON_KEY = "<your-anon-key>"

flutter run -d chrome `
    --dart-define=SUPABASE_URL=$env:SUPABASE_URL `
    --dart-define=SUPABASE_ANON_KEY=$env:SUPABASE_ANON_KEY
```

`start_all.ps1` (in the repo root) does this automatically once `SUPABASE_URL`/`SUPABASE_ANON_KEY` are set in the session.

To develop against the UI without touching the real database, run the mock entry point instead (no credentials required):

```powershell
flutter run -d chrome -t lib/main_mock.dart
```

## Authentication

Accounts live in the Supabase `workers` table (bcrypt password hashes, `admin`/`operator` roles) — there is no self-service sign-up. See [`AUTENTICACAO.md`](AUTENTICACAO.md) for how to provision a user with `bin/generate_password_hash.dart`.
