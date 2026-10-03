# Sleeping Routine for Zy — Flutter lite (Spotify timer)

Slim Flutter build: **account + sync + Spotify + sleep timer**.  
When the timer ends, Spotify playback is paused. No wake alarms, quiet sounds, Remote Admin UI, bedtime reminders, or sleep history.

## What it does

1. Sign in / register
2. Connect Spotify and pick music (search tracks/albums, Liked Songs, Recently Played, or a playlist)
3. Set a timer and start — Spotify plays
4. When time is up (or you stop early) — Spotify pauses
5. Offline-first sync for preferences + active timer across devices

## Prerequisites (Windows)

1. Flutter SDK
2. Chrome (for web)
3. Optional: Android Studio + emulator

```powershell
$env:Path = "e:\Develop\tools\flutter\bin;" + $env:Path
flutter doctor
```

## Run (Web)

```powershell
cd e:\Develop\App\Zy\SRZ\flutter_app
flutter pub get
flutter run -d web-server --web-hostname=127.0.0.1 --web-port=7357
```

Open http://127.0.0.1:7357 in Chrome.

## Spotify redirect URIs

| Client | Redirect URI |
|--------|----------------|
| iOS / Android (production) | `https://sleeping-routine-for-zy.pages.dev/callback` |
| Flutter web (local) | `http://127.0.0.1:7357/callback` |

```powershell
flutter run -d web-server --web-hostname=127.0.0.1 --web-port=7357 --dart-define=SPOTIFY_CLIENT_ID=your_id
```

## Backend (account + sync)

```powershell
cd e:\Develop\App\Zy\SRZ\backend
python -m uvicorn main:app --host 127.0.0.1 --port 8081
```

```powershell
flutter run -d chrome --dart-define=BACKEND_BASE_URL=http://127.0.0.1:8081 --dart-define=SPOTIFY_CLIENT_ID=your_id
```

Use **Settings → Sync & install** to sync now or join another device via pairing code.

## Feature set (lite)

| Area | Status |
|------|--------|
| Account (register / sign-in) | Yes |
| Onboarding (Spotify + timer default) | Yes |
| Home timer → Spotify play / pause | Yes |
| Spotify PKCE + Web API | Yes |
| Sync & multi-device pairing | Yes |
| Wake alarms | Removed |
| Quiet sounds | Removed |
| Remote Admin UI | Removed |
| Bedtime / history / streak | Removed |

## Notes

- Spotify Premium + an active Connect device are required for remote play/pause.
- Keep the app/tab available so the timer can pause Spotify when it ends.
- OAuth scopes include library read + recently played. If Liked Songs / Recently Played fail after an update, **Disconnect and Connect Spotify again** once so the new scopes are granted.
- Native Swift iOS app under `SleepingRoutineForZy/` is unchanged on `main`.
- Backend admin/alarm APIs may still exist server-side; this client does not use them.
