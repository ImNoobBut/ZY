#!/usr/bin/env bash
# Build Flutter web for Cloudflare Pages (offline-first PWA).
# Usage:
#   ./scripts/build_web.sh https://your-api.example.com [spotify_client_id]
# Or: export BACKEND_BASE_URL=... SPOTIFY_CLIENT_ID=... && ./scripts/build_web.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND_BASE_URL="${1:-${BACKEND_BASE_URL:-}}"
SPOTIFY_CLIENT_ID="${2:-${SPOTIFY_CLIENT_ID:-}}"
if [[ -z "${BACKEND_BASE_URL}" ]]; then
  echo "BACKEND_BASE_URL is required (arg or env)." >&2
  exit 1
fi
cd "$ROOT/flutter_app"
flutter pub get
ARGS=(build web --release --pwa-strategy=offline-first "--dart-define=BACKEND_BASE_URL=${BACKEND_BASE_URL}")
if [[ -n "$SPOTIFY_CLIENT_ID" ]]; then
  ARGS+=("--dart-define=SPOTIFY_CLIENT_ID=${SPOTIFY_CLIENT_ID}")
fi
flutter "${ARGS[@]}"
echo "Built: $ROOT/flutter_app/build/web"
