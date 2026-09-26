import 'package:flutter_test/flutter_test.dart';
import 'package:sleeping_routine_for_zy/core/models/models.dart';
import 'package:sleeping_routine_for_zy/core/services/alarm_scheduler_stub.dart';
import 'package:sleeping_routine_for_zy/core/services/sync_service.dart';

void main() {
  group('outbox push must not drop in-flight mutations', () {
    test('keeps mutations added while push was in flight', () {
      final pushedAt = DateTime.utc(2026, 9, 26, 12);
      final pushed = [
        SyncMutation(
          entityType: 'alarm',
          entityId: 'a1',
          payload: const {'id': 'a1'},
          updatedAt: pushedAt,
        ),
      ];
      final midFlight = SyncMutation(
        entityType: 'alarm',
        entityId: 'a2',
        payload: const {'id': 'a2'},
        updatedAt: DateTime.utc(2026, 9, 26, 12, 1),
      );
      final current = [...pushed, midFlight];

      final remaining = SyncService.outboxAfterSuccessfulPush(
        pushed: pushed,
        current: current,
      );

      expect(remaining, hasLength(1));
      expect(remaining.single.entityId, 'a2');
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
          entityType: 'session',
          entityId: 's1',
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

  group('native reconcile must cancel deleted alarms', () {
    test('stub reconcile drops OS schedules for removed ids', () async {
      final scheduler = StubAlarmScheduler();
      final a = SleepAlarm(id: 'keep', hour: 7, minute: 0);
      final b = SleepAlarm(id: 'delete-me', hour: 8, minute: 0);
      await scheduler.reconcile([a, b]);
      expect(scheduler.scheduled.map((e) => e.id), containsAll(['keep', 'delete-me']));

      await scheduler.reconcile([a]);
      expect(scheduler.scheduled.map((e) => e.id), ['keep']);
      expect(scheduler.scheduled.any((e) => e.id == 'delete-me'), isFalse);
    });
  });

  group('alarm tombstone LWW', () {
    test('older delete must not remove newer local alarm', () {
      final localUpdated = DateTime.utc(2026, 9, 26, 15);
      final remoteDeleteAt = DateTime.utc(2026, 9, 26, 14);
      var alarms = [
        SleepAlarm(
          id: 'a1',
          hour: 7,
          minute: 0,
          updatedAt: localUpdated,
        ),
      ];

      // Mirror sync_service LWW delete rule.
      const id = 'a1';
      final idx = alarms.indexWhere((a) => a.id == id);
      if (idx >= 0 && remoteDeleteAt.isAfter(alarms[idx].updatedAt)) {
        alarms = alarms.where((a) => a.id != id).toList();
      }

      expect(alarms, hasLength(1));
      expect(alarms.single.id, 'a1');
    });

    test('newer delete removes local alarm', () {
      final localUpdated = DateTime.utc(2026, 9, 26, 14);
      final remoteDeleteAt = DateTime.utc(2026, 9, 26, 15);
      var alarms = [
        SleepAlarm(
          id: 'a1',
          hour: 7,
          minute: 0,
          updatedAt: localUpdated,
        ),
      ];

      const id = 'a1';
      final idx = alarms.indexWhere((a) => a.id == id);
      if (idx >= 0 && remoteDeleteAt.isAfter(alarms[idx].updatedAt)) {
        alarms = alarms.where((a) => a.id != id).toList();
      }

      expect(alarms, isEmpty);
    });
  });
}
