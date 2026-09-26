#!/usr/bin/env bash
# Build Flutter web for Cloudflare Pages.
# Usage:
#   ./scripts/build_web.sh https://your-api.example.com [spotify_client_id]
# Or: export BACKEND_BASE_URL=... SPOTIFY_CLIENT_ID=... && ./scripts/build_web.sh
#
# Optional env: SPOTIFY_REDIRECT_URI (local loopback only), FLUTTER_SDK / FLUTTER_ROOT
# On hosted Pages, Spotify redirect is {origin}/callback (see AppConfig).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND_BASE_URL="${1:-${BACKEND_BASE_URL:-}}"
SPOTIFY_CLIENT_ID="${2:-${SPOTIFY_CLIENT_ID:-}}"
SPOTIFY_REDIRECT_URI="${SPOTIFY_REDIRECT_URI:-}"

if [[ -n "${FLUTTER_SDK:-}" ]]; then
  export PATH="${FLUTTER_SDK}/bin:${PATH}"
elif [[ -n "${FLUTTER_ROOT:-}" ]]; then
  export PATH="${FLUTTER_ROOT}/bin:${PATH}"
fi

if [[ -z "${BACKEND_BASE_URL}" ]]; then
  echo "BACKEND_BASE_URL is required (arg or env)." >&2
  exit 1
fi
cd "$ROOT/flutter_app"
flutter pub get
# Prefer classic JS build; --pwa-strategy is deprecated on newer Flutter.
ARGS=(build web --release --no-wasm-dry-run "--dart-define=BACKEND_BASE_URL=${BACKEND_BASE_URL}")
if [[ -n "$SPOTIFY_CLIENT_ID" ]]; then
  ARGS+=("--dart-define=SPOTIFY_CLIENT_ID=${SPOTIFY_CLIENT_ID}")
fi
if [[ -n "$SPOTIFY_REDIRECT_URI" ]]; then
  ARGS+=("--dart-define=SPOTIFY_REDIRECT_URI=${SPOTIFY_REDIRECT_URI}")
fi
flutter "${ARGS[@]}"
echo "Built: $ROOT/flutter_app/build/web"
echo "Spotify redirect on Pages uses {origin}/callback automatically."
