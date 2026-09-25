import Foundation
import UserNotifications

/// Schedules a daily local notification at preferred bedtime (not AlarmKit).
enum BedtimeReminderScheduler {
    static let identifier = "bedtime-reminder"

    static func sync(
        hour: Int,
        minute: Int,
        enabled: Bool,
        center: UNUserNotificationCenter = .current()
    ) async {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard enabled else { return }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized ||
                settings.authorizationStatus == .provisional else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "bedtime.reminder.title", defaultValue: "Bedtime")
        content.body = String(
            localized: "bedtime.reminder.body",
            defaultValue: "Time for your sleep routine"
        )
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await center.add(request)
    }

    static func sync(from preferences: UserPreferences) async {
        let hour = preferences.preferredBedtime?.hour ?? 22
        let minute = preferences.preferredBedtime?.minute ?? 0
        await sync(hour: hour, minute: minute, enabled: preferences.bedtimeReminderEnabled)
    }
}
