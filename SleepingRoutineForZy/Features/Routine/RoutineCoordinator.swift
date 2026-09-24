import Foundation

/// Coordinates sleep routine transitions.
struct RoutineCoordinator {
    private(set) var state: RoutineState = .idle

    mutating func apply(_ next: RoutineState) throws {
        state = try RoutineStateMachine.transition(from: state, to: next)
    }

    mutating func reset() {
        state = .idle
    }

    /// Used when reconstructing UI state from persisted timestamps (not a user action).
    mutating func restore(_ value: RoutineState) {
        state = value
    }
}
