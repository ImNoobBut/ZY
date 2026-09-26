/// Cross-platform facade for picking a device alarm/ringtone.
abstract class AlarmRingtonePicker {
  /// Whether this platform can open a system ringtone picker (Android).
  bool get isSupported;

  /// Opens the system ringtone picker. Returns a content URI, or null if cancelled.
  Future<String?> pickRingtone({String? currentUri});
}
