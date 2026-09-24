import Foundation

enum RoutineState: String, Codable, Equatable, Sendable, CaseIterable {
    case idle
    case starting
    case playing
    case timerRunning
    case stopping
    case completed
    case interrupted
    case failed
}

struct RoutineTransition: Equatable, Sendable {
    let from: RoutineState
    let to: RoutineState
}

enum RoutineStateMachine {
    /// Allowed transitions for the sleep routine state machine.
    static let allowed: Set<RoutineTransition> = [
        RoutineTransition(from: .idle, to: .starting),
        RoutineTransition(from: .starting, to: .playing),
        RoutineTransition(from: .starting, to: .failed),
        RoutineTransition(from: .playing, to: .timerRunning),
        RoutineTransition(from: .playing, to: .interrupted),
        RoutineTransition(from: .playing, to: .stopping),
        RoutineTransition(from: .playing, to: .failed),
        RoutineTransition(from: .timerRunning, to: .stopping),
        RoutineTransition(from: .timerRunning, to: .interrupted),
        RoutineTransition(from: .timerRunning, to: .completed),
        RoutineTransition(from: .stopping, to: .completed),
        RoutineTransition(from: .interrupted, to: .idle),
        RoutineTransition(from: .interrupted, to: .stopping),
        RoutineTransition(from: .interrupted, to: .timerRunning),
        RoutineTransition(from: .interrupted, to: .playing),
        RoutineTransition(from: .completed, to: .idle),
        RoutineTransition(from: .failed, to: .idle),
        RoutineTransition(from: .failed, to: .starting)
    ]

    static func canTransition(from: RoutineState, to: RoutineState) -> Bool {
        allowed.contains(RoutineTransition(from: from, to: to))
    }

    static func transition(from: RoutineState, to: RoutineState) throws -> RoutineState {
        guard canTransition(from: from, to: to) else {
            throw SleepRoutineError.invalidRoutineTransition(from: from, to: to)
        }
        return to
    }
}
