import Foundation
import SwiftData

@Model
final class PreferencesEntity {
    var hasCompletedOnboarding: Bool
    var defaultSleepTimer: Double
    var preferredBedtimeHour: Int?
    var preferredBedtimeMinute: Int?
    var preferredWakeHour: Int?
    var preferredWakeMinute: Int?
    var defaultAlarmEnabled: Bool
    var selectedSpotifyURI: String?
    var selectedSpotifyTitle: String?
    var remoteMonitoringOptIn: Bool = false
    var lastSuccessfulCheckIn: Date?

    init(from preferences: UserPreferences = .default) {
        self.hasCompletedOnboarding = preferences.hasCompletedOnboarding
        self.defaultSleepTimer = preferences.defaultSleepTimer
        self.preferredBedtimeHour = preferences.preferredBedtime?.hour
        self.preferredBedtimeMinute = preferences.preferredBedtime?.minute
        self.preferredWakeHour = preferences.preferredWakeTime?.hour
        self.preferredWakeMinute = preferences.preferredWakeTime?.minute
        self.defaultAlarmEnabled = preferences.defaultAlarmEnabled
        self.selectedSpotifyURI = preferences.selectedSpotifyURI
        self.selectedSpotifyTitle = preferences.selectedSpotifyTitle
        self.remoteMonitoringOptIn = preferences.remoteMonitoringOptIn
        self.lastSuccessfulCheckIn = preferences.lastSuccessfulCheckIn
    }

    func apply(_ preferences: UserPreferences) {
        hasCompletedOnboarding = preferences.hasCompletedOnboarding
        defaultSleepTimer = preferences.defaultSleepTimer
        preferredBedtimeHour = preferences.preferredBedtime?.hour
        preferredBedtimeMinute = preferences.preferredBedtime?.minute
        preferredWakeHour = preferences.preferredWakeTime?.hour
        preferredWakeMinute = preferences.preferredWakeTime?.minute
        defaultAlarmEnabled = preferences.defaultAlarmEnabled
        selectedSpotifyURI = preferences.selectedSpotifyURI
        selectedSpotifyTitle = preferences.selectedSpotifyTitle
        remoteMonitoringOptIn = preferences.remoteMonitoringOptIn
        lastSuccessfulCheckIn = preferences.lastSuccessfulCheckIn
    }

    func toDomain() -> UserPreferences {
        var bedtime: DateComponents?
        if let hour = preferredBedtimeHour, let minute = preferredBedtimeMinute {
            bedtime = DateComponents(hour: hour, minute: minute)
        }
        var wake: DateComponents?
        if let hour = preferredWakeHour, let minute = preferredWakeMinute {
            wake = DateComponents(hour: hour, minute: minute)
        }
        return UserPreferences(
            hasCompletedOnboarding: hasCompletedOnboarding,
            defaultSleepTimer: defaultSleepTimer,
            preferredBedtime: bedtime,
            preferredWakeTime: wake,
            defaultAlarmEnabled: defaultAlarmEnabled,
            selectedSpotifyURI: selectedSpotifyURI,
            selectedSpotifyTitle: selectedSpotifyTitle,
            remoteMonitoringOptIn: remoteMonitoringOptIn,
            lastSuccessfulCheckIn: lastSuccessfulCheckIn
        )
    }
}

@Model
final class SleepRoutineEntity {
    @Attribute(.unique) var id: UUID
    var isEnabled: Bool
    var musicSourceRaw: String
    var sleepTimerDuration: Double
    var alarmID: UUID?
    var startedAt: Date?
    var endsAt: Date?

    init(from routine: SleepRoutine) {
        self.id = routine.id
        self.isEnabled = routine.isEnabled
        self.musicSourceRaw = routine.musicSource.rawValue
        self.sleepTimerDuration = routine.sleepTimerDuration
        self.alarmID = routine.alarmID
        self.startedAt = routine.startedAt
        self.endsAt = routine.endsAt
    }

    func apply(_ routine: SleepRoutine) {
        isEnabled = routine.isEnabled
        musicSourceRaw = routine.musicSource.rawValue
        sleepTimerDuration = routine.sleepTimerDuration
        alarmID = routine.alarmID
        startedAt = routine.startedAt
        endsAt = routine.endsAt
    }

    func toDomain() -> SleepRoutine {
        SleepRoutine(
            id: id,
            isEnabled: isEnabled,
            musicSource: MusicSource(rawValue: musicSourceRaw) ?? .none,
            sleepTimerDuration: sleepTimerDuration,
            alarmID: alarmID,
            startedAt: startedAt,
            endsAt: endsAt
        )
    }
}

@Model
final class SleepAlarmEntity {
    @Attribute(.unique) var id: UUID
    var hour: Int
    var minute: Int
    var repeatDaysData: Data
    var label: String
    var isEnabled: Bool
    var soundRaw: String
    var vibrationEnabled: Bool

    init(from alarm: SleepAlarm) {
        self.id = alarm.id
        self.hour = alarm.hour
        self.minute = alarm.minute
        self.repeatDaysData = (try? JSONEncoder().encode(Array(alarm.repeatDays))) ?? Data()
        self.label = alarm.label
        self.isEnabled = alarm.isEnabled
        self.soundRaw = alarm.sound.rawValue
        self.vibrationEnabled = alarm.vibrationEnabled
    }

    func apply(_ alarm: SleepAlarm) {
        hour = alarm.hour
        minute = alarm.minute
        repeatDaysData = (try? JSONEncoder().encode(Array(alarm.repeatDays))) ?? Data()
        label = alarm.label
        isEnabled = alarm.isEnabled
        soundRaw = alarm.sound.rawValue
        vibrationEnabled = alarm.vibrationEnabled
    }

    func toDomain() -> SleepAlarm {
        let days = (try? JSONDecoder().decode([Int].self, from: repeatDaysData)) ?? []
        return SleepAlarm(
            id: id,
            hour: hour,
            minute: minute,
            repeatDays: Set(days),
            label: label,
            isEnabled: isEnabled,
            sound: AlarmSound(rawValue: soundRaw) ?? .default,
            vibrationEnabled: vibrationEnabled
        )
    }
}

@Model
final class SleepSessionEntity {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var musicStoppedAt: Date?
    var alarmTime: Date?
    var completedAt: Date?
    var notes: String?

    init(from record: SleepSessionRecord) {
        self.id = record.id
        self.startedAt = record.startedAt
        self.musicStoppedAt = record.musicStoppedAt
        self.alarmTime = record.alarmTime
        self.completedAt = record.completedAt
        self.notes = record.notes
    }

    func toDomain() -> SleepSessionRecord {
        SleepSessionRecord(
            id: id,
            startedAt: startedAt,
            musicStoppedAt: musicStoppedAt,
            alarmTime: alarmTime,
            completedAt: completedAt,
            notes: notes
        )
    }
}
