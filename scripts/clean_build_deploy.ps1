# Clean → build Flutter web → deploy to Cloudflare Pages.
#
# Requires BACKEND_BASE_URL (param or env). Optional:
#   SPOTIFY_CLIENT_ID, SPOTIFY_REDIRECT_URI, CLOUDFLARE_PAGES_PROJECT, CF_PAGES_BRANCH,
#   FLUTTER_SDK / FLUTTER_ROOT
#
# Usage:
#   $env:BACKEND_BASE_URL = "https://your-api.example.com"
#   $env:SPOTIFY_CLIENT_ID = "..."
#   .\scripts\clean_build_deploy.ps1
#
#   .\scripts\clean_build_deploy.ps1 -BackendBaseUrl "https://..." -SpotifyClientId "..."
#   .\scripts\clean_build_deploy.ps1 -Branch production -SkipClean
#   .\scripts\clean_build_deploy.ps1 -SkipDeploy
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

    # Stage native installers into the Pages output when present.
    # Cloudflare Pages rejects files > 25 MiB — skip oversized binaries.
    $webDownloads = Join-Path $webOut "downloads"
    New-Item -ItemType Directory -Force -Path $webDownloads | Out-Null
    $maxPagesBytes = 25MB
    $stagedApk = Join-Path $app "web\downloads\zy-sleep.apk"
    $stagedIpa = Join-Path $app "web\downloads\zy-sleep.ipa"
    if (Test-Path $stagedApk) {
        $len = (Get-Item $stagedApk).Length
        if ($len -le $maxPagesBytes) {
            Copy-Item -Force $stagedApk (Join-Path $webDownloads "zy-sleep.apk")
            Write-Host "Included Android APK in Pages: /downloads/zy-sleep.apk ($([math]::Round($len/1MB,1)) MiB)"
        }
        else {
            Write-Host "Skipped APK for Pages (size $([math]::Round($len/1MB,1)) MiB > 25 MiB). Use split-per-abi or GitHub Releases / R2." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "No staged APK (run scripts\\build_apk.ps1 first to publish one)."
    }
    if (Test-Path $stagedIpa) {
        $len = (Get-Item $stagedIpa).Length
        if ($len -le $maxPagesBytes) {
            Copy-Item -Force $stagedIpa (Join-Path $webDownloads "zy-sleep.ipa")
            Write-Host "Included iOS IPA in Pages: /downloads/zy-sleep.ipa"
        }
        else {
            Write-Host "Skipped IPA for Pages (size $([math]::Round($len/1MB,1)) MiB > 25 MiB). Prefer TestFlight (IOS_INSTALL_URL)." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "No staged IPA (run scripts/build_ipa.sh on a Mac, or set IOS_INSTALL_URL to TestFlight)."
    }

    Write-Host "Built: $webOut"
    Write-Host "Spotify redirect on Pages uses {origin}/callback automatically."
    Write-Host "Downloads (after deploy):"
    Write-Host "  Android: https://$ProjectName.pages.dev/downloads/zy-sleep.apk"
    Write-Host "  iOS:     https://$ProjectName.pages.dev/downloads/zy-sleep.ipa"

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
