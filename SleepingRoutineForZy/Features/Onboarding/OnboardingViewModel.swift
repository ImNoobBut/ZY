import Foundation
import Observation

enum OnboardingStep: Int, CaseIterable, Equatable {
    case welcome
    case alarms
    case spotify
    case preferences
}

@Observable
final class OnboardingViewModel {
    private(set) var step: OnboardingStep = .welcome
    var defaultSleepTimerMinutes: Int = 30
    var defaultAlarmEnabled: Bool = true
    var bedtime: Date
    var wakeTime: Date
    var notificationGranted: Bool?
    var isRequestingPermission = false
    var isConnectingSpotify = false
    var isSaving = false
    var spotifyStatusMessage: String?
    var errorMessage: String?

    let timerChoices = SleepTimerPreset.allCases.map(\.rawValue)

    private let preferencesRepository: any PreferencesRepository
    private let alarmRepository: any AlarmRepository
    private let alarmAuthorization: any AlarmAuthorizationService
    private let spotifyService: any SpotifyService
    private let alarmScheduler: (any AlarmScheduler)?
    private let calendar: Calendar

    init(
        preferencesRepository: any PreferencesRepository,
        alarmRepository: any AlarmRepository,
        alarmAuthorization: any AlarmAuthorizationService,
        spotifyService: any SpotifyService,
        alarmScheduler: (any AlarmScheduler)? = nil,
        calendar: Calendar = .current,
        now: Date = Date()
    ) {
        self.preferencesRepository = preferencesRepository
        self.alarmRepository = alarmRepository
        self.alarmAuthorization = alarmAuthorization
        self.spotifyService = spotifyService
        self.alarmScheduler = alarmScheduler
        self.calendar = calendar

        let existing = preferencesRepository.load()
        defaultSleepTimerMinutes = max(1, Int(existing.defaultSleepTimer / 60))
        defaultAlarmEnabled = existing.defaultAlarmEnabled
        bedtime = Self.date(from: existing.preferredBedtime, fallbackHour: 22, fallbackMinute: 0, calendar: calendar, now: now)
        wakeTime = Self.date(from: existing.preferredWakeTime, fallbackHour: 7, fallbackMinute: 0, calendar: calendar, now: now)
    }

    var usesAlarmKit: Bool { alarmAuthorization.usesAlarmKit }

    var canGoBack: Bool {
        step != .welcome
    }

    func goNext() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        step = next
        errorMessage = nil
    }

    func goBack() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = previous
        errorMessage = nil
    }

    @MainActor
    func requestAlarmPermission() async {
        isRequestingPermission = true
        errorMessage = nil
        defer { isRequestingPermission = false }

        do {
            let granted = try await alarmAuthorization.requestAuthorization()
            notificationGranted = granted
            if !granted {
                errorMessage = SleepRoutineError.notificationPermissionDenied.errorDescription
            }
        } catch {
            notificationGranted = false
            errorMessage = SleepRoutineError.notificationPermissionDenied.errorDescription
        }
    }

    /// Legacy name used by older call sites / tests.
    @MainActor
    func requestNotificationPermission() async {
        await requestAlarmPermission()
    }

    @MainActor
    func connectSpotify() async {
        isConnectingSpotify = true
        spotifyStatusMessage = nil
        errorMessage = nil
        defer { isConnectingSpotify = false }

        do {
            try await spotifyService.authenticate()
            spotifyStatusMessage = String(
                localized: "onboarding.spotify.connected",
                defaultValue: "Spotify is connected."
            )
            goNext()
        } catch let error as SleepRoutineError {
            spotifyStatusMessage = error.errorDescription
        } catch {
            spotifyStatusMessage = SleepRoutineError.spotifyNotConnected.errorDescription
        }
    }

    func skipSpotify() {
        spotifyStatusMessage = String(
            localized: "onboarding.spotify.skipped",
            defaultValue: "You can connect Spotify later in Settings."
        )
        goNext()
    }

    /// Persists preferences (and optional default alarm) and marks onboarding complete.
    @MainActor
    func finish() async throws -> UserPreferences {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let minutes = min(max(defaultSleepTimerMinutes, 1), 180)
        let bedtimeComponents = calendar.dateComponents([.hour, .minute], from: bedtime)
        let wakeComponents = calendar.dateComponents([.hour, .minute], from: wakeTime)

        var preferences = preferencesRepository.load()
        preferences.hasCompletedOnboarding = true
        preferences.defaultSleepTimer = TimeInterval(minutes * 60)
        preferences.preferredBedtime = bedtimeComponents
        preferences.preferredWakeTime = wakeComponents
        preferences.defaultAlarmEnabled = defaultAlarmEnabled
        preferences.bedtimeReminderEnabled = true

        do {
            try preferencesRepository.save(preferences)
        } catch {
            throw SleepRoutineError.persistenceFailed
        }

        if defaultAlarmEnabled {
            try await saveDefaultAlarmIfNeeded(wakeComponents: wakeComponents)
        }

        await BedtimeReminderScheduler.sync(from: preferences)

        return preferences
    }

    private func saveDefaultAlarmIfNeeded(wakeComponents: DateComponents) async throws {
        guard alarmRepository.fetchAll().isEmpty else { return }
        guard let hour = wakeComponents.hour, let minute = wakeComponents.minute else { return }

        let alarm = SleepAlarm(
            id: UUID(),
            hour: hour,
            minute: minute,
            repeatDays: [2, 3, 4, 5, 6],
            label: String(localized: "alarm.default_label", defaultValue: "Wake up"),
            isEnabled: true,
            sound: .default,
            vibrationEnabled: true
        )
        do {
            try alarmRepository.save(alarm)
            try await alarmScheduler?.schedule(alarm)
        } catch let error as SleepRoutineError {
            // Preferences are saved; alarm row exists even if notification scheduling fails.
            if case .persistenceFailed = error { throw error }
        } catch {
            throw SleepRoutineError.persistenceFailed
        }
    }

    private static func date(
        from components: DateComponents?,
        fallbackHour: Int,
        fallbackMinute: Int,
        calendar: Calendar,
        now: Date
    ) -> Date {
        var parts = DateComponents()
        parts.year = calendar.component(.year, from: now)
        parts.month = calendar.component(.month, from: now)
        parts.day = calendar.component(.day, from: now)
        parts.hour = components?.hour ?? fallbackHour
        parts.minute = components?.minute ?? fallbackMinute
        return calendar.date(from: parts) ?? now
    }
}
