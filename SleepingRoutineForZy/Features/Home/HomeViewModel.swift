import Foundation
import Observation

@Observable
final class HomeViewModel {
    private let routineController: SleepRoutineController
    var isBusy = false
    var errorMessage: String?

    init(routineController: SleepRoutineController) {
        self.routineController = routineController
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

    func remainingText(at now: Date) -> String {
        routineController.timer.remaining(at: now).mmssCountdown
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
