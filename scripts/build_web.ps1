# Build Flutter web for Cloudflare Pages (offline-first PWA).
# Usage:
#   .\scripts\build_web.ps1 -BackendBaseUrl "https://srz-admin-api.onrender.com"
# Optional:
#   .\scripts\build_web.ps1 -BackendBaseUrl "https://..." -SpotifyClientId "..." -Deploy

param(
    [Parameter(Mandatory = $true)]
    [string]$BackendBaseUrl,

    [string]$SpotifyClientId = "",

    [switch]$Deploy
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$app = Join-Path $root "flutter_app"

Push-Location $app
try {
    flutter pub get
    $defines = @(
        "--dart-define=BACKEND_BASE_URL=$BackendBaseUrl"
    )
    if ($SpotifyClientId) {
        $defines += "--dart-define=SPOTIFY_CLIENT_ID=$SpotifyClientId"
    }
    flutter build web --release --pwa-strategy=offline-first @defines
    Write-Host "Built: $app\build\web"
    if ($Deploy) {
        npx --yes wrangler pages deploy build/web --project-name=sleeping-routine-for-zy
    }
}
finally {
    Pop-Location
}
