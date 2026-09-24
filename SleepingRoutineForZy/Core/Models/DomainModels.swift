import Foundation

struct UserPreferences: Codable, Equatable, Sendable {
    var hasCompletedOnboarding: Bool
    var defaultSleepTimer: TimeInterval
    var preferredBedtime: DateComponents?
    var preferredWakeTime: DateComponents?
    var defaultAlarmEnabled: Bool
    var selectedSpotifyURI: String?
    var selectedSpotifyTitle: String?
    /// User explicitly opts in to upload permitted status fields to the remote Admin backend.
    var remoteMonitoringOptIn: Bool
    var lastSuccessfulCheckIn: Date?

    static let `default` = UserPreferences(
        hasCompletedOnboarding: false,
        defaultSleepTimer: 30 * 60,
        preferredBedtime: DateComponents(hour: 22, minute: 0),
        preferredWakeTime: DateComponents(hour: 7, minute: 0),
        defaultAlarmEnabled: true,
        selectedSpotifyURI: nil,
        selectedSpotifyTitle: nil,
        remoteMonitoringOptIn: false,
        lastSuccessfulCheckIn: nil
    )
}

enum MusicSource: String, Codable, Equatable, Sendable, CaseIterable {
    case spotify
    case local
    case none
}

struct SleepRoutine: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var isEnabled: Bool
    var musicSource: MusicSource
    var sleepTimerDuration: TimeInterval
    var alarmID: UUID?
    var startedAt: Date?
    var endsAt: Date?

    static func makeDefault(duration: TimeInterval = 30 * 60) -> SleepRoutine {
        SleepRoutine(
            id: UUID(),
            isEnabled: true,
            musicSource: .none,
            sleepTimerDuration: duration,
            alarmID: nil,
            startedAt: nil,
            endsAt: nil
        )
    }
}

enum Weekday: Int, Codable, CaseIterable, Sendable {
    case sunday = 1
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    var shortLabel: String {
        switch self {
        case .sunday: return String(localized: "weekday.sun", defaultValue: "S")
        case .monday: return String(localized: "weekday.mon", defaultValue: "M")
        case .tuesday: return String(localized: "weekday.tue", defaultValue: "T")
        case .wednesday: return String(localized: "weekday.wed", defaultValue: "W")
        case .thursday: return String(localized: "weekday.thu", defaultValue: "T")
        case .friday: return String(localized: "weekday.fri", defaultValue: "F")
        case .saturday: return String(localized: "weekday.sat", defaultValue: "S")
        }
    }
}

enum AlarmSound: String, Codable, CaseIterable, Sendable {
    case `default`
    case gentle
    case chime
}

struct SleepAlarm: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var hour: Int
    var minute: Int
    var repeatDays: Set<Int>
    var label: String
    var isEnabled: Bool
    var sound: AlarmSound
    var vibrationEnabled: Bool

    var timeComponents: DateComponents {
        DateComponents(hour: hour, minute: minute)
    }

    var weekdaySet: Set<Weekday> {
        Set(repeatDays.compactMap(Weekday.init(rawValue:)))
    }

    static func makeDefault(hour: Int = 7, minute: Int = 0) -> SleepAlarm {
        SleepAlarm(
            id: UUID(),
            hour: hour,
            minute: minute,
            repeatDays: [2, 3, 4, 5, 6],
            label: String(localized: "alarm.default_label", defaultValue: "Wake up"),
            isEnabled: true,
            sound: .default,
            vibrationEnabled: true
        )
    }
}

struct DeviceStatus: Codable, Equatable, Sendable {
    var batteryLevel: Double?
    var isCharging: Bool?
    var routineActive: Bool
    var routineStartedAt: Date?
    var sleepTimerEndsAt: Date?
    var spotifyConnected: Bool
    var alarmEnabled: Bool
    var nextAlarm: Date?
    var isPlayingOwnAudio: Bool
    var lastCheckIn: Date
}

struct SleepSessionRecord: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var startedAt: Date
    var musicStoppedAt: Date?
    var alarmTime: Date?
    var completedAt: Date?
    var notes: String?
}
