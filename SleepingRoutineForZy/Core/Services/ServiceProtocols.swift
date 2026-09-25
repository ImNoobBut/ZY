import Foundation
#if canImport(UIKit)
import UIKit
#endif

struct SpotifyUser: Equatable, Sendable {
    let id: String
    let displayName: String
}

struct SpotifyTrack: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let artistName: String
    let uri: String
}

struct SpotifyPlaylist: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let trackCount: Int
    let uri: String
    let imageURL: URL?
}

protocol SpotifyService: AnyObject {
    var isAuthenticated: Bool { get }
    func authenticate() async throws
    func logout() async throws
    func getCurrentUser() async throws -> SpotifyUser
    func search(query: String) async throws -> [SpotifyTrack]
    func getPlaylists() async throws -> [SpotifyPlaylist]
    func getPlaylistTracks(playlistID: String) async throws -> [SpotifyTrack]
    func listDeviceNames() async throws -> [String]
    func play(uri: String) async throws
    func pause() async throws
}

protocol NotificationService: AnyObject {
    func requestAuthorization() async throws -> Bool
    func authorizationStatus() async -> Bool
}

final class NotificationServiceStub: NotificationService {
    func requestAuthorization() async throws -> Bool { false }
    func authorizationStatus() async -> Bool { false }
}

enum BatteryState: String, Codable, Sendable {
    case unknown
    case unplugged
    case charging
    case full
}

protocol DeviceStatusService: AnyObject {
    var batteryLevel: Float { get }
    var batteryState: BatteryState { get }
    func currentStatus(
        routineActive: Bool,
        routineStartedAt: Date?,
        sleepTimerEndsAt: Date?,
        spotifyConnected: Bool,
        alarmEnabled: Bool,
        nextAlarm: Date?,
        isPlayingOwnAudio: Bool,
        preferredBedtime: String?,
        currentStreak: Int?
    ) -> DeviceStatus
}

final class DeviceStatusServiceLive: DeviceStatusService {
    var batteryLevel: Float {
        readBatteryLevel()
    }

    var batteryState: BatteryState {
        readBatteryState()
    }

    func currentStatus(
        routineActive: Bool,
        routineStartedAt: Date?,
        sleepTimerEndsAt: Date?,
        spotifyConnected: Bool,
        alarmEnabled: Bool,
        nextAlarm: Date?,
        isPlayingOwnAudio: Bool,
        preferredBedtime: String? = nil,
        currentStreak: Int? = nil
    ) -> DeviceStatus {
        let state = batteryState
        let level = batteryLevel
        return DeviceStatus(
            batteryLevel: level >= 0 ? Double(level) : nil,
            isCharging: state == .charging || state == .full,
            routineActive: routineActive,
            routineStartedAt: routineStartedAt,
            sleepTimerEndsAt: sleepTimerEndsAt,
            spotifyConnected: spotifyConnected,
            alarmEnabled: alarmEnabled,
            nextAlarm: nextAlarm,
            isPlayingOwnAudio: isPlayingOwnAudio,
            lastCheckIn: Date(),
            preferredBedtime: preferredBedtime,
            currentStreak: currentStreak
        )
    }

    private func readBatteryLevel() -> Float {
        #if os(iOS)
        enableBatteryMonitoring()
        return UIDevice.current.batteryLevel
        #else
        return -1
        #endif
    }

    private func readBatteryState() -> BatteryState {
        #if os(iOS)
        enableBatteryMonitoring()
        switch UIDevice.current.batteryState {
        case .unknown: return .unknown
        case .unplugged: return .unplugged
        case .charging: return .charging
        case .full: return .full
        @unknown default: return .unknown
        }
        #else
        return .unknown
        #endif
    }

    private func enableBatteryMonitoring() {
        #if os(iOS)
        if !UIDevice.current.isBatteryMonitoringEnabled {
            UIDevice.current.isBatteryMonitoringEnabled = true
        }
        #endif
    }
}

protocol StatusCheckInService: AnyObject {
    var isRegistered: Bool { get }
    var pairingCode: String? { get }
    var deviceId: String? { get }

    func registerDevice(displayName: String) async throws
    func checkIn(_ status: DeviceStatus) async throws
    func clearRegistration() async throws
}

/// Records check-ins for previews/tests. Does not call the network.
final class StatusCheckInServiceStub: StatusCheckInService {
    let configuration: AppConfiguration
    private(set) var lastCheckIn: DeviceStatus?
    private(set) var registeredDeviceId: String?
    private(set) var storedPairingCode: String?
    var shouldFailNetwork = false

    init(configuration: AppConfiguration) {
        self.configuration = configuration
    }

    var isRegistered: Bool { registeredDeviceId != nil }
    var pairingCode: String? { storedPairingCode }
    var deviceId: String? { registeredDeviceId }

    func registerDevice(displayName: String) async throws {
        _ = displayName
        if shouldFailNetwork { throw SleepRoutineError.adminBackendUnavailable }
        registeredDeviceId = UUID().uuidString
        storedPairingCode = String(format: "%06d", Int.random(in: 0...999_999))
    }

    func checkIn(_ status: DeviceStatus) async throws {
        if shouldFailNetwork { throw SleepRoutineError.networkUnavailable }
        guard isRegistered else { throw SleepRoutineError.adminNotRegistered }
        lastCheckIn = status
    }

    func clearRegistration() async throws {
        registeredDeviceId = nil
        storedPairingCode = nil
        lastCheckIn = nil
    }
}
