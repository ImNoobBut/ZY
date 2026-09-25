import Foundation

enum StreakCalculator {
    /// Night key = local calendar date of `startedAt`.
    /// Counts nights with non-nil `completedAt`.
    /// Anchor is today if now is at/after preferred bedtime, else yesterday.
    static func currentStreak(
        sessions: [SleepSessionRecord],
        bedtimeHour: Int,
        bedtimeMinute: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        var completedNights = Set<DateComponents>()
        for session in sessions where session.completedAt != nil {
            let parts = calendar.dateComponents([.year, .month, .day], from: session.startedAt)
            completedNights.insert(parts)
        }
        guard !completedNights.isEmpty else { return 0 }

        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let afterBedtime = hour > bedtimeHour || (hour == bedtimeHour && minute >= bedtimeMinute)

        var cursor = calendar.startOfDay(for: now)
        if !afterBedtime {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }

        func key(_ date: Date) -> DateComponents {
            calendar.dateComponents([.year, .month, .day], from: date)
        }

        let previous = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        if !completedNights.contains(key(cursor)) && !completedNights.contains(key(previous)) {
            return 0
        }
        if !completedNights.contains(key(cursor)) {
            cursor = previous
        }

        var streak = 0
        while completedNights.contains(key(cursor)) {
            streak += 1
            guard let next = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = next
        }
        return streak
    }
}
