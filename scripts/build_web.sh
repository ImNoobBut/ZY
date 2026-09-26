#!/usr/bin/env bash
# Build Flutter web for Cloudflare Pages (offline-first PWA).
# Usage:
#   ./scripts/build_web.sh https://srz-admin-api.onrender.com [spotify_client_id]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND_BASE_URL="${1:?BACKEND_BASE_URL required}"
SPOTIFY_CLIENT_ID="${2:-}"
cd "$ROOT/flutter_app"
flutter pub get
ARGS=(build web --release --pwa-strategy=offline-first "--dart-define=BACKEND_BASE_URL=${BACKEND_BASE_URL}")
if [[ -n "$SPOTIFY_CLIENT_ID" ]]; then
  ARGS+=("--dart-define=SPOTIFY_CLIENT_ID=${SPOTIFY_CLIENT_ID}")
fi
flutter "${ARGS[@]}"
echo "Built: $ROOT/flutter_app/build/web"
