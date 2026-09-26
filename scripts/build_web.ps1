# Build Flutter web for Cloudflare Pages.
# Usage:
#   .\scripts\build_web.ps1 -BackendBaseUrl "https://your-api.example.com"
# Optional:
#   .\scripts\build_web.ps1 -BackendBaseUrl "https://..." -SpotifyClientId "..." -Deploy
# Env fallbacks: BACKEND_BASE_URL, SPOTIFY_CLIENT_ID, SPOTIFY_REDIRECT_URI,
#                CLOUDFLARE_PAGES_PROJECT, FLUTTER_SDK / FLUTTER_ROOT
#
# On hosted Pages, Spotify redirect is {origin}/callback (see AppConfig).
# SPOTIFY_REDIRECT_URI is only needed for local loopback overrides.

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

# Prefer FLUTTER_ROOT / PATH; optional local override via FLUTTER_SDK.
$flutterSdk = $env:FLUTTER_SDK
if (-not $flutterSdk -and $env:FLUTTER_ROOT) {
    $flutterSdk = $env:FLUTTER_ROOT
}
if ($flutterSdk -and (Test-Path (Join-Path $flutterSdk "bin\flutter.bat"))) {
    $env:Path = (Join-Path $flutterSdk "bin") + ";" + $env:Path
}

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
    # Prefer classic JS build; --pwa-strategy is deprecated on newer Flutter.
    flutter build web --release --no-wasm-dry-run @defines
    Write-Host "Built: $app\build\web"
    Write-Host "Spotify redirect on Pages uses {origin}/callback automatically."
    if ($Deploy) {
        npx --yes wrangler pages deploy build/web --project-name=$ProjectName
    }
}
finally {
    Pop-Location
}
