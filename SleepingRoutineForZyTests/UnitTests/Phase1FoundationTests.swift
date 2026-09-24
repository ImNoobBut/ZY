import XCTest
@testable import SleepingRoutineForZy

final class SleepTimerStateTests: XCTestCase {
    func testFifteenMinutePreset() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let state = SleepTimerState.start(duration: SleepTimerPreset.fifteen.duration, now: now)
        XCTAssertTrue(state.isRunning)
        XCTAssertEqual(state.remaining(at: now), 15 * 60, accuracy: 0.001)
        XCTAssertEqual(state.endsAt?.timeIntervalSince(now), 15 * 60, accuracy: 0.001)
    }

    func testThirtyMinutePreset() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let state = SleepTimerState.start(duration: SleepTimerPreset.thirty.duration, now: now)
        XCTAssertEqual(state.remaining(at: now), 30 * 60, accuracy: 0.001)
    }

    func testCustomDurationClampedToMax() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let state = SleepTimerState.start(duration: 999 * 60, now: now)
        XCTAssertEqual(state.remaining(at: now), 180 * 60, accuracy: 0.001)
    }

    func testCustomDurationClampedToMin() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let state = SleepTimerState.start(duration: 10, now: now)
        XCTAssertEqual(state.remaining(at: now), 60, accuracy: 0.001)
    }

    func testExpiredTimerAfterRestartReconstruction() {
        let started = Date(timeIntervalSince1970: 1_000_000)
        let ends = started.addingTimeInterval(30 * 60)
        let routine = SleepRoutine(
            id: UUID(),
            isEnabled: true,
            musicSource: .none,
            sleepTimerDuration: 30 * 60,
            alarmID: nil,
            startedAt: started,
            endsAt: ends
        )
        let afterExpiry = ends.addingTimeInterval(5)
        let reconstructed = SleepTimerState.reconstructed(from: routine, now: afterExpiry)
        XCTAssertFalse(reconstructed.isRunning)
        XCTAssertTrue(reconstructed.isExpired(at: afterExpiry))
        XCTAssertEqual(reconstructed.remaining(at: afterExpiry), 0, accuracy: 0.001)
    }

    func testReconstructionWhileRunning() {
        let started = Date(timeIntervalSince1970: 1_000_000)
        let ends = started.addingTimeInterval(30 * 60)
        let routine = SleepRoutine(
            id: UUID(),
            isEnabled: true,
            musicSource: .local,
            sleepTimerDuration: 30 * 60,
            alarmID: nil,
            startedAt: started,
            endsAt: ends
        )
        let mid = started.addingTimeInterval(10 * 60)
        let reconstructed = SleepTimerState.reconstructed(from: routine, now: mid)
        XCTAssertTrue(reconstructed.isRunning)
        XCTAssertEqual(reconstructed.remaining(at: mid), 20 * 60, accuracy: 0.001)
    }
}

final class RoutineStateMachineTests: XCTestCase {
    func testHappyPathTransitions() throws {
        var state = RoutineState.idle
        state = try RoutineStateMachine.transition(from: state, to: .starting)
        state = try RoutineStateMachine.transition(from: state, to: .playing)
        state = try RoutineStateMachine.transition(from: state, to: .timerRunning)
        state = try RoutineStateMachine.transition(from: state, to: .stopping)
        state = try RoutineStateMachine.transition(from: state, to: .completed)
        XCTAssertEqual(state, .completed)
    }

    func testFailureFromStarting() throws {
        var state = RoutineState.idle
        state = try RoutineStateMachine.transition(from: state, to: .starting)
        state = try RoutineStateMachine.transition(from: state, to: .failed)
        XCTAssertEqual(state, .failed)
    }

    func testInvalidTransitionThrows() {
        XCTAssertThrowsError(try RoutineStateMachine.transition(from: .idle, to: .playing)) { error in
            XCTAssertEqual(
                error as? SleepRoutineError,
                .invalidRoutineTransition(from: .idle, to: .playing)
            )
        }
    }

    func testCoordinatorApply() throws {
        var coordinator = RoutineCoordinator()
        try coordinator.apply(.starting)
        try coordinator.apply(.playing)
        XCTAssertEqual(coordinator.state, .playing)
        coordinator.reset()
        XCTAssertEqual(coordinator.state, .idle)
    }
}

final class DomainModelCodableTests: XCTestCase {
    func testUserPreferencesRoundTrip() throws {
        let original = UserPreferences.default
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(UserPreferences.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testSleepRoutineRoundTrip() throws {
        let original = SleepRoutine.makeDefault(duration: 45 * 60)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SleepRoutine.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testSleepAlarmRoundTrip() throws {
        let original = SleepAlarm.makeDefault()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SleepAlarm.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testDeviceStatusRoundTrip() throws {
        let original = DeviceStatus(
            batteryLevel: 0.78,
            isCharging: false,
            routineActive: true,
            routineStartedAt: Date(timeIntervalSince1970: 1_699_999_000),
            sleepTimerEndsAt: Date(timeIntervalSince1970: 1_700_000_800),
            spotifyConnected: false,
            alarmEnabled: true,
            nextAlarm: Date(timeIntervalSince1970: 1_700_000_000),
            isPlayingOwnAudio: false,
            lastCheckIn: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DeviceStatus.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}

final class KeychainServiceMemoryTests: XCTestCase {
    func testSetGetDeleteString() throws {
        let keychain = KeychainServiceMemory()
        try keychain.setString("token-value", forKey: KeychainKey.spotifyAccessToken)
        XCTAssertEqual(try keychain.string(forKey: KeychainKey.spotifyAccessToken), "token-value")
        try keychain.delete(forKey: KeychainKey.spotifyAccessToken)
        XCTAssertNil(try keychain.string(forKey: KeychainKey.spotifyAccessToken))
    }
}
