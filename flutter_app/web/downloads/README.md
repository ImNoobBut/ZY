# Hosted native installers (copied into Cloudflare Pages `build/web/downloads/`).
#
# After building:
#   Android: scripts/build_apk.ps1  → place APK as zy-sleep.apk here (or let the script copy)
#   iOS:     scripts/build_ipa.sh   → place IPA as zy-sleep.ipa (Mac + Xcode + signing)
#
# Public URLs (production Pages):
#   https://sleeping-routine-for-zy.pages.dev/downloads/zy-sleep.apk
#   https://sleeping-routine-for-zy.pages.dev/downloads/zy-sleep.ipa
#
# Prefer a TestFlight link for iOS via --dart-define=IOS_INSTALL_URL=...
