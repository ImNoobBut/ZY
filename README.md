# Sleeping Routine for Zy

## Overview

**Sleeping Routine for Zy** is a calm, privacy-first iPhone app that helps Zy keep a consistent bedtime routine: sleep timer, music (including Spotify where supported), wake alarms via local notifications, and an optional **remote Admin** status dashboard for a guardian.

This repository currently contains **Phase 9 — Device test matrix**: automated contract/API harness (`scripts/phase9_matrix.py`), CI for Flutter tests, plus Phases 1–8 (routine, alarms, Spotify, Remote Admin, privacy/security hardening). Physical iPhone / Android / Chrome rows remain a manual owner checklist.

## Features

| Feature | Status |
|---------|--------|
| Tab navigation (Home / Alarms / Settings) | Updated — Sleep merged into Home |
| Domain models + routine state machine | Phase 1 |
| SwiftData persistence + repositories | Phase 1 |
| Sleep timer timestamp reconstruction | Phase 1 (logic) |
| Onboarding | Phase 2 complete |
| Home routine UX + timer presets | Phase 3 + polish |
| Bedtime reminder | Complete |
| Quiet sounds (soft / rain / white noise / deep hum) | Complete |
| Timer fade-out (app-owned audio) | Complete |
| Sleep history / streak | Complete (local) |
| Local notification alarms | Phase 4 complete (fallback on older iOS) |
| AlarmKit wake alarms (iOS 26+) | MVP complete |
| App-owned audio + AVAudioSession | Phase 5 complete |
| Spotify OAuth PKCE + Web API playback | Phase 6 complete |
| Remote Admin backend + check-in | Phase 7 complete (+ bedtime/streak fields) |
| Flutter Android exact alarms + Spotify deep link | MVP complete |
| Flutter web best-effort reminders | MVP complete |
| Privacy / security audit | Phase 8 complete |
| Full device test matrix | Phase 9 complete (automated subset + manual checklist) |

## Requirements

- macOS with **Xcode 26+** recommended for AlarmKit (iOS 26 SDK); Xcode 15+ still builds the notification fallback path
- iOS **17.0+** deployment target (AlarmKit used at runtime on iOS 26+)
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

The app collects only what is needed for the sleep routine, optional account, and **opted-in** remote Admin status, for example:

- Account email and display name when you register (password is bcrypt-hashed server-side; never stored in the app)
- Sleep routine and alarm settings
- Spotify connection state (tokens in Keychain / platform secure store — not passwords)
- App-generated sleep session history (app activity, not medical sleep quality)
- Device status fields the user agrees to share (battery, charging, routine active, etc.)

**Never collected:** messages, browsing history, keystrokes, other apps’ private content, microphone, camera, location, screen contents. Account passwords are never stored in plaintext.

## Phase 8 — Privacy / security audit (complete)

Hardening shipped with this phase:

- `/health` no longer returns pairing codes (critical leak fixed)
- Admin bearer tokens expire (24h) and are revoked on re-pair
- Rate limits on auth + pairing endpoints
- Flutter OAuth / device tokens + Admin PIN moved to platform secure store (Keystore/Keychain); web documents origin-trust limitation
- Admin PIN uses a per-device random salt
- Privacy screens updated for account auth honesty

## iOS Limitations

| Topic | Limitation |
|-------|------------|
| Alarms | **iOS 26+:** wake alarms use **AlarmKit** after the user grants access (system-grade alerts that can break through Focus/silent). **iOS 17–25:** local notifications via `UNUserNotificationCenter`. Apps still cannot read or control Apple Clock’s own alarms. |
| Background | Continuous execution is **not** guaranteed. Sleep timer uses persisted timestamps; remote check-ins are opportunistic. |
| Battery / status | Only APIs Apple exposes (e.g. `UIDevice` battery monitoring). No secret surveillance. |
| Stopping audio | The app can stop **its own** audio. Stopping Spotify requires Spotify’s supported remote APIs when connected. |

## Android / Web (Flutter) alarms

| Platform | Behavior |
|----------|----------|
| Android | Exact local notifications (`SCHEDULE_EXACT_ALARM` / `POST_NOTIFICATIONS`) with boot reschedule. Grant permission in onboarding or Alarms. |
| Web | Best-effort browser notifications **while the tab stays open** — not a phone alarm clock. |

## Spotify Limitations

- This app does **not** stream Spotify audio itself. Playback is requested via `PUT /me/player/play` on the user’s **active Spotify Connect device**.
- **Spotify Premium** is typically required for Web API remote playback control.
- An **active device** is required — usually open the Spotify app on the phone first. If none is active, the app opens Spotify and shows an honest “playback unavailable” recovery.
- Stopping Spotify uses `PUT /me/player/pause` when connected; there is no system-wide audio kill.
- Official **App Remote** (SDK) is not bundled in this phase; it can be layered on later without changing the Keychain/PKCE token store.
- Physical device + real Client ID recommended for end-to-end playback tests.
- Redirect URIs to register in Spotify Dashboard:
  - iOS / Android: `sleepingroutineforzy://spotify-callback`
  - Flutter web (local): `http://127.0.0.1:7357/callback`
  - Flutter web (Pages): `https://700ff232.sleeping-routine-for-zy.pages.dev/callback`
  - Flutter web (Pages alias): `https://sleeping-routine-for-zy.pages.dev/callback`

## Device verification checklist (MVP)

1. **Spotify Dashboard** — add the redirect URIs above; set `SPOTIFY_CLIENT_ID` in `Config/Secrets.xcconfig` (iOS) and/or `--dart-define=SPOTIFY_CLIENT_ID=...` (Flutter).
2. **iPhone (Mac required)** — Xcode with **iOS 26 SDK** for AlarmKit path; signing Team; install on device; grant AlarmKit; set a wake alarm; connect Spotify and start a bedtime routine.
3. **Older iPhone (iOS 17–25)** — same app build; alarms use notification fallback; grant notifications.
4. **Android** — grant notifications + exact alarms; set alarm; force-stop app; confirm fire; complete Spotify OAuth (custom scheme returns into the app).
5. **Chrome web** — Spotify connect via `http://127.0.0.1:7357`; confirm alarm limitation copy; browser reminders only while the tab is open.

### Phase 9 — automated matrix subset

Run without phones (repo root; backend must be listening on `:8081`):

```bash
cd backend && python main.py
# other terminal:
python scripts/phase9_matrix.py
```

CI (`.github/workflows/ci.yml`) also runs the matrix against a started API and `flutter test` / `flutter analyze`.

**Last local automated run:** 29 pass / 0 fail (static platform contracts + API smoke). Physical device rows above are still owner sign-off.

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

Free PWA + sync stack (see also `backend/README.md`, `scripts/build_web.ps1`):

1. **Database** — create a Neon (or Render) Postgres database; set `DATABASE_URL`.
2. **API** — deploy `backend/` to Render via [`render.yaml`](render.yaml); set `CORS_ORIGINS` to your Pages URL.
3. **Web app** — build with `.\scripts\build_web.ps1 -BackendBaseUrl https://YOUR-API.onrender.com` and publish `flutter_app/build/web` to Cloudflare Pages (or use `.github/workflows/deploy-web.yml`).
4. On phones: open the Pages HTTPS URL → **Add to Home Screen**. Settings → **Sync & install** for status and multi-device pairing.
5. Spotify Client ID via `--dart-define` / CI secrets — never commit secrets.

Native App Store / Play Store shipping remains optional and is out of scope for the free PWA path.

## Project Structure

```
SleepingRoutineForZy/     # Native Swift iOS app (source of truth for iPhone)
flutter_app/              # Flutter Android + Web port (Windows testing)
backend/                  # Remote Admin API + guardian dashboard
Config/                   # xcconfig (secrets gitignored)
```

## Phase status / next

Phases 1–9 are in-tree:

- **iOS:** AlarmKit on iOS 26+ (`AlarmSchedulerAlarmKit`), notification fallback otherwise; Spotify OAuth PKCE
- **Flutter Android:** exact local notifications + Spotify deep-link (`sleepingroutineforzy://spotify-callback`)
- **Flutter Web:** best-effort browser reminders + Spotify web redirect
- **Phase 8:** privacy/security hardening (health leak closed, admin TTL, Flutter secure store)
- **Phase 9:** device test matrix + `scripts/phase9_matrix.py` + CI

**Next:** Manual device sign-off on the Phase 9 checklist (iPhone / Android / Chrome), or App Store / Play packaging if you choose to ship native stores.

## Architecture notes

- **MVVM + Services + Repository**
- Business logic stays out of SwiftUI views
- Protocols for Audio, Spotify, Notifications, DeviceStatus, StatusCheckIn
- Stubs throw typed `SleepRoutineError` values — no fake capabilities
