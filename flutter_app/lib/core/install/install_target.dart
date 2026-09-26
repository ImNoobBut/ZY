import 'package:flutter/foundation.dart';

/// Which native install artifact to offer for this device/browser.
enum InstallTarget { androidApk, iosIpa, other }

/// Prefer Android APK or iOS IPA based on the current platform / mobile browser.
///
/// On Flutter web, [defaultTargetPlatform] follows the browser's OS (Chrome on
/// Android → android, Safari on iPhone → iOS).
InstallTarget detectInstallTarget() {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return InstallTarget.androidApk;
    case TargetPlatform.iOS:
      return InstallTarget.iosIpa;
    default:
      return InstallTarget.other;
  }
}
