# Sleeping Routine for Zy

## Overview

**Sleeping Routine for Zy** is a calm, privacy-first iPhone app that helps Zy keep a consistent bedtime routine: sleep timer, music (including Spotify where supported), wake alarms via local notifications, and an optional **remote Admin** status dashboard for a guardian.

This repository currently contains **Phase 7 — Remote Admin**: opt-in HTTPS check-in, Keychain device tokens, local Admin PIN, Privacy screen, and a runnable FastAPI backend + guardian dashboard (in-memory store for local demo; PostgreSQL for production).

## Features

| Feature | Status |
|---------|--------|
| Tab navigation (Home / Sleep / Alarms / Settings) | Phase 1 shell |
| Domain models + routine state machine | Phase 1 |
| SwiftData persistence + repositories | Phase 1 |
| Sleep timer timestamp reconstruction | Phase 1 (logic) |
| Onboarding | Phase 2 complete |
| Home routine UX | Phase 3 complete |
| Sleep timer UI | Phase 3 complete |
| Local notification alarms | Phase 4 complete |
| App-owned audio + AVAudioSession | Phase 5 complete |
| Spotify OAuth PKCE + Web API playback | Phase 6 complete |
| Remote Admin backend + check-in | Phase 7 complete |
| Privacy / security audit | Phase 8 |
| Full device test matrix | Phase 9 |

## Requirements

- macOS with **Xcode 15+** (iOS 17 SDK)
- iOS **17.0+** deployment target
- Apple Developer account for device installs
- (Required for Spotify) Spotify Developer app Client ID
- (Required for Remote Admin) Backend at `BACKEND_BASE_URL` (see `backend/`)

## Xcode Setup

1. Open `SleepingRoutineForZy.xcodeproj` **on a Mac** (this workspace was authored on Windows; `xcodebuild` is not available here).
2. Optionally regenerate the project with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

   ```bash
   brew install xcodegen
   xcodegen generate
   ```

3. Copy secrets template:

   ```bash
   cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
   ```

4. Select the `SleepingRoutineForZy` scheme and an iPhone simulator or device.
5. Set your **Team** under Signing & Capabilities.

## iOS Deployment Target

**iOS 17.0**

## Spotify Setup

Phase 6 uses **Authorization Code with PKCE** (`ASWebAuthenticationSession`) and the **Spotify Web API**. The official Spotify iOS App Remote SDK is not embedded here (binary SDK / CocoaPods packaging is awkward on this Windows-authored tree); Web API player endpoints are the supported path today. App Remote can be added later on macOS via the official SpotifyiOS package.

1. Create an app in the [Spotify Developer Dashboard](https://developer.spotify.com/dashboard).
2. Add redirect URI exactly: `sleepingroutineforzy://spotify-callback`
3. Copy secrets template and set the **public** Client ID:

   ```bash
   cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
   # Edit SPOTIFY_CLIENT_ID=...
   ```

4. Rebuild. Connect from **Onboarding** or **Settings → Spotify**.
5. Never commit confidential client secrets. PKCE does not need a client secret in the app.

## OAuth Configuration

- Redirect URI: `sleepingroutineforzy://spotify-callback` (`CFBundleURLTypes` + `SPOTIFY_REDIRECT_URI`)
- Tokens stored only in the **iOS Keychain** (`SpotifyKeychainTokenStore`)
- Never store tokens in UserDefaults, SwiftData, or source control
- Scopes: `user-read-private`, `playlist-read-private`, `playlist-read-collaborative`, `user-modify-playback-state`, `user-read-playback-state`

## Environment Configuration

| Key | File | Purpose |
|-----|------|---------|
| `SPOTIFY_CLIENT_ID` | `Config/Secrets.xcconfig` | Spotify public client id |
| `SPOTIFY_REDIRECT_URI` | `Config/Shared.xcconfig` / Secrets | OAuth callback |
| `BACKEND_BASE_URL` | Secrets / Shared | Remote Admin API base URL |

`Config/Secrets.xcconfig` is gitignored. Defaults live in `Config/Shared.xcconfig` so the project still opens without secrets.

## Backend Setup

**Remote Admin** is implemented in `backend/` (FastAPI). Local demo uses an **in-memory** store; production should use PostgreSQL + TLS.

```bash
cd backend
python -m venv .venv
# Windows: .venv\Scripts\activate
pip install -r requirements.txt
python main.py
```

- Health: http://127.0.0.1:8080/health  
- Guardian dashboard: http://127.0.0.1:8080/  
- App config: `BACKEND_BASE_URL = http://127.0.0.1:8080` (Simulator). Physical device: use your PC’s LAN IP.

See `backend/README.md` for endpoints and production notes.

## Database Setup

Planned tables (Phase 7):

- `users`, `devices`, `device_permissions`, `device_status`
- `sleep_routines`, `sleep_alarms`, `sleep_sessions`
- `spotify_connections` (no passwords; minimal OAuth metadata server-side if needed)

## Running Locally

```bash
# On macOS with Xcode installed:
open SleepingRoutineForZy.xcodeproj
# Product → Run (⌘R)
```

Or:

```bash
xcodebuild -scheme SleepingRoutineForZy -destination 'platform=iOS Simulator,name=iPhone 16' build
```

## Testing

```bash
xcodebuild test \
  -scheme SleepingRoutineForZy \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Phase 1–6 unit coverage includes:

- Sleep timer presets, clamping, expiry, reconstruction after “restart”
- Routine state machine happy path + failure
- Codable round-trips for preferences / routine / alarm / device status
- In-memory Keychain
- SwiftData repository save/load/delete
- App-owned audio prepare/play/stop stubs
- Spotify PKCE challenge vector, ViewModel selection persistence, routine URI playback
- Admin PIN / credential store, opt-in register + check-in stubs, API endpoint URLs

## Privacy

The app collects only what is needed for the sleep routine and **opted-in** remote Admin status, for example:

- Sleep routine and alarm settings
- Spotify connection state (not passwords)
- App-generated sleep session history (app activity, not medical sleep quality)
- Device status fields the user agrees to share (battery, charging, routine active, etc.)

**Never collected:** messages, passwords, browsing history, keystrokes, other apps’ private content, microphone, camera, location, screen contents.

## iOS Limitations

| Topic | Limitation |
|-------|------------|
| Alarms | Third-party apps use `UNUserNotificationCenter`. They are **not** equivalent to Apple Clock. Delivery depends on notification permission and system behavior. |
| Background | Continuous execution is **not** guaranteed. Sleep timer uses persisted timestamps; remote check-ins are opportunistic. |
| Battery / status | Only APIs Apple exposes (e.g. `UIDevice` battery monitoring). No secret surveillance. |
| Stopping audio | The app can stop **its own** audio. Stopping Spotify requires Spotify’s supported remote APIs when connected. |

## Spotify Limitations

- This app does **not** stream Spotify audio itself. Playback is requested via `PUT /me/player/play` on the user’s **active Spotify Connect device**.
- **Spotify Premium** is typically required for Web API remote playback control.
- An **active device** is required — usually open the Spotify app on the iPhone first. If none is active, the app opens Spotify and shows an honest “playback unavailable” recovery.
- Stopping Spotify uses `PUT /me/player/pause` when connected; there is no system-wide audio kill.
- Official **App Remote** (SDK) is not bundled in this phase; it can be layered on later without changing the Keychain/PKCE token store.
- Physical device + real Client ID recommended for end-to-end playback tests.

## Admin Architecture

**Remote Admin** (selected):

```
Zy iPhone App  --HTTPS check-in-->  Backend API  -->  store (memory demo / PostgreSQL prod)
                                         ^
Guardian browser dashboard  --pair + auth----┘
```

- Opt-in only (`remoteMonitoringOptIn`). Off by default.
- Device registers → access/refresh tokens in Keychain + one-time **pairing code**.
- Guardian pairs at the web dashboard with that code (server issues admin bearer token).
- Opportunistic check-in when the app becomes active; UI shows stale `lastCheckIn` honestly.
- Local **Admin PIN** protects Settings → Admin on the phone (separate from backend auth).
- Privacy copy lives under Settings → Privacy.

## Production Deployment

Not applicable in Phase 1. Later:

1. Configure signing, App Store Connect, privacy nutrition labels.
2. Deploy backend with TLS, secrets management, audit logs.
3. Ship Spotify credentials via secure config — never in git.
4. Verify alarms, timer persistence, and Admin check-in on a real iPhone.

## Project Structure

```
SleepingRoutineForZy/     # Native Swift iOS app (source of truth for iPhone)
flutter_app/              # Flutter Android + Web port (Windows testing)
backend/                  # Remote Admin API + guardian dashboard
Config/                   # xcconfig (secrets gitignored)
```

## Phase status / next

Phases 1–7 are implemented in the **Swift iOS** app. A parallel **Flutter (Android + Web)** port lives in `flutter_app/` for Windows testing (Chrome / Android emulator). It does not replace the iOS project.

**Next instruction:** implement **Phase 8 — Privacy / security audit**, or continue Flutter polish.

## Architecture notes

- **MVVM + Services + Repository**
- Business logic stays out of SwiftUI views
- Protocols for Audio, Spotify, Notifications, DeviceStatus, StatusCheckIn
- Stubs throw typed `SleepRoutineError` values — no fake capabilities
