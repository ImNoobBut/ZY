#!/usr/bin/env bash
# Build a signed IPA (Flutter iOS App Archive) on macOS with Xcode.
#
# Requires: macOS, Xcode, CocoaPods, Flutter, Apple Developer signing set up
# in Xcode (Team + Bundle ID matching the Runner target).
#
# Usage:
#   export BACKEND_BASE_URL=https://srz-admin-api.onrender.com
#   export SPOTIFY_CLIENT_ID=...          # optional
#   export IOS_INSTALL_URL=https://testflight.apple.com/join/...  # optional override for in-app button
#   ./scripts/build_ipa.sh
#
# Output:
#   flutter_app/build/ios/ipa/*.ipa
#   flutter_app/web/downloads/zy-sleep.ipa  (copied for Cloudflare Pages)
#
# Note: Installing a raw IPA on a normal iPhone usually needs TestFlight,
# Enterprise distribution, or a Mac sideload tool. Prefer uploading the
# archive to App Store Connect / TestFlight and set IOS_INSTALL_URL.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/flutter_app"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "IPA builds require macOS + Xcode. On Windows/Linux, build the Android APK instead:" >&2
  echo "  .\\scripts\\build_apk.ps1" >&2
  exit 1
fi

if [[ -n "${FLUTTER_SDK:-}" ]]; then
  export PATH="${FLUTTER_SDK}/bin:${PATH}"
elif [[ -n "${FLUTTER_ROOT:-}" ]]; then
  export PATH="${FLUTTER_ROOT}/bin:${PATH}"
fi

cd "$APP"
flutter pub get
cd ios
pod install
cd ..

DEFINES=()
if [[ -n "${BACKEND_BASE_URL:-}" ]]; then
  DEFINES+=("--dart-define=BACKEND_BASE_URL=${BACKEND_BASE_URL}")
fi
if [[ -n "${SPOTIFY_CLIENT_ID:-}" ]]; then
  DEFINES+=("--dart-define=SPOTIFY_CLIENT_ID=${SPOTIFY_CLIENT_ID}")
fi
if [[ -n "${IOS_INSTALL_URL:-}" ]]; then
  DEFINES+=("--dart-define=IOS_INSTALL_URL=${IOS_INSTALL_URL}")
fi
if [[ -n "${ANDROID_APK_URL:-}" ]]; then
  DEFINES+=("--dart-define=ANDROID_APK_URL=${ANDROID_APK_URL}")
fi

# Produces build/ios/ipa/*.ipa when export options are configured.
flutter build ipa --release "${DEFINES[@]}"

IPA="$(ls -1 "$APP"/build/ios/ipa/*.ipa 2>/dev/null | head -n 1 || true)"
if [[ -z "${IPA}" ]]; then
  echo "No IPA found under build/ios/ipa. Open Xcode Organizer if the archive succeeded without export." >&2
  echo "Archive path: build/ios/archive/Runner.xcarchive" >&2
  exit 1
fi

mkdir -p "$APP/web/downloads"
cp -f "$IPA" "$APP/web/downloads/zy-sleep.ipa"
echo "IPA ready: $APP/web/downloads/zy-sleep.ipa"
echo "Public URL after Pages deploy: https://sleeping-routine-for-zy.pages.dev/downloads/zy-sleep.ipa"
echo "Tip: for end users, prefer a TestFlight link via IOS_INSTALL_URL."
