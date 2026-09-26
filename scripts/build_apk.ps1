# Build release APK and stage it for Cloudflare Pages downloads/.
#
# Usage:
#   $env:ANDROID_HOME = "E:\Develop\tools\android-sdk"   # optional if already set
#   $env:JAVA_HOME = "C:\Program Files (x86)\Android\openjdk\jdk-17.0.14"
#   .\scripts\build_apk.ps1
#   .\scripts\build_apk.ps1 -BackendBaseUrl "https://srz-admin-api.onrender.com"
#
# Output:
#   flutter_app\build\app\outputs\flutter-apk\app-release.apk
#   flutter_app\web\downloads\zy-sleep.apk   (copied for next web deploy)

param(
    [string]$BackendBaseUrl = $env:BACKEND_BASE_URL,
    [string]$SpotifyClientId = $env:SPOTIFY_CLIENT_ID
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$app = Join-Path $root "flutter_app"

if ($env:FLUTTER_SDK -and (Test-Path (Join-Path $env:FLUTTER_SDK "bin\flutter.bat"))) {
    $env:Path = (Join-Path $env:FLUTTER_SDK "bin") + ";" + $env:Path
}
elseif ($env:FLUTTER_ROOT -and (Test-Path (Join-Path $env:FLUTTER_ROOT "bin\flutter.bat"))) {
    $env:Path = (Join-Path $env:FLUTTER_ROOT "bin") + ";" + $env:Path
}

if (-not $env:ANDROID_HOME) {
    foreach ($candidate in @(
        "E:\Develop\tools\android-sdk",
        "$env:LOCALAPPDATA\Android\Sdk",
        "C:\Program Files (x86)\Android\android-sdk"
    )) {
        if (Test-Path $candidate) {
            $env:ANDROID_HOME = $candidate
            $env:ANDROID_SDK_ROOT = $candidate
            break
        }
    }
}

Push-Location $app
try {
    flutter pub get
    $defines = @()
    if ($BackendBaseUrl) {
        $defines += "--dart-define=BACKEND_BASE_URL=$BackendBaseUrl"
    }
    if ($SpotifyClientId) {
        $defines += "--dart-define=SPOTIFY_CLIENT_ID=$SpotifyClientId"
    }
    flutter build apk --release --split-per-abi @defines

    $apkDir = Join-Path $app "build\app\outputs\flutter-apk"
    # Prefer arm64 (phones); fall back to fat APK if present.
    $candidates = @(
        (Join-Path $apkDir "app-arm64-v8a-release.apk"),
        (Join-Path $apkDir "app-armeabi-v7a-release.apk"),
        (Join-Path $apkDir "app-release.apk")
    )
    $apk = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $apk) {
        throw "APK missing under $apkDir"
    }

    $downloads = Join-Path $app "web\downloads"
    New-Item -ItemType Directory -Force -Path $downloads | Out-Null
    $dest = Join-Path $downloads "zy-sleep.apk"
    Copy-Item -Force $apk $dest
    $mb = [math]::Round((Get-Item $dest).Length / 1MB, 1)
    Write-Host "APK ready: $dest ($mb MiB) from $(Split-Path $apk -Leaf)" -ForegroundColor Green
    if ((Get-Item $dest).Length -gt 25MB) {
        Write-Host "Warning: >25 MiB - Cloudflare Pages will reject this file. Host on GitHub Releases/R2 or keep split ABI." -ForegroundColor Yellow
    }
    Write-Host "Public URL after Pages deploy: https://sleeping-routine-for-zy.pages.dev/downloads/zy-sleep.apk"
}
finally {
    Pop-Location
}
