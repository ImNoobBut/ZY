import 'package:flutter_test/flutter_test.dart';
import 'package:sleeping_routine_for_zy/core/models/models.dart';

void main() {
  test('UserPreferences round-trip json', () {
    final original = UserPreferences(
      hasCompletedOnboarding: true,
      defaultSleepTimerSeconds: 45 * 60,
      remoteMonitoringOptIn: true,
    );
    final decoded = UserPreferences.fromJson(original.toJson());
    expect(decoded.hasCompletedOnboarding, isTrue);
    expect(decoded.defaultSleepTimerSeconds, 45 * 60);
    expect(decoded.remoteMonitoringOptIn, isTrue);
  });
}
