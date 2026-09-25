import Foundation
import Observation

@Observable
final class HomeViewModel {
    private let routineController: SleepRoutineController
    private let preferencesRepository: any PreferencesRepository
    var isBusy = false
    var errorMessage: String?
    var showQuietSoundPicker = false

    init(
        routineController: SleepRoutineController,
        preferencesRepository: any PreferencesRepository
    ) {
        self.routineController = routineController
        self.preferencesRepository = preferencesRepository
    }

    var isActive: Bool { routineController.isRoutineActive }
    var routineStatusText: String {
        switch routineController.state {
        case .idle:
            return String(localized: "home.routine.ready", defaultValue: "Ready")
        case .starting:
            return String(localized: "home.routine.starting", defaultValue: "Starting")
        case .playing, .timerRunning:
            return String(localized: "home.routine.active", defaultValue: "Active")
        case .stopping:
            return String(localized: "home.routine.stopping", defaultValue: "Stopping")
        case .completed:
            return String(localized: "home.routine.completed", defaultValue: "Completed")
        case .interrupted:
            return String(localized: "home.routine.interrupted", defaultValue: "Interrupted")
        case .failed:
            return String(localized: "home.routine.failed", defaultValue: "Needs attention")
        }
    }

    var musicText: String { routineController.musicLabel }
    var alarmText: String { routineController.nextAlarmText }
    var configuredTimerText: String {
        let minutes = routineController.configuredTimerMinutes
        return String(localized: "home.timer.minutes \(minutes)", defaultValue: "\(minutes) min")
    }

    var preferences: UserPreferences { preferencesRepository.load() }

    var bedtimeText: String {
        let prefs = preferences
        let reminder = prefs.bedtimeReminderEnabled
            ? String(localized: "home.reminder.on", defaultValue: "Reminder on")
            : String(localized: "home.reminder.off", defaultValue: "Reminder off")
        return "\(prefs.preferredBedtimeLabel) · \(reminder)"
    }

    var streakText: String {
        let streak = routineController.currentStreak
        if streak > 0 {
            return String(
                localized: "home.streak.count \(streak)",
                defaultValue: "\(streak)-night streak"
            )
        }
        return String(localized: "home.streak.empty", defaultValue: "Start tonight’s streak")
    }

    var isFading: Bool { routineController.isFadingOut }

    var usingSpotify: Bool {
        let prefs = preferences
        return !prefs.selectedSpotifyURI.isNilOrEmpty
    }

    func remainingText(at now: Date) -> String {
        routineController.timer.remaining(at: now).mmssCountdown
    }

    func setTimerMinutes(_ minutes: Int) {
        try? routineController.setDefaultTimerMinutes(minutes)
    }

    @MainActor
    func start() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        await routineController.startRoutine()
        if let error = routineController.lastError {
            errorMessage = error.errorDescription
        }
    }

    @MainActor
    func end() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        await routineController.endRoutine()
    }

    @MainActor
    func tick(now: Date) async {
        await routineController.handleCountdownTick(now: now)
    }

    func refresh() {
        routineController.reconcile()
        errorMessage = routineController.lastError?.errorDescription
    }
}

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        switch self {
        case .none: return true
        case .some(let value): return value.isEmpty
        }
    }
}
