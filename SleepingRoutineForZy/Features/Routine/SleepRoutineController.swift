import Foundation
import Observation

/// Orchestrates sleep routine transitions, timer persistence, and app-owned audio stop.
/// Timer source of truth is always `startedAt` / `endsAt` timestamps.
@Observable
final class SleepRoutineController {
    private(set) var state: RoutineState = .idle
    private(set) var timer: SleepTimerState = .idle
    private(set) var activeRoutine: SleepRoutine?
    private(set) var lastError: SleepRoutineError?
    private(set) var musicLabel: String = String(
        localized: "home.music.not_configured",
        defaultValue: "Not configured yet"
    )

    private var sessionStartedAt: Date?
    private var coordinator = RoutineCoordinator()

    private let preferencesRepository: any PreferencesRepository
    private let routineRepository: any RoutineRepository
    private let alarmRepository: any AlarmRepository
    private let historyRepository: any HistoryRepository
    private let audioService: any AudioService
    private let spotifyService: any SpotifyService

    var isRoutineActive: Bool {
        switch state {
        case .starting, .playing, .timerRunning, .stopping, .interrupted:
            return true
        default:
            return false
        }
    }

    init(
        preferencesRepository: any PreferencesRepository,
        routineRepository: any RoutineRepository,
        alarmRepository: any AlarmRepository,
        historyRepository: any HistoryRepository,
        audioService: any AudioService,
        spotifyService: any SpotifyService
    ) {
        self.preferencesRepository = preferencesRepository
        self.routineRepository = routineRepository
        self.alarmRepository = alarmRepository
        self.historyRepository = historyRepository
        self.audioService = audioService
        self.spotifyService = spotifyService
        wireAudioCallbacks()
        reconcile()
    }

    func refreshMusicLabel() {
        let preferences = preferencesRepository.load()
        if let title = preferences.selectedSpotifyTitle, spotifyService.isAuthenticated {
            musicLabel = title
        } else if spotifyService.isAuthenticated {
            musicLabel = String(localized: "home.music.spotify", defaultValue: "Spotify")
        } else if audioService.isPlaying {
            musicLabel = String(localized: "home.music.playing_local", defaultValue: "Quiet night tone")
        } else if state == .interrupted {
            musicLabel = String(localized: "home.music.interrupted", defaultValue: "Paused — interruption")
        } else if isRoutineActive {
            musicLabel = String(localized: "home.music.quiet", defaultValue: "Quiet night")
        } else {
            musicLabel = String(localized: "home.music.not_configured", defaultValue: "Not configured yet")
        }
    }

    /// Rebuild state from persisted timestamps after launch, foreground, or clock changes.
    func reconcile(now: Date = Date()) {
        lastError = nil
        refreshMusicLabel()

        guard let routine = routineRepository.loadActiveRoutine(),
              routine.startedAt != nil,
              routine.endsAt != nil else {
            activeRoutine = nil
            timer = .idle
            if state != .idle && state != .failed {
                coordinator.reset()
                state = .idle
            }
            return
        }

        activeRoutine = routine
        let reconstructed = SleepTimerState.reconstructed(from: routine, now: now)
        timer = reconstructed
        sessionStartedAt = routine.startedAt

        if reconstructed.isRunning {
            coordinator.restore(.timerRunning)
            state = .timerRunning
            resumeAppOwnedAudioIfNeeded(for: routine)
            refreshMusicLabel()
            return
        }

        if reconstructed.isExpired(at: now) {
            Task { @MainActor in
                await completeExpiredRoutine(routine: routine, now: now)
            }
        }
    }

    @MainActor
    func startRoutine(now: Date = Date()) async {
        lastError = nil
        guard state == .idle || state == .failed || state == .completed else { return }

        if state == .completed || state == .failed {
            coordinator.reset()
            state = .idle
        }

        do {
            try apply(.starting)
        } catch {
            lastError = error as? SleepRoutineError
            return
        }

        let preferences = preferencesRepository.load()
        let duration = preferences.defaultSleepTimer
        let enabledAlarm = alarmRepository.fetchAll().first(where: \.isEnabled)
        let selectedURI = preferences.selectedSpotifyURI
        let useSpotify = spotifyService.isAuthenticated && selectedURI != nil
        let musicSource: MusicSource = useSpotify ? .spotify : .local

        do {
            switch musicSource {
            case .spotify:
                guard let uri = selectedURI else {
                    try apply(.failed)
                    lastError = .spotifyPlaybackUnavailable
                    return
                }
                do {
                    try await spotifyService.play(uri: uri)
                    musicLabel = preferences.selectedSpotifyTitle
                        ?? String(localized: "home.music.spotify", defaultValue: "Spotify")
                    try apply(.playing)
                } catch {
                    try apply(.failed)
                    lastError = (error as? SleepRoutineError) ?? .spotifyPlaybackUnavailable
                    return
                }
            case .local, .none:
                do {
                    try audioService.prepare()
                    try audioService.play()
                    musicLabel = String(localized: "home.music.playing_local", defaultValue: "Quiet night tone")
                    try apply(.playing)
                } catch {
                    try apply(.failed)
                    lastError = .audioSessionUnavailable
                    return
                }
            }

            try apply(.timerRunning)
        } catch let error as SleepRoutineError {
            lastError = error
            return
        } catch {
            lastError = .persistenceFailed
            coordinator.reset()
            state = .idle
            return
        }

        let timerState = SleepTimerState.start(duration: duration, now: now)
        var routine = SleepRoutine.makeDefault(duration: duration)
        routine.musicSource = musicSource
        routine.alarmID = enabledAlarm?.id
        routine.startedAt = timerState.startedAt
        routine.endsAt = timerState.endsAt
        routine.isEnabled = true

        do {
            try routineRepository.clearActiveRoutine()
            try routineRepository.save(routine)
        } catch {
            audioService.stop()
            lastError = .persistenceFailed
            coordinator.reset()
            state = .idle
            timer = .idle
            activeRoutine = nil
            return
        }

        sessionStartedAt = timerState.startedAt
        activeRoutine = routine
        timer = timerState
        state = .timerRunning
        coordinator.restore(.timerRunning)
    }

    @MainActor
    func endRoutine(now: Date = Date()) async {
        lastError = nil
        guard isRoutineActive || timer.isRunning else {
            await resetToIdle(clearPersistence: true)
            return
        }

        if state == .playing || state == .timerRunning || state == .interrupted {
            try? apply(.stopping)
        }

        stopPlayback()

        let started = sessionStartedAt ?? activeRoutine?.startedAt ?? now
        let record = SleepSessionRecord(
            id: UUID(),
            startedAt: started,
            musicStoppedAt: now,
            alarmTime: nextEnabledAlarmDate(from: now),
            completedAt: now,
            notes: nil
        )
        try? historyRepository.append(record)

        if state == .stopping {
            try? apply(.completed)
        }
        if state == .completed {
            try? apply(.idle)
        } else {
            coordinator.reset()
            state = .idle
        }

        try? routineRepository.clearActiveRoutine()
        activeRoutine = nil
        timer = .idle
        sessionStartedAt = nil
        refreshMusicLabel()
    }

    /// Called by UI on each display tick; completes routine when timestamps say the timer ended.
    @MainActor
    func handleCountdownTick(now: Date = Date()) async {
        guard let routine = activeRoutine else { return }
        guard state == .timerRunning || state == .interrupted else { return }
        let reconstructed = SleepTimerState.reconstructed(from: routine, now: now)
        timer = reconstructed
        if reconstructed.isExpired(at: now) {
            await completeExpiredRoutine(routine: routine, now: now)
        }
    }

    @MainActor
    func handleAudioInterruptionBegan() {
        guard state == .timerRunning || state == .playing else { return }
        try? apply(.interrupted)
        refreshMusicLabel()
    }

    @MainActor
    func handleAudioInterruptionEnded(shouldResume: Bool) {
        guard state == .interrupted else { return }
        if shouldResume {
            do {
                try audioService.play()
                try apply(.timerRunning)
                refreshMusicLabel()
            } catch {
                lastError = .audioSessionUnavailable
            }
        } else {
            refreshMusicLabel()
        }
    }

    @MainActor
    func handleAudioRouteChange(shouldPause: Bool) {
        guard shouldPause else { return }
        guard state == .timerRunning || state == .playing else { return }
        audioService.pause()
        try? apply(.interrupted)
        refreshMusicLabel()
    }

    var configuredTimerMinutes: Int {
        Int(preferencesRepository.load().defaultSleepTimer / 60)
    }

    var nextAlarmText: String {
        guard let alarm = alarmRepository.fetchAll().first(where: \.isEnabled) else {
            return String(localized: "home.alarm.none", defaultValue: "None")
        }
        return Self.formatTime(hour: alarm.hour, minute: alarm.minute)
    }

    static func formatTime(hour: Int, minute: Int, calendar: Calendar = .current) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let date = calendar.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func wireAudioCallbacks() {
        audioService.onInterruptionBegan = { [weak self] in
            Task { @MainActor in
                self?.handleAudioInterruptionBegan()
            }
        }
        audioService.onInterruptionEnded = { [weak self] shouldResume in
            Task { @MainActor in
                self?.handleAudioInterruptionEnded(shouldResume: shouldResume)
            }
        }
        audioService.onRouteChanged = { [weak self] shouldPause in
            Task { @MainActor in
                self?.handleAudioRouteChange(shouldPause: shouldPause)
            }
        }
    }

    private func resumeAppOwnedAudioIfNeeded(for routine: SleepRoutine) {
        guard routine.musicSource == .local || routine.musicSource == .none else { return }
        guard !audioService.isPlaying, !audioService.isInterrupted else { return }
        do {
            try audioService.prepare()
            try audioService.play()
        } catch {
            // Soft failure — timer remains accurate from timestamps.
            lastError = .audioSessionUnavailable
        }
    }

    private func apply(_ next: RoutineState) throws {
        try coordinator.apply(next)
        state = coordinator.state
    }

    private func stopPlayback() {
        audioService.stop()
        Task {
            try? await spotifyService.pause()
        }
    }

    @MainActor
    private func completeExpiredRoutine(routine: SleepRoutine, now: Date) async {
        guard activeRoutine?.id == routine.id else { return }
        guard state == .timerRunning || state == .interrupted else { return }

        if state == .interrupted {
            try? apply(.stopping)
            try? apply(.completed)
        } else {
            try? apply(.completed)
        }
        stopPlayback()

        let record = SleepSessionRecord(
            id: UUID(),
            startedAt: routine.startedAt ?? now,
            musicStoppedAt: routine.endsAt ?? now,
            alarmTime: nextEnabledAlarmDate(from: now),
            completedAt: now,
            notes: String(localized: "history.timer_completed", defaultValue: "Timer completed")
        )
        try? historyRepository.append(record)
        try? routineRepository.clearActiveRoutine()

        if state == .completed {
            try? apply(.idle)
        } else {
            coordinator.reset()
            state = .idle
        }

        activeRoutine = nil
        timer = .idle
        sessionStartedAt = nil
        refreshMusicLabel()
    }

    @MainActor
    private func resetToIdle(clearPersistence: Bool) async {
        stopPlayback()
        if clearPersistence {
            try? routineRepository.clearActiveRoutine()
        }
        coordinator.reset()
        state = .idle
        timer = .idle
        activeRoutine = nil
        sessionStartedAt = nil
        refreshMusicLabel()
    }

    private func nextEnabledAlarmDate(from now: Date, calendar: Calendar = .current) -> Date? {
        guard let alarm = alarmRepository.fetchAll().first(where: \.isEnabled) else { return nil }
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = alarm.hour
        components.minute = alarm.minute
        components.second = 0
        guard let today = calendar.date(from: components) else { return nil }
        if today > now { return today }
        return calendar.date(byAdding: .day, value: 1, to: today)
    }
}
