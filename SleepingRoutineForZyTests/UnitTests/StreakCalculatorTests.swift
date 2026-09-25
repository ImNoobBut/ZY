import XCTest
@testable import SleepingRoutineForZy

final class StreakCalculatorTests: XCTestCase {
    func testConsecutiveNightsAfterBedtime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 23))!
        let sessions = [
            SleepSessionRecord(
                id: UUID(),
                startedAt: calendar.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 22))!,
                completedAt: calendar.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 22, minute: 30))!
            ),
            SleepSessionRecord(
                id: UUID(),
                startedAt: calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 22))!,
                completedAt: calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 22, minute: 30))!
            ),
        ]
        let streak = StreakCalculator.currentStreak(
            sessions: sessions,
            bedtimeHour: 22,
            bedtimeMinute: 0,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(streak, 2)
    }
}
