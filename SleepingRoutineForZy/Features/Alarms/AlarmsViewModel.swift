import Foundation
import Observation

@Observable
final class AlarmsViewModel {
    private(set) var alarms: [SleepAlarm] = []
    var errorMessage: String?
    var infoMessage: String?
    var notificationsAllowed: Bool?

    private let alarmRepository: any AlarmRepository
    private let alarmScheduler: any AlarmScheduler
    private let alarmAuthorization: any AlarmAuthorizationService

    var usesAlarmKit: Bool { alarmAuthorization.usesAlarmKit }

    init(
        alarmRepository: any AlarmRepository,
        alarmScheduler: any AlarmScheduler,
        alarmAuthorization: any AlarmAuthorizationService
    ) {
        self.alarmRepository = alarmRepository
        self.alarmScheduler = alarmScheduler
        self.alarmAuthorization = alarmAuthorization
    }

    @MainActor
    func refresh() async {
        alarms = alarmRepository.fetchAll()
        notificationsAllowed = await alarmAuthorization.authorizationStatus()
        infoMessage = nil
        errorMessage = nil
    }

    @MainActor
    func requestPermissionIfNeeded() async {
        do {
            let granted = try await alarmAuthorization.requestAuthorization()
            notificationsAllowed = granted
            if !granted {
                errorMessage = SleepRoutineError.notificationPermissionDenied.errorDescription
            }
        } catch {
            notificationsAllowed = false
            errorMessage = SleepRoutineError.notificationPermissionDenied.errorDescription
        }
    }

    @MainActor
    func setEnabled(_ alarm: SleepAlarm, isEnabled: Bool) async {
        var updated = alarm
        updated.isEnabled = isEnabled
        await save(updated, successInfo: isEnabled
            ? String(localized: "alarms.enabled", defaultValue: "Alarm on")
            : String(localized: "alarms.disabled", defaultValue: "Alarm off — schedule removed"))
    }

    @MainActor
    func save(_ alarm: SleepAlarm, successInfo: String? = nil) async {
        errorMessage = nil
        infoMessage = nil
        do {
            try alarmRepository.save(alarm)
            try await alarmScheduler.schedule(alarm)
            alarms = alarmRepository.fetchAll()
            infoMessage = successInfo
            notificationsAllowed = await alarmAuthorization.authorizationStatus()
        } catch let error as SleepRoutineError {
            // Persist even if scheduling fails so the user doesn't lose edits; surface recovery.
            try? alarmRepository.save(alarm)
            alarms = alarmRepository.fetchAll()
            errorMessage = error.errorDescription
        } catch {
            errorMessage = SleepRoutineError.persistenceFailed.errorDescription
        }
    }

    @MainActor
    func delete(_ alarm: SleepAlarm) async {
        errorMessage = nil
        await alarmScheduler.cancel(alarmID: alarm.id)
        do {
            try alarmRepository.delete(id: alarm.id)
            alarms = alarmRepository.fetchAll()
        } catch {
            errorMessage = SleepRoutineError.persistenceFailed.errorDescription
        }
    }

    @MainActor
    func reconcileScheduledNotifications() async {
        do {
            try await alarmScheduler.reconcile(alarms: alarmRepository.fetchAll())
        } catch let error as SleepRoutineError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = SleepRoutineError.alarmSchedulingFailed.errorDescription
        }
    }

    static func repeatSummary(for alarm: SleepAlarm) -> String {
        let days = alarm.weekdaySet.sorted { $0.rawValue < $1.rawValue }
        if days.isEmpty {
            return String(localized: "alarms.repeat.once", defaultValue: "Once")
        }
        if days.map(\.rawValue) == [2, 3, 4, 5, 6] {
            return String(localized: "alarms.repeat.weekdays", defaultValue: "Weekdays")
        }
        if days.count == 7 {
            return String(localized: "alarms.repeat.every_day", defaultValue: "Every day")
        }
        return days.map(\.shortLabel).joined(separator: " ")
    }

    static func timeText(for alarm: SleepAlarm) -> String {
        SleepRoutineController.formatTime(hour: alarm.hour, minute: alarm.minute)
    }
}

@Observable
final class AlarmEditorViewModel {
    var hour: Int
    var minute: Int
    var label: String
    var repeatDays: Set<Int>
    var sound: AlarmSound
    var vibrationEnabled: Bool
    var isEnabled: Bool

    let alarmID: UUID
    let isNew: Bool

    init(alarm: SleepAlarm?) {
        if let alarm {
            alarmID = alarm.id
            hour = alarm.hour
            minute = alarm.minute
            label = alarm.label
            repeatDays = alarm.repeatDays
            sound = alarm.sound
            vibrationEnabled = alarm.vibrationEnabled
            isEnabled = alarm.isEnabled
            isNew = false
        } else {
            let defaults = SleepAlarm.makeDefault()
            alarmID = defaults.id
            hour = defaults.hour
            minute = defaults.minute
            label = defaults.label
            repeatDays = defaults.repeatDays
            sound = defaults.sound
            vibrationEnabled = defaults.vibrationEnabled
            isEnabled = true
            isNew = true
        }
    }

    var timeDate: Date {
        get {
            var components = DateComponents()
            components.hour = hour
            components.minute = minute
            return Calendar.current.date(from: components) ?? Date()
        }
        set {
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            hour = components.hour ?? hour
            minute = components.minute ?? minute
        }
    }

    func toggleDay(_ weekday: Weekday) {
        if repeatDays.contains(weekday.rawValue) {
            repeatDays.remove(weekday.rawValue)
        } else {
            repeatDays.insert(weekday.rawValue)
        }
    }

    func makeAlarm() -> SleepAlarm {
        SleepAlarm(
            id: alarmID,
            hour: hour,
            minute: minute,
            repeatDays: repeatDays,
            label: label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? String(localized: "alarm.default_label", defaultValue: "Wake up")
                : label.trimmingCharacters(in: .whitespacesAndNewlines),
            isEnabled: isEnabled,
            sound: sound,
            vibrationEnabled: vibrationEnabled
        )
    }
}
