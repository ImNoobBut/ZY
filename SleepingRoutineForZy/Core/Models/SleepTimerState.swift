import Foundation

struct SleepTimerState: Equatable, Sendable {
    var startedAt: Date?
    var endsAt: Date?
    var isRunning: Bool

    static let idle = SleepTimerState(startedAt: nil, endsAt: nil, isRunning: false)

    var remaining: TimeInterval {
        remaining(at: Date())
    }

    func remaining(at now: Date) -> TimeInterval {
        guard let endsAt else { return 0 }
        return max(0, endsAt.timeIntervalSince(now))
    }

    var isExpired: Bool {
        isExpired(at: Date())
    }

    func isExpired(at now: Date) -> Bool {
        guard let endsAt else { return false }
        return now >= endsAt
    }

    static func start(duration: TimeInterval, now: Date = Date()) -> SleepTimerState {
        let clamped = min(max(duration, 60), 180 * 60)
        return SleepTimerState(
            startedAt: now,
            endsAt: now.addingTimeInterval(clamped),
            isRunning: true
        )
    }

    /// Reconstruct timer state from persisted routine timestamps.
    /// Source of truth is `startedAt` / `endsAt`, never an in-memory Timer.
    static func reconstructed(from routine: SleepRoutine, now: Date = Date()) -> SleepTimerState {
        guard let startedAt = routine.startedAt, let endsAt = routine.endsAt else {
            return .idle
        }
        if now >= endsAt {
            return SleepTimerState(startedAt: startedAt, endsAt: endsAt, isRunning: false)
        }
        return SleepTimerState(startedAt: startedAt, endsAt: endsAt, isRunning: true)
    }

    static func durationMinutes(_ minutes: Int) -> TimeInterval {
        TimeInterval(minutes * 60)
    }
}

enum SleepTimerPreset: Int, CaseIterable, Identifiable, Sendable {
    case fifteen = 15
    case thirty = 30
    case fortyFive = 45
    case sixty = 60
    case ninety = 90

    var id: Int { rawValue }

    var duration: TimeInterval {
        SleepTimerState.durationMinutes(rawValue)
    }
}
