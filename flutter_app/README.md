# Sleeping Routine for Zy — Flutter (Android + Web)

Parallel to the native **Swift iOS** app under `SleepingRoutineForZy/`.  
This Flutter port lets you test on **Windows** via Chrome and/or an Android emulator.  
It does **not** replace the iOS project and cannot build a real iPhone app without a Mac.

## Prerequisites (Windows)

1. Flutter SDK (this repo may use `e:\Develop\tools\flutter`)
2. Chrome (for web)
3. Optional: Android Studio + emulator (for Android)

Add Flutter to PATH for your session:

```powershell
$env:Path = "e:\Develop\tools\flutter\bin;" + $env:Path
flutter doctor
```

## Run (Web — easiest on PC)

```powershell
cd e:\Develop\App\Zy\SRZ\flutter_app
flutter pub get
flutter run -d web-server --web-hostname=127.0.0.1 --web-port=7357
```

Then open http://127.0.0.1:7357 in Chrome.

## Run (Android emulator / device)

```powershell
flutter emulators
flutter emulators --launch <id>
flutter run -d android
```

On first run, grant **notifications** and **exact alarms** when prompted (Onboarding → Allow alarms, or Alarms tab).

## Spotify redirect URIs

Register **all** of these in the [Spotify Developer Dashboard](https://developer.spotify.com/dashboard) → your app → Redirect URIs:

| Client | Redirect URI |
|--------|----------------|
| iOS / Android | `sleepingroutineforzy://spotify-callback` |
| Flutter web (local) | `http://127.0.0.1:7357/callback` |
| Flutter web (Cloudflare Pages) | `https://700ff232.sleeping-routine-for-zy.pages.dev/callback` |
| Flutter web (Pages production alias) | `https://sleeping-routine-for-zy.pages.dev/callback` |

Register **all** hosts you use. On web the app uses `{current origin}/callback` unless you override with `--dart-define=SPOTIFY_REDIRECT_URI=...`.

Android uses the custom scheme by default (deep link into the app via `app_links`).  
Web uses same-tab redirect to `/callback`. Override with:

```powershell
flutter run -d android --dart-define=SPOTIFY_CLIENT_ID=your_id
flutter run -d web-server --web-hostname=127.0.0.1 --web-port=7357 --dart-define=SPOTIFY_CLIENT_ID=your_id
```

Open **http://127.0.0.1:7357** (not `localhost`) for local demos. The app auto-redirects `localhost` → `127.0.0.1` so Spotify PKCE storage matches the registered redirect URI.

## Admin backend + sync

```powershell
cd e:\Develop\App\Zy\SRZ\backend
python -m uvicorn main:app --host 127.0.0.1 --port 8081
```

Pass the same origin to Flutter:

```powershell
flutter run -d chrome --dart-define=BACKEND_BASE_URL=http://127.0.0.1:8081
```

Offline-first sync (preferences, alarms, sessions, active routine) runs automatically when online. Use **Settings → Sync & install** to sync now, join another device via pairing code, or see Add to Home Screen tips.

## Hosted PWA build

Clean → build → deploy (Windows):

```powershell
cd e:\Develop\App\Zy\SRZ
.\scripts\clean_build_deploy.ps1
```

Set `BACKEND_BASE_URL` (and optionally `SPOTIFY_CLIENT_ID`) via env or script params. Cloudflare project defaults to `sleeping-routine-for-zy` or `CLOUDFLARE_PAGES_PROJECT`.

```powershell
# Build only
$env:BACKEND_BASE_URL = "https://your-api.example.com"
.\scripts\clean_build_deploy.ps1 -SkipDeploy
# Custom API / branch
.\scripts\clean_build_deploy.ps1 -BackendBaseUrl "https://..." -Branch production
```

Or the older build helper:

```powershell
.\scripts\build_web.ps1 -BackendBaseUrl "https://your-api.example.com"
# Optional: -Deploy
```

Spotify Redirect URI on Pages is `{origin}/callback` (register `https://sleeping-routine-for-zy.pages.dev/callback`).
## Feature parity (v0.9)

| Area | Status |
|------|--------|
| Onboarding | Yes (includes alarm permission) |
| Home (timer presets + streak + bedtime) | Yes — 3 tabs: Home / Alarms / Settings |
| Bedtime reminder | Yes (daily local notification) |
| Quiet sounds | Soft tone / Rain / White noise / Deep hum |
| Timer fade-out (last 5 min, app audio) | Yes |
| Sleep history / streak | Yes (local) |
| Alarms (Android exact notifications) | Yes |
| Alarms (web best-effort while tab open) | Yes — honest limitation copy |
| Spotify PKCE + Web API | Yes (Android deep link + web redirect) |
| Remote Admin opt-in + pairing | Yes (includes bedtime + streak) |
| Privacy screen | Yes |
| Secure credential store (Phase 8) | Yes — Keystore/Keychain on mobile; web origin-trust documented |

## Relationship to Swift

Keep developing `SleepingRoutineForZy/` for production iPhone (AlarmKit on iOS 26+).  
Use `flutter_app/` for Windows-friendly Android/Web demos and iteration.
