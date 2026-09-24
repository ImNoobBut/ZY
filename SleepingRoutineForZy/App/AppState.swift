import Foundation
import Observation

@Observable
final class AppState {
    var hasCompletedOnboarding: Bool
    var selectedTab: AppTab = .home

    private let environment: AppEnvironment

    var routineState: RoutineState { environment.routineController.state }
    var sleepTimer: SleepTimerState { environment.routineController.timer }
    var isRoutineActive: Bool { environment.routineController.isRoutineActive }

    init(environment: AppEnvironment) {
        self.environment = environment

        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-UITestSkipOnboarding") {
            var preferences = environment.preferencesRepository.load()
            preferences.hasCompletedOnboarding = true
            try? environment.preferencesRepository.save(preferences)
            self.hasCompletedOnboarding = true
        } else if arguments.contains("-UITestFreshOnboarding") {
            var preferences = UserPreferences.default
            preferences.hasCompletedOnboarding = false
            try? environment.preferencesRepository.save(preferences)
            for alarm in environment.alarmRepository.fetchAll() {
                try? environment.alarmRepository.delete(id: alarm.id)
            }
            self.hasCompletedOnboarding = false
        } else {
            self.hasCompletedOnboarding = environment.preferencesRepository.load().hasCompletedOnboarding
        }

        environment.routineController.reconcile()
    }

    func refreshFromPersistence() {
        hasCompletedOnboarding = environment.preferencesRepository.load().hasCompletedOnboarding
        environment.routineController.reconcile()
        Task {
            try? await environment.alarmScheduler.reconcile(
                alarms: environment.alarmRepository.fetchAll()
            )
            await environment.adminMonitoring.checkInIfNeeded()
        }
    }

    func markOnboardingCompleted() {
        hasCompletedOnboarding = true
        refreshFromPersistence()
    }

    @MainActor
    func startSleepRoutine() async {
        await environment.routineController.startRoutine()
    }

    @MainActor
    func endSleepRoutine() async {
        await environment.routineController.endRoutine()
    }
}

enum AppTab: Hashable {
    case home
    case sleep
    case alarms
    case settings
}
