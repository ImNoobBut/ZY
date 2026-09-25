import Foundation
import Observation

/// Builds opted-in device status and performs opportunistic remote check-ins.
@Observable
@MainActor
final class AdminMonitoringController {
    private(set) var latestStatus: DeviceStatus?
    private(set) var lastError: SleepRoutineError?
    private(set) var isBusy = false

    private let preferencesRepository: any PreferencesRepository
    private let routineRepository: any RoutineRepository
    private let alarmRepository: any AlarmRepository
    private let deviceStatusService: any DeviceStatusService
    private let statusCheckInService: any StatusCheckInService
    private let spotifyService: any SpotifyService
    private let audioService: any AudioService
    private let routineController: SleepRoutineController
    private let credentialStore: any AdminCredentialStore

    init(
        preferencesRepository: any PreferencesRepository,
        routineRepository: any RoutineRepository,
        alarmRepository: any AlarmRepository,
        deviceStatusService: any DeviceStatusService,
        statusCheckInService: any StatusCheckInService,
        spotifyService: any SpotifyService,
        audioService: any AudioService,
        routineController: SleepRoutineController,
        credentialStore: any AdminCredentialStore
    ) {
        self.preferencesRepository = preferencesRepository
        self.routineRepository = routineRepository
        self.alarmRepository = alarmRepository
        self.deviceStatusService = deviceStatusService
        self.statusCheckInService = statusCheckInService
        self.spotifyService = spotifyService
        self.audioService = audioService
        self.routineController = routineController
        self.credentialStore = credentialStore
    }

    var isOptedIn: Bool {
        preferencesRepository.load().remoteMonitoringOptIn
    }

    var isRegistered: Bool {
        statusCheckInService.isRegistered
    }

    var pairingCode: String? {
        statusCheckInService.pairingCode
    }

    var hasPIN: Bool {
        credentialStore.hasPIN()
    }

    var lastSuccessfulCheckIn: Date? {
        preferencesRepository.load().lastSuccessfulCheckIn
    }

    func buildCurrentStatus(now: Date = Date()) -> DeviceStatus {
        let routine = routineRepository.loadActiveRoutine()
        let alarm = alarmRepository.fetchAll().first(where: \.isEnabled)
        let nextAlarm = Self.nextAlarmDate(for: alarm, from: now)
        let preferences = preferencesRepository.load()
        let status = deviceStatusService.currentStatus(
            routineActive: routineController.isRoutineActive,
            routineStartedAt: routine?.startedAt,
            sleepTimerEndsAt: routine?.endsAt,
            spotifyConnected: spotifyService.isAuthenticated,
            alarmEnabled: alarm != nil,
            nextAlarm: nextAlarm,
            isPlayingOwnAudio: audioService.isPlaying,
            preferredBedtime: preferences.preferredBedtimeLabel,
            currentStreak: routineController.currentStreak
        )
        latestStatus = status
        return status
    }

    func setOptIn(_ enabled: Bool) throws {
        var preferences = preferencesRepository.load()
        preferences.remoteMonitoringOptIn = enabled
        try preferencesRepository.save(preferences)
        if !enabled {
            lastError = nil
        }
    }

    func registerIfNeeded(displayName: String = "Zy iPhone") async {
        guard isOptedIn else {
            lastError = .adminNotOptedIn
            return
        }
        if statusCheckInService.isRegistered { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await statusCheckInService.registerDevice(displayName: displayName)
            lastError = nil
        } catch let error as SleepRoutineError {
            lastError = error
        } catch {
            lastError = .adminBackendUnavailable
        }
    }

    func checkInIfNeeded() async {
        guard isOptedIn else { return }
        guard statusCheckInService.isRegistered else { return }

        isBusy = true
        defer { isBusy = false }

        let status = buildCurrentStatus()
        do {
            try await statusCheckInService.checkIn(status)
            var preferences = preferencesRepository.load()
            preferences.lastSuccessfulCheckIn = status.lastCheckIn
            try preferencesRepository.save(preferences)
            lastError = nil
        } catch let error as SleepRoutineError {
            lastError = error
        } catch {
            lastError = .networkUnavailable
        }
    }

    func disconnectRemote() async {
        isBusy = true
        defer { isBusy = false }
        try? await statusCheckInService.clearRegistration()
        try? setOptIn(false)
        var preferences = preferencesRepository.load()
        preferences.lastSuccessfulCheckIn = nil
        try? preferencesRepository.save(preferences)
        latestStatus = nil
        lastError = nil
    }

    func setPIN(_ pin: String) throws {
        try credentialStore.setPIN(pin)
    }

    func unlock(with pin: String) throws -> Bool {
        let ok = try credentialStore.verifyPIN(pin)
        if !ok { throw SleepRoutineError.adminPINIncorrect }
        return true
    }

    static func nextAlarmDate(for alarm: SleepAlarm?, from now: Date, calendar: Calendar = .current) -> Date? {
        guard let alarm else { return nil }
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = alarm.hour
        components.minute = alarm.minute
        components.second = 0
        guard let today = calendar.date(from: components) else { return nil }
        if today > now { return today }
        return calendar.date(byAdding: .day, value: 1, to: today)
    }
}
