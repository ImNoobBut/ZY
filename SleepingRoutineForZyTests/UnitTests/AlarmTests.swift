import XCTest
@testable import SleepingRoutineForZy

final class AlarmNotificationBuilderTests: XCTestCase {
    func testOneTimeIdentifierAndTrigger() {
        let id = UUID()
        let alarm = SleepAlarm(
            id: id,
            hour: 7,
            minute: 0,
            repeatDays: [],
            label: "Wake up",
            isEnabled: true,
            sound: .default,
            vibrationEnabled: true
        )

        let specs = AlarmNotificationBuilder.triggerSpecs(for: alarm)
        XCTAssertEqual(specs.count, 1)
        XCTAssertEqual(specs[0].identifier, "alarm-\(id.uuidString)")
        XCTAssertFalse(specs[0].repeats)
        XCTAssertEqual(specs[0].components.hour, 7)
        XCTAssertEqual(specs[0].components.minute, 0)
        XCTAssertNil(specs[0].components.weekday)
    }

    func testWeekdayRepeatCreatesOneRequestPerDay() {
        var alarm = SleepAlarm.makeDefault(hour: 6, minute: 30)
        alarm.repeatDays = [2, 4, 6]
        let specs = AlarmNotificationBuilder.triggerSpecs(for: alarm)
        XCTAssertEqual(specs.count, 3)
        XCTAssertTrue(specs.allSatisfy(\.repeats))
        XCTAssertEqual(specs.map(\.components.weekday), [2, 4, 6])
        XCTAssertEqual(
            AlarmNotificationBuilder.allIdentifiers(for: alarm).count,
            3
        )
    }

    func testDisabledAlarmProducesNoTriggers() {
        var alarm = SleepAlarm.makeDefault()
        alarm.isEnabled = false
        XCTAssertTrue(AlarmNotificationBuilder.triggerSpecs(for: alarm).isEmpty)
    }

    func testMakeRequestsMatchesTriggerCount() {
        let alarm = SleepAlarm.makeDefault()
        let requests = AlarmNotificationBuilder.makeRequests(for: alarm)
        XCTAssertEqual(requests.count, AlarmNotificationBuilder.triggerSpecs(for: alarm).count)
        XCTAssertEqual(requests.first?.content.categoryIdentifier, AlarmNotificationCategory.alarm)
    }
}

@MainActor
final class AlarmsViewModelTests: XCTestCase {
    func testSaveSchedulesEnabledAlarm() async {
        let environment = AppEnvironment.preview()
        let scheduler = environment.alarmScheduler as! AlarmSchedulerMock
        let viewModel = AlarmsViewModel(
            alarmRepository: environment.alarmRepository,
            alarmScheduler: scheduler,
            alarmAuthorization: environment.alarmAuthorization
        )

        let alarm = SleepAlarm.makeDefault(hour: 8, minute: 15)
        await viewModel.save(alarm)

        XCTAssertEqual(viewModel.alarms.count, 1)
        XCTAssertEqual(scheduler.scheduled.count, 1)
        XCTAssertEqual(scheduler.scheduled.first?.hour, 8)
    }

    func testDisableCancelsNotification() async {
        let environment = AppEnvironment.preview()
        let scheduler = environment.alarmScheduler as! AlarmSchedulerMock
        let viewModel = AlarmsViewModel(
            alarmRepository: environment.alarmRepository,
            alarmScheduler: scheduler,
            alarmAuthorization: environment.alarmAuthorization
        )

        let alarm = SleepAlarm.makeDefault()
        await viewModel.save(alarm)
        await viewModel.setEnabled(alarm, isEnabled: false)

        XCTAssertTrue(scheduler.scheduled.isEmpty)
        XCTAssertFalse(viewModel.alarms.first?.isEnabled ?? true)
    }

    func testDeleteRemovesAlarmAndCancels() async {
        let environment = AppEnvironment.preview()
        let scheduler = environment.alarmScheduler as! AlarmSchedulerMock
        let viewModel = AlarmsViewModel(
            alarmRepository: environment.alarmRepository,
            alarmScheduler: scheduler,
            alarmAuthorization: environment.alarmAuthorization
        )

        let alarm = SleepAlarm.makeDefault()
        await viewModel.save(alarm)
        await viewModel.delete(alarm)

        XCTAssertTrue(viewModel.alarms.isEmpty)
        XCTAssertTrue(scheduler.cancelledIDs.contains(alarm.id))
    }

    func testPermissionFailureSurfacesErrorButKeepsPersistence() async {
        let environment = AppEnvironment.preview()
        let scheduler = environment.alarmScheduler as! AlarmSchedulerMock
        scheduler.shouldFailPermission = true
        let viewModel = AlarmsViewModel(
            alarmRepository: environment.alarmRepository,
            alarmScheduler: scheduler,
            alarmAuthorization: environment.alarmAuthorization
        )

        let alarm = SleepAlarm.makeDefault()
        await viewModel.save(alarm)

        XCTAssertEqual(environment.alarmRepository.fetchAll().count, 1)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testRepeatSummaryWeekdays() {
        let alarm = SleepAlarm.makeDefault()
        XCTAssertEqual(AlarmsViewModel.repeatSummary(for: alarm), "Weekdays")
    }
}

@MainActor
final class AlarmEditorViewModelTests: XCTestCase {
    func testMakeAlarmUsesEditedValues() {
        let viewModel = AlarmEditorViewModel(alarm: nil)
        viewModel.hour = 5
        viewModel.minute = 45
        viewModel.label = " Early "
        viewModel.repeatDays = [1, 7]
        viewModel.sound = .chime
        viewModel.vibrationEnabled = false

        let alarm = viewModel.makeAlarm()
        XCTAssertEqual(alarm.hour, 5)
        XCTAssertEqual(alarm.minute, 45)
        XCTAssertEqual(alarm.label, "Early")
        XCTAssertEqual(alarm.repeatDays, [1, 7])
        XCTAssertEqual(alarm.sound, .chime)
        XCTAssertFalse(alarm.vibrationEnabled)
    }
}
