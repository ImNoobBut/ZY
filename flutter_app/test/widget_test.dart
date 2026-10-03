import 'package:flutter_test/flutter_test.dart';
import 'package:sleeping_routine_for_zy/core/models/models.dart';
import 'package:sleeping_routine_for_zy/core/services/sync_service.dart';

void main() {
  group('sleep timer minutes', () {
    test('clampSleepTimerMinutes allows 1 through 24 hours', () {
      expect(clampSleepTimerMinutes(0), 1);
      expect(clampSleepTimerMinutes(-5), 1);
      expect(clampSleepTimerMinutes(1), 1);
      expect(clampSleepTimerMinutes(180), 180);
      expect(clampSleepTimerMinutes(1440), 1440);
      expect(clampSleepTimerMinutes(1441), 1440);
      expect(kMaxSleepTimerMinutes, 24 * 60);
    });

    test('formatSleepTimerMinutes shows hours for long durations', () {
      expect(formatSleepTimerMinutes(45), '45 min');
      expect(formatSleepTimerMinutes(60), '1h');
      expect(formatSleepTimerMinutes(90), '1h 30m');
      expect(formatSleepTimerMinutes(150), '2h 30m');
      expect(formatSleepTimerMinutes(1440), '24h');
    });

    test('parseSleepTimerInput accepts friendly formats', () {
      expect(parseSleepTimerInput('90'), 90);
      expect(parseSleepTimerInput('30m'), 30);
      expect(parseSleepTimerInput('2h'), 120);
      expect(parseSleepTimerInput('2.5h'), 150);
      expect(parseSleepTimerInput('2:30'), 150);
      expect(parseSleepTimerInput('2h 30m'), 150);
      expect(parseSleepTimerInput('2h30'), 150);
      expect(parseSleepTimerInput(''), isNull);
      expect(parseSleepTimerInput('abc'), isNull);
      expect(parseSleepTimerInput('9999'), 1440);
    });
  });

  group('lite models & sync contracts', () {
    test('UserPreferences round-trip json', () {
      final original = UserPreferences(
        hasCompletedOnboarding: true,
        defaultSleepTimerSeconds: 45 * 60,
        selectedSpotifyUri: 'spotify:track:abc',
        selectedSpotifyTitle: 'Calm night',
      );
      final decoded = UserPreferences.fromJson(original.toJson());
      expect(decoded.hasCompletedOnboarding, isTrue);
      expect(decoded.defaultSleepTimerSeconds, 45 * 60);
      expect(decoded.selectedSpotifyUri, 'spotify:track:abc');
      expect(decoded.selectedSpotifyTitle, 'Calm night');
    });

    test('SleepRoutine round-trip preserves timer fields', () {
      final started = DateTime.utc(2026, 10, 3, 12);
      final ends = started.add(const Duration(minutes: 30));
      final routine = SleepRoutine(
        id: 'r1',
        sleepTimerDurationSeconds: 30 * 60,
        musicSource: MusicSource.spotify,
        startedAt: started,
        endsAt: ends,
      );
      final decoded = SleepRoutine.fromJson(routine.toJson());
      expect(decoded.id, 'r1');
      expect(decoded.musicSource, MusicSource.spotify);
      expect(decoded.sleepTimerDurationSeconds, 30 * 60);
      expect(decoded.startedAt, started);
      expect(decoded.endsAt, ends);
    });
  });

  group('outbox push must not drop in-flight mutations', () {
    test('keeps mutations added while push was in flight', () {
      final pushedAt = DateTime.utc(2026, 9, 26, 12);
      final pushed = [
        SyncMutation(
          entityType: 'preferences',
          entityId: 'default',
          payload: const {'v': 1},
          updatedAt: pushedAt,
        ),
      ];
      final midFlight = SyncMutation(
        entityType: 'routine',
        entityId: 'active',
        payload: const {'id': 'r2'},
        updatedAt: DateTime.utc(2026, 9, 26, 12, 1),
      );
      final current = [...pushed, midFlight];

      final remaining = SyncService.outboxAfterSuccessfulPush(
        pushed: pushed,
        current: current,
      );

      expect(remaining, hasLength(1));
      expect(remaining.single.entityId, 'active');
    });

    test('keeps newer upsert for same entity enqueued during push', () {
      final oldAt = DateTime.utc(2026, 9, 26, 12);
      final newAt = DateTime.utc(2026, 9, 26, 12, 5);
      final pushed = [
        SyncMutation(
          entityType: 'preferences',
          entityId: 'default',
          payload: const {'v': 1},
          updatedAt: oldAt,
        ),
      ];
      final current = [
        SyncMutation(
          entityType: 'preferences',
          entityId: 'default',
          payload: const {'v': 2},
          updatedAt: newAt,
        ),
      ];

      final remaining = SyncService.outboxAfterSuccessfulPush(
        pushed: pushed,
        current: current,
      );

      expect(remaining, hasLength(1));
      expect(remaining.single.payload['v'], 2);
    });

    test('clears only the exact pushed snapshot (regression: wipe-all)', () {
      final at = DateTime.utc(2026, 9, 26, 12);
      final pushed = [
        SyncMutation(
          entityType: 'routine',
          entityId: 'active',
          payload: const {},
          updatedAt: at,
        ),
      ];

      final remaining = SyncService.outboxAfterSuccessfulPush(
        pushed: pushed,
        current: pushed,
      );

      expect(remaining, isEmpty);
    });
  });
}
