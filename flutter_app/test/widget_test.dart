import 'package:flutter_test/flutter_test.dart';
import 'package:sleeping_routine_for_zy/core/models/models.dart';
import 'package:sleeping_routine_for_zy/core/services/alarm_scheduler_stub.dart';
import 'package:sleeping_routine_for_zy/core/services/streak_calculator.dart';

void main() {
  group('Phase 9 — models & contracts', () {
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

    test('remoteMonitoringOptIn defaults off (privacy)', () {
      expect(UserPreferences().remoteMonitoringOptIn, isFalse);
    });

    test('SleepAlarm round-trip preserves schedule fields', () {
      final alarm = SleepAlarm(
        id: 'a1',
        hour: 7,
        minute: 15,
        repeatDays: {1, 3, 5},
        label: 'Wake',
        isEnabled: true,
      );
      final decoded = SleepAlarm.fromJson(alarm.toJson());
      expect(decoded.hour, 7);
      expect(decoded.minute, 15);
      expect(decoded.repeatDays, {1, 3, 5});
      expect(decoded.isEnabled, isTrue);
    });

    test('DeviceStatus check-in payload includes opt-in fields', () {
      final status = DeviceStatus(
        batteryLevel: 0.55,
        isCharging: false,
        routineActive: true,
        spotifyConnected: true,
        alarmEnabled: true,
        isPlayingOwnAudio: false,
        lastCheckIn: DateTime.utc(2026, 9, 26, 12),
        preferredBedtime: '22:30',
        currentStreak: 3,
      );
      final json = status.toJson();
      expect(json['preferredBedtime'], '22:30');
      expect(json['currentStreak'], 3);
      expect(json['spotifyConnected'], isTrue);
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

    test('Stub alarm scheduler is honest about unsupported env', () {
      final scheduler = createAlarmScheduler();
      expect(scheduler.isBestEffortOnly, isTrue);
      expect(scheduler.limitationCopy.toLowerCase(), contains('not scheduled'));
    });
  });
}
