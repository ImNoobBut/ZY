# Clean → build Flutter web → deploy to Cloudflare Pages.
#
# Requires BACKEND_BASE_URL (param or env). Optional:
#   SPOTIFY_CLIENT_ID, SPOTIFY_REDIRECT_URI, CLOUDFLARE_PAGES_PROJECT, CF_PAGES_BRANCH
#
# Usage:
#   $env:BACKEND_BASE_URL = "https://your-api.example.com"
#   $env:SPOTIFY_CLIENT_ID = "..."
#   .\scripts\clean_build_deploy.ps1
#
#   .\scripts\clean_build_deploy.ps1 -BackendBaseUrl "https://..." -SpotifyClientId "..."
#   .\scripts\clean_build_deploy.ps1 -Branch production -SkipClean
#   .\scripts\clean_build_deploy.ps1 -SkipDeploy

param(
    [string]$BackendBaseUrl = $env:BACKEND_BASE_URL,

    [string]$SpotifyClientId = $env:SPOTIFY_CLIENT_ID,

    [string]$SpotifyRedirectUri = $env:SPOTIFY_REDIRECT_URI,

    [string]$ProjectName = $(
        if ($env:CLOUDFLARE_PAGES_PROJECT) { $env:CLOUDFLARE_PAGES_PROJECT }
        else { "sleeping-routine-for-zy" }
    ),

    [string]$Branch = $(
        if ($env:CF_PAGES_BRANCH) { $env:CF_PAGES_BRANCH } else { "main" }
    ),

    [switch]$SkipClean,

    [switch]$SkipDeploy
)

$ErrorActionPreference = "Stop"

if (-not $BackendBaseUrl) {
    throw "BACKEND_BASE_URL is required (pass -BackendBaseUrl or set `$env:BACKEND_BASE_URL)."
}

$root = Split-Path -Parent $PSScriptRoot
$app = Join-Path $root "flutter_app"
$webOut = Join-Path $app "build\web"

# Prefer FLUTTER_ROOT / PATH; optional local override via FLUTTER_SDK.
$flutterSdk = $env:FLUTTER_SDK
if (-not $flutterSdk -and $env:FLUTTER_ROOT) {
    $flutterSdk = $env:FLUTTER_ROOT
}
if ($flutterSdk -and (Test-Path (Join-Path $flutterSdk "bin\flutter.bat"))) {
    $env:Path = (Join-Path $flutterSdk "bin") + ";" + $env:Path
}

function Step([string]$msg) {
    Write-Host ""
    Write-Host "==> $msg" -ForegroundColor Cyan
}

Push-Location $app
try {
    if (-not $SkipClean) {
        Step "1/3 Clean"
        flutter clean
        if (Test-Path $webOut) {
            Remove-Item -Recurse -Force $webOut
        }
    }
    else {
        Step "1/3 Clean (skipped)"
    }

    Step "2/3 Build web (release)"
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

    if (-not (Test-Path (Join-Path $webOut "index.html"))) {
        throw "Build failed: missing $webOut\index.html"
    }
    Write-Host "Built: $webOut"
    Write-Host "Spotify redirect on Pages uses {origin}/callback automatically."

    if ($SkipDeploy) {
        Step "3/3 Deploy (skipped)"
        Write-Host "Done. Upload $webOut manually if needed."
        return
    }

    Step "3/3 Deploy Cloudflare Pages ($ProjectName / $Branch)"
    npx --yes wrangler pages deploy $webOut `
        --project-name=$ProjectName `
        --branch=$Branch `
        --commit-dirty=true

    Write-Host ""
    Write-Host "Live: https://$ProjectName.pages.dev" -ForegroundColor Green
}
finally {
    Pop-Location
}
