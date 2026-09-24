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

## Run (Android emulator)

```powershell
flutter emulators
flutter emulators --launch <id>
flutter run -d android
```

## Spotify (Flutter web)

Your Spotify app currently has the **iOS** redirect:

```
sleepingroutineforzy://spotify-callback
```

For Flutter web you must **also** add this Redirect URI in the
[Spotify Developer Dashboard](https://developer.spotify.com/dashboard) → your app → Settings → Redirect URIs:

```
http://127.0.0.1:7357/callback
```

Save, then restart:

```powershell
flutter run -d web-server --web-hostname=127.0.0.1 --web-port=7357
```

Open **http://127.0.0.1:7357** (not `localhost`) so it matches the redirect URI exactly.


Start the Admin backend first:

```powershell
cd e:\Develop\App\Zy\SRZ\backend
python -m uvicorn main:app --host 127.0.0.1 --port 8081
```

## Feature parity (v0.7)

| Area | Status |
|------|--------|
| Onboarding | Yes |
| Home / sleep routine + timer timestamps | Yes |
| Sleep timer presets | Yes |
| Alarms (Android notifications; limited on web) | Partial on web |
| App-owned quiet audio | Yes (asset tone) |
| Spotify PKCE + Web API | Yes (needs Client ID) |
| Remote Admin opt-in + pairing | Yes |
| Privacy screen | Yes |

## Relationship to Swift

Keep developing `SleepingRoutineForZy/` for production iPhone.  
Use `flutter_app/` for Windows-friendly demos and iteration.
