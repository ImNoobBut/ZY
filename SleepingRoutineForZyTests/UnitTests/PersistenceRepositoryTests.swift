import XCTest
import SwiftData
@testable import SleepingRoutineForZy

final class PersistenceRepositoryTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
    }

    func testPreferencesSaveAndLoad() throws {
        let repo = PreferencesRepositoryLive(context: context)
        var preferences = UserPreferences.default
        preferences.hasCompletedOnboarding = true
        preferences.defaultSleepTimer = 45 * 60
        try repo.save(preferences)
        let loaded = repo.load()
        XCTAssertTrue(loaded.hasCompletedOnboarding)
        XCTAssertEqual(loaded.defaultSleepTimer, 45 * 60, accuracy: 0.001)
    }

    func testRoutineSaveAndLoad() throws {
        let repo = RoutineRepositoryLive(context: context)
        var routine = SleepRoutine.makeDefault(duration: 30 * 60)
        let now = Date(timeIntervalSince1970: 1_000_000)
        routine.startedAt = now
        routine.endsAt = now.addingTimeInterval(30 * 60)
        try repo.save(routine)
        let loaded = repo.loadActiveRoutine()
        XCTAssertEqual(loaded?.id, routine.id)
        XCTAssertEqual(loaded?.startedAt, now)
    }

    func testAlarmSaveEditDelete() throws {
        let repo = AlarmRepositoryLive(context: context)
        var alarm = SleepAlarm.makeDefault(hour: 7, minute: 0)
        try repo.save(alarm)
        XCTAssertEqual(repo.fetchAll().count, 1)

        alarm.label = "Morning"
        alarm.isEnabled = false
        try repo.save(alarm)
        XCTAssertEqual(repo.fetchAll().first?.label, "Morning")
        XCTAssertFalse(repo.fetchAll().first?.isEnabled ?? true)

        try repo.delete(id: alarm.id)
        XCTAssertTrue(repo.fetchAll().isEmpty)
    }

    func testHistoryAppendAndFetch() throws {
        let repo = HistoryRepositoryLive(context: context)
        let record = SleepSessionRecord(
            id: UUID(),
            startedAt: Date(timeIntervalSince1970: 1_000_000),
            musicStoppedAt: Date(timeIntervalSince1970: 1_001_800),
            alarmTime: Date(timeIntervalSince1970: 1_025_200),
            completedAt: Date(timeIntervalSince1970: 1_025_200),
            notes: nil
        )
        try repo.append(record)
        let recent = repo.fetchRecent(limit: 5)
        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent.first?.id, record.id)
    }
}
