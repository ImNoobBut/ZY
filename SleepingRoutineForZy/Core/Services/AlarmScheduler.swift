import Foundation
import UserNotifications

enum AlarmNotificationCategory {
    static let alarm = "alarm"
}

enum AlarmNotificationBuilder {
    static func requestIdentifier(alarmID: UUID, weekday: Int?) -> String {
        if let weekday {
            return "alarm-\(alarmID.uuidString)-weekday-\(weekday)"
        }
        return "alarm-\(alarmID.uuidString)"
    }

    static func allIdentifiers(for alarm: SleepAlarm) -> [String] {
        if alarm.repeatDays.isEmpty {
            return [requestIdentifier(alarmID: alarm.id, weekday: nil)]
        }
        return alarm.repeatDays.sorted().map { requestIdentifier(alarmID: alarm.id, weekday: $0) }
    }

    /// Builds calendar triggers. Repeating weekdays use one request per weekday.
    static func triggerSpecs(for alarm: SleepAlarm) -> [(identifier: String, components: DateComponents, repeats: Bool)] {
        guard alarm.isEnabled else { return [] }

        if alarm.repeatDays.isEmpty {
            return [(
                requestIdentifier(alarmID: alarm.id, weekday: nil),
                DateComponents(hour: alarm.hour, minute: alarm.minute),
                false
            )]
        }

        return alarm.repeatDays.sorted().map { weekday in
            (
                requestIdentifier(alarmID: alarm.id, weekday: weekday),
                DateComponents(hour: alarm.hour, minute: alarm.minute, weekday: weekday),
                true
            )
        }
    }

    static func content(for alarm: SleepAlarm) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = alarm.label.isEmpty
            ? String(localized: "alarm.default_label", defaultValue: "Wake up")
            : alarm.label
        content.body = String(
            localized: "alarm.notification.body",
            defaultValue: "It’s time to wake up. This reminder uses an iOS notification, not Apple Clock."
        )
        content.sound = sound(for: alarm.sound)
        content.categoryIdentifier = AlarmNotificationCategory.alarm
        content.userInfo = [
            "alarmID": alarm.id.uuidString,
            "vibrationEnabled": alarm.vibrationEnabled
        ]
        return content
    }

    static func sound(for alarmSound: AlarmSound) -> UNNotificationSound {
        switch alarmSound {
        case .default, .gentle, .chime:
            // Custom bundled sounds can be added later; system default is the supported path for v1.
            return .default
        }
    }

    static func makeRequests(for alarm: SleepAlarm) -> [UNNotificationRequest] {
        triggerSpecs(for: alarm).map { spec in
            let trigger = UNCalendarNotificationTrigger(dateMatching: spec.components, repeats: spec.repeats)
            return UNNotificationRequest(identifier: spec.identifier, content: content(for: alarm), trigger: trigger)
        }
    }
}

protocol AlarmScheduler: AnyObject {
    func schedule(_ alarm: SleepAlarm) async throws
    func cancel(alarmID: UUID) async
    func reconcile(alarms: [SleepAlarm]) async throws
}

final class AlarmSchedulerLive: AlarmScheduler {
    private let center: UNUserNotificationCenter
    private let notificationService: any NotificationService

    init(
        center: UNUserNotificationCenter = .current(),
        notificationService: any NotificationService
    ) {
        self.center = center
        self.notificationService = notificationService
        Self.registerCategories(center: center)
    }

    func schedule(_ alarm: SleepAlarm) async throws {
        await cancel(alarmID: alarm.id)
        guard alarm.isEnabled else { return }

        let authorized = await notificationService.authorizationStatus()
        if !authorized {
            let granted = try await notificationService.requestAuthorization()
            guard granted else {
                throw SleepRoutineError.notificationPermissionDenied
            }
        }

        let requests = AlarmNotificationBuilder.makeRequests(for: alarm)
        for request in requests {
            do {
                try await center.add(request)
            } catch {
                throw SleepRoutineError.alarmSchedulingFailed
            }
        }
    }

    func cancel(alarmID: UUID) async {
        let pending = await center.pendingNotificationRequests()
        let prefix = "alarm-\(alarmID.uuidString)"
        let matching = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: matching)
        center.removeDeliveredNotifications(withIdentifiers: matching)
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

    private static func registerCategories(center: UNUserNotificationCenter) {
        let category = UNNotificationCategory(
            identifier: AlarmNotificationCategory.alarm,
            actions: [],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        center.setNotificationCategories([category])
    }
}

final class AlarmSchedulerMock: AlarmScheduler {
    private(set) var scheduled: [SleepAlarm] = []
    private(set) var cancelledIDs: [UUID] = []
    var shouldFailPermission = false
    var shouldFailSchedule = false

    func schedule(_ alarm: SleepAlarm) async throws {
        if shouldFailPermission {
            throw SleepRoutineError.notificationPermissionDenied
        }
        if shouldFailSchedule {
            throw SleepRoutineError.alarmSchedulingFailed
        }
        scheduled.removeAll { $0.id == alarm.id }
        if alarm.isEnabled {
            scheduled.append(alarm)
        }
        cancelledIDs.removeAll { $0 == alarm.id }
    }

    func cancel(alarmID: UUID) async {
        scheduled.removeAll { $0.id == alarmID }
        cancelledIDs.append(alarmID)
    }

    func reconcile(alarms: [SleepAlarm]) async throws {
        scheduled = alarms.filter(\.isEnabled)
        for alarm in alarms where !alarm.isEnabled {
            cancelledIDs.append(alarm.id)
        }
    }
}
