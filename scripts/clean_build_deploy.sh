#!/usr/bin/env bash
# Clean → build Flutter web → deploy to Cloudflare Pages.
#
# Requires BACKEND_BASE_URL (arg or env). Optional:
#   SPOTIFY_CLIENT_ID, SPOTIFY_REDIRECT_URI, CLOUDFLARE_PAGES_PROJECT, BRANCH,
#   FLUTTER_SDK / FLUTTER_ROOT
#
# Usage:
#   export BACKEND_BASE_URL=https://your-api.example.com
#   export SPOTIFY_CLIENT_ID=...
#   ./scripts/clean_build_deploy.sh
#   ./scripts/clean_build_deploy.sh https://your-api.example.com [spotify_client_id]
#
# On hosted Pages, Spotify redirect is {origin}/callback (see AppConfig).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/flutter_app"
BACKEND_BASE_URL="${1:-${BACKEND_BASE_URL:-}}"
SPOTIFY_CLIENT_ID="${2:-${SPOTIFY_CLIENT_ID:-}}"
SPOTIFY_REDIRECT_URI="${SPOTIFY_REDIRECT_URI:-}"
PROJECT_NAME="${CLOUDFLARE_PAGES_PROJECT:-sleeping-routine-for-zy}"
BRANCH="${BRANCH:-main}"

if [[ -n "${FLUTTER_SDK:-}" ]]; then
  export PATH="${FLUTTER_SDK}/bin:${PATH}"
elif [[ -n "${FLUTTER_ROOT:-}" ]]; then
  export PATH="${FLUTTER_ROOT}/bin:${PATH}"
fi

if [[ -z "${BACKEND_BASE_URL}" ]]; then
  echo "BACKEND_BASE_URL is required (arg or env)." >&2
  exit 1
fi

cd "$APP"

echo "==> 1/3 Clean"
flutter clean
rm -rf build/web

echo "==> 2/3 Build web (release)"
flutter pub get
# Prefer classic JS build; --pwa-strategy is deprecated on newer Flutter.
DEFINES=("--dart-define=BACKEND_BASE_URL=${BACKEND_BASE_URL}")
if [[ -n "${SPOTIFY_CLIENT_ID}" ]]; then
  DEFINES+=("--dart-define=SPOTIFY_CLIENT_ID=${SPOTIFY_CLIENT_ID}")
fi
if [[ -n "${SPOTIFY_REDIRECT_URI}" ]]; then
  DEFINES+=("--dart-define=SPOTIFY_REDIRECT_URI=${SPOTIFY_REDIRECT_URI}")
fi
flutter build web --release --no-wasm-dry-run "${DEFINES[@]}"

if [[ ! -f build/web/index.html ]]; then
  echo "Build failed: missing build/web/index.html" >&2
  exit 1
fi

mkdir -p build/web/downloads
if [[ -f web/downloads/zy-sleep.apk ]]; then
  cp -f web/downloads/zy-sleep.apk build/web/downloads/zy-sleep.apk
  echo "Included Android APK in Pages: /downloads/zy-sleep.apk"
fi
if [[ -f web/downloads/zy-sleep.ipa ]]; then
  cp -f web/downloads/zy-sleep.ipa build/web/downloads/zy-sleep.ipa
  echo "Included iOS IPA in Pages: /downloads/zy-sleep.ipa"
fi

echo "Built: $APP/build/web"
echo "Spotify redirect on Pages uses {origin}/callback automatically."
echo "Downloads (after deploy):"
echo "  Android: https://${PROJECT_NAME}.pages.dev/downloads/zy-sleep.apk"
echo "  iOS:     https://${PROJECT_NAME}.pages.dev/downloads/zy-sleep.ipa"
echo "==> 3/3 Deploy Cloudflare Pages ($PROJECT_NAME / $BRANCH)"
npx --yes wrangler pages deploy build/web \
  --project-name="$PROJECT_NAME" \
  --branch="$BRANCH" \
  --commit-dirty=true

echo "Live: https://${PROJECT_NAME}.pages.dev"
