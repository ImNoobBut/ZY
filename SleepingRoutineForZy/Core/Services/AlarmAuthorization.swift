import Foundation
#if canImport(AlarmKit)
import AlarmKit
#endif

/// Abstracts alarm permission so UI does not import AlarmKit directly.
protocol AlarmAuthorizationService: AnyObject {
    /// True when this build/device uses AlarmKit (iOS 26+) instead of local notifications.
    var usesAlarmKit: Bool { get }
    func requestAuthorization() async throws -> Bool
    func authorizationStatus() async -> Bool
}

final class AlarmAuthorizationServiceLive: AlarmAuthorizationService {
    private let notificationService: any NotificationService

    init(notificationService: any NotificationService) {
        self.notificationService = notificationService
    }

    var usesAlarmKit: Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }

    func requestAuthorization() async throws -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            return try await requestAlarmKitAuthorization()
        }
        #endif
        return try await notificationService.requestAuthorization()
    }

    func authorizationStatus() async -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            return AlarmManager.shared.authorizationState == .authorized
        }
        #endif
        return await notificationService.authorizationStatus()
    }

    #if canImport(AlarmKit)
    @available(iOS 26.0, *)
    private func requestAlarmKitAuthorization() async throws -> Bool {
        switch AlarmManager.shared.authorizationState {
        case .authorized:
            return true
        case .denied:
            return false
        case .notDetermined:
            let state = try await AlarmManager.shared.requestAuthorization()
            return state == .authorized
        @unknown default:
            return false
        }
    }
    #endif
}

final class AlarmAuthorizationServiceMock: AlarmAuthorizationService {
    var usesAlarmKit: Bool
    var grantResult: Bool
    var statusResult: Bool
    private(set) var requestCount = 0

    init(usesAlarmKit: Bool = false, grantResult: Bool = true, statusResult: Bool = true) {
        self.usesAlarmKit = usesAlarmKit
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
