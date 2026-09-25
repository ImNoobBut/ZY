import 'package:flutter_test/flutter_test.dart';
import 'package:sleeping_routine_for_zy/core/models/models.dart';
import 'package:sleeping_routine_for_zy/core/services/streak_calculator.dart';

void main() {
  test('UserPreferences round-trip json', () {
    final original = UserPreferences(
      hasCompletedOnboarding: true,
      defaultSleepTimerSeconds: 45 * 60,
      remoteMonitoringOptIn: true,
      bedtimeReminderEnabled: false,
      selectedQuietSound: QuietSound.rain,
    );
    final decoded = UserPreferences.fromJson(original.toJson());
    expect(decoded.hasCompletedOnboarding, isTrue);
    expect(decoded.defaultSleepTimerSeconds, 45 * 60);
    expect(decoded.remoteMonitoringOptIn, isTrue);
    expect(decoded.bedtimeReminderEnabled, isFalse);
    expect(decoded.selectedQuietSound, QuietSound.rain);
  });

  test('StreakCalculator counts consecutive nights', () {
    final now = DateTime(2026, 9, 26, 23, 0);
    final sessions = [
      SleepSessionRecord(
        id: '1',
        startedAt: DateTime(2026, 9, 26, 22, 0),
        completedAt: DateTime(2026, 9, 26, 22, 30),
      ),
      SleepSessionRecord(
        id: '2',
        startedAt: DateTime(2026, 9, 25, 22, 0),
        completedAt: DateTime(2026, 9, 25, 22, 30),
      ),
    ];
    final streak = StreakCalculator.currentStreak(
      sessions: sessions,
      bedtimeHour: 22,
      bedtimeMinute: 0,
      now: now,
    );
    expect(streak, 2);
  });
}
