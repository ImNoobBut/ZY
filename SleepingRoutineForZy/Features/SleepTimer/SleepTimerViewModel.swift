import Foundation
import Observation

@Observable
final class SleepTimerViewModel {
    var selectedPreset: SleepTimerPreset? = .thirty
    var isCustomSelected = false
    var customMinutes: Int = 30
    var saveMessage: String?
    var errorMessage: String?

    private let preferencesRepository: any PreferencesRepository
    private let routineController: SleepRoutineController

    init(
        preferencesRepository: any PreferencesRepository,
        routineController: SleepRoutineController
    ) {
        self.preferencesRepository = preferencesRepository
        self.routineController = routineController
        loadFromPreferences()
    }

    var isRoutineActive: Bool { routineController.isRoutineActive }

    var effectiveMinutes: Int {
        if isCustomSelected {
            return min(max(customMinutes, 1), 180)
        }
        return selectedPreset?.rawValue ?? customMinutes
    }

    var remainingText: String? {
        guard isRoutineActive else { return nil }
        return routineController.timer.remaining.mmssCountdown
    }

    func selectPreset(_ preset: SleepTimerPreset) {
        selectedPreset = preset
        isCustomSelected = false
        customMinutes = preset.rawValue
        saveMessage = nil
        errorMessage = nil
    }

    func selectCustom() {
        isCustomSelected = true
        selectedPreset = nil
        saveMessage = nil
        errorMessage = nil
    }

    func loadFromPreferences() {
        let minutes = max(1, Int(preferencesRepository.load().defaultSleepTimer / 60))
        if let preset = SleepTimerPreset(rawValue: minutes) {
            selectedPreset = preset
            isCustomSelected = false
            customMinutes = minutes
        } else {
            isCustomSelected = true
            selectedPreset = nil
            customMinutes = min(max(minutes, 1), 180)
        }
    }

    func saveDefault() {
        errorMessage = nil
        saveMessage = nil
        let minutes = effectiveMinutes
        guard (1...180).contains(minutes) else {
            errorMessage = SleepRoutineError.customTimerOutOfRange.errorDescription
            return
        }

        var preferences = preferencesRepository.load()
        preferences.defaultSleepTimer = TimeInterval(minutes * 60)
        do {
            try preferencesRepository.save(preferences)
            if isRoutineActive {
                saveMessage = String(
                    localized: "sleep.saved_active_note",
                    defaultValue: "Saved for next routine. The timer already running keeps its original end time."
                )
            } else {
                saveMessage = String(
                    localized: "sleep.saved",
                    defaultValue: "Default sleep timer saved."
                )
            }
        } catch {
            errorMessage = SleepRoutineError.persistenceFailed.errorDescription
        }
    }
}
