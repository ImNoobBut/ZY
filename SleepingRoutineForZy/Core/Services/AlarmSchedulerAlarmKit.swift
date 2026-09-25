import Foundation
import SwiftUI
#if canImport(AlarmKit)
import AlarmKit

/// Empty metadata required by AlarmKit's generic `AlarmAttributes`.
nonisolated struct SleepAlarmMetadata: AlarmMetadata {}

/// Schedules wake alarms via AlarmKit (iOS 26+). Older OS uses `AlarmSchedulerLive`.
@available(iOS 26.0, *)
final class AlarmSchedulerAlarmKit: AlarmScheduler {
    private let manager = AlarmManager.shared

    func schedule(_ alarm: SleepAlarm) async throws {
        try await cancel(alarmID: alarm.id)
        guard alarm.isEnabled else { return }

        guard try await ensureAuthorized() else {
            throw SleepRoutineError.notificationPermissionDenied
        }

        let titleText = alarm.label.isEmpty
            ? String(localized: "alarm.default_label", defaultValue: "Wake up")
            : alarm.label
        let stopButton = AlarmButton(
            text: "Dismiss",
            textColor: .white,
            systemImageName: "stop.circle"
        )
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: titleText),
            stopButton: stopButton
        )
        let attributes = AlarmAttributes<SleepAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: SleepAlarmMetadata(),
            tintColor: Color(red: 0.45, green: 0.62, blue: 0.95)
        )
        let schedule = Self.makeSchedule(for: alarm)
        let configuration = AlarmManager.AlarmConfiguration<SleepAlarmMetadata>.alarm(
            schedule: schedule,
            attributes: attributes
        )

        do {
            _ = try await manager.schedule(id: alarm.id, configuration: configuration)
        } catch {
            throw SleepRoutineError.alarmSchedulingFailed
        }
    }

    func cancel(alarmID: UUID) async {
        try? manager.cancel(id: alarmID)
    }

    func reconcile(alarms: [SleepAlarm]) async throws {
        for alarm in alarms {
            if alarm.isEnabled {
                try await schedule(alarm)
            } else {
                await cancel(alarmID: alarm.id)
            }
        }
    }

    private func ensureAuthorized() async throws -> Bool {
        switch manager.authorizationState {
        case .authorized:
            return true
        case .denied:
            return false
        case .notDetermined:
            let state = try await manager.requestAuthorization()
            return state == .authorized
        @unknown default:
            return false
        }
    }

    private static func makeSchedule(for alarm: SleepAlarm) -> Alarm.Schedule {
        let time = Alarm.Schedule.Relative.Time(hour: alarm.hour, minute: alarm.minute)
        let repeats: Alarm.Schedule.Relative.Recurrence
        if alarm.repeatDays.isEmpty {
            repeats = .never
        } else {
            let weekdays = alarm.repeatDays.compactMap(localeWeekday(fromCalendarWeekday:))
            repeats = weekdays.isEmpty ? .never : .weekly(weekdays)
        }
        return .relative(Alarm.Schedule.Relative(time: time, repeats: repeats))
    }

    /// Maps Foundation calendar weekday (1 = Sunday … 7 = Saturday) to `Locale.Weekday`.
    private static func localeWeekday(fromCalendarWeekday value: Int) -> Locale.Weekday? {
        switch value {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        case 7: return .saturday
        default: return nil
        }
    }
}

#endif

enum AlarmSchedulerFactory {
    static func make(notificationService: any NotificationService) -> any AlarmScheduler {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            return AlarmSchedulerAlarmKit()
        }
        #endif
        return AlarmSchedulerLive(notificationService: notificationService)
    }
}
