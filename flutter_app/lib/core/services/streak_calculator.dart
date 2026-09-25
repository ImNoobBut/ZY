import '../models/models.dart';

/// Computes consecutive-night streaks from completed sleep sessions.
class StreakCalculator {
  /// Night key = local calendar date of [SleepSessionRecord.startedAt].
  /// A night counts when [completedAt] is non-null.
  /// Anchor night is today if [now] is at/after preferred bedtime, else yesterday.
  static int currentStreak({
    required List<SleepSessionRecord> sessions,
    required int bedtimeHour,
    required int bedtimeMinute,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final completedNights = <DateTime>{};
    for (final s in sessions) {
      if (s.completedAt == null) continue;
      final d = s.startedAt;
      completedNights.add(DateTime(d.year, d.month, d.day));
    }
    if (completedNights.isEmpty) return 0;

    final bedtimeToday = DateTime(
      clock.year,
      clock.month,
      clock.day,
      bedtimeHour,
      bedtimeMinute,
    );
    var cursor = !clock.isBefore(bedtimeToday)
        ? DateTime(clock.year, clock.month, clock.day)
        : DateTime(clock.year, clock.month, clock.day).subtract(const Duration(days: 1));

    // If neither anchor nor previous night has a session, streak is 0.
    if (!completedNights.contains(cursor) &&
        !completedNights.contains(cursor.subtract(const Duration(days: 1)))) {
      return 0;
    }
    if (!completedNights.contains(cursor)) {
      cursor = cursor.subtract(const Duration(days: 1));
    }

    var streak = 0;
    while (completedNights.contains(cursor)) {
      streak += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }
}
