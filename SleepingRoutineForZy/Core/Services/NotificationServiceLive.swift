import Foundation
import UserNotifications

final class NotificationServiceLive: NotificationService {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func authorizationStatus() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
    }
}

/// Configurable notification service for previews and unit tests.
final class NotificationServiceMock: NotificationService {
    var grantResult: Bool
    var statusResult: Bool
    private(set) var requestCount = 0

    init(grantResult: Bool = true, statusResult: Bool = false) {
        self.grantResult = grantResult
        self.statusResult = statusResult
    }

    func requestAuthorization() async throws -> Bool {
        requestCount += 1
        statusResult = grantResult
        return grantResult
    }

    func authorizationStatus() async -> Bool {
        statusResult
    }
}
