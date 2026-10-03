import 'package:flutter_test/flutter_test.dart';
import 'package:sleeping_routine_for_zy/core/models/models.dart';
import 'package:sleeping_routine_for_zy/core/services/sync_service.dart';

void main() {
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
