#!/usr/bin/env bash
# Clean → build Flutter web → deploy to Cloudflare Pages.
#
# Requires BACKEND_BASE_URL (arg or env). Optional:
#   SPOTIFY_CLIENT_ID, CLOUDFLARE_PAGES_PROJECT, BRANCH
#
# Usage:
#   export BACKEND_BASE_URL=https://your-api.example.com
#   export SPOTIFY_CLIENT_ID=...
#   ./scripts/clean_build_deploy.sh
#   ./scripts/clean_build_deploy.sh https://your-api.example.com [spotify_client_id]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/flutter_app"
BACKEND_BASE_URL="${1:-${BACKEND_BASE_URL:-}}"
SPOTIFY_CLIENT_ID="${2:-${SPOTIFY_CLIENT_ID:-}}"
PROJECT_NAME="${CLOUDFLARE_PAGES_PROJECT:-sleeping-routine-for-zy}"
BRANCH="${BRANCH:-main}"

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
DEFINES=("--dart-define=BACKEND_BASE_URL=${BACKEND_BASE_URL}")
if [[ -n "${SPOTIFY_CLIENT_ID}" ]]; then
  DEFINES+=("--dart-define=SPOTIFY_CLIENT_ID=${SPOTIFY_CLIENT_ID}")
fi
flutter build web --release --no-wasm-dry-run "${DEFINES[@]}"

echo "==> 3/3 Deploy Cloudflare Pages ($PROJECT_NAME / $BRANCH)"
npx --yes wrangler pages deploy build/web \
  --project-name="$PROJECT_NAME" \
  --branch="$BRANCH" \
  --commit-dirty=true

echo "Live: https://${PROJECT_NAME}.pages.dev"
