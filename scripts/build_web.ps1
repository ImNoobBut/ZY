# Build Flutter web for Cloudflare Pages (offline-first PWA).
# Usage:
#   .\scripts\build_web.ps1 -BackendBaseUrl "https://your-api.example.com"
# Optional:
#   .\scripts\build_web.ps1 -BackendBaseUrl "https://..." -SpotifyClientId "..." -Deploy
# Env fallbacks: BACKEND_BASE_URL, SPOTIFY_CLIENT_ID, SPOTIFY_REDIRECT_URI, CLOUDFLARE_PAGES_PROJECT

param(
    [string]$BackendBaseUrl = $env:BACKEND_BASE_URL,

    [string]$SpotifyClientId = $env:SPOTIFY_CLIENT_ID,

    [string]$SpotifyRedirectUri = $env:SPOTIFY_REDIRECT_URI,

    [string]$ProjectName = $(
        if ($env:CLOUDFLARE_PAGES_PROJECT) { $env:CLOUDFLARE_PAGES_PROJECT }
        else { "sleeping-routine-for-zy" }
    ),

    [switch]$Deploy
)

$ErrorActionPreference = "Stop"

if (-not $BackendBaseUrl) {
    throw "BACKEND_BASE_URL is required (pass -BackendBaseUrl or set `$env:BACKEND_BASE_URL)."
}

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
    if ($SpotifyRedirectUri) {
        $defines += "--dart-define=SPOTIFY_REDIRECT_URI=$SpotifyRedirectUri"
    }
    flutter build web --release --pwa-strategy=offline-first @defines
    Write-Host "Built: $app\build\web"
    Write-Host "Spotify: register Redirect URI https://YOUR-PAGES-HOST/callback (or pass -SpotifyRedirectUri)"
    if ($Deploy) {
        npx --yes wrangler pages deploy build/web --project-name=$ProjectName
    }
}
finally {
    Pop-Location
}
