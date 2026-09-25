import XCTest
import SwiftData
@testable import SleepingRoutineForZy

final class SleepAudioSampleFactoryTests: XCTestCase {
    func testGeneratedWAVHasValidHeaderAndPayload() {
        let data = SleepAudioSampleFactory.makeSoftToneWAV(durationSeconds: 0.25, sampleRate: 8_000)
        XCTAssertTrue(SleepAudioSampleFactory.riffHeaderIsValid(data))
        XCTAssertGreaterThan(data.count, 44)
    }

    func testQuietSoundCatalogGeneratesValidWAV() {
        for sound in QuietSound.allCases {
            let data = SleepAudioSampleFactory.makeWAV(for: sound)
            XCTAssertTrue(SleepAudioSampleFactory.riffHeaderIsValid(data), sound.rawValue)
            XCTAssertGreaterThan(data.count, 44, sound.rawValue)
        }
    }
}

@MainActor
final class AudioInterruptionRoutineTests: XCTestCase {
    private var container: ModelContainer!
    private var audio: AudioServiceStub!
    private var controller: SleepRoutineController!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        let context = ModelContext(container)
        audio = AudioServiceStub()
        var preferences = UserPreferences.default
        preferences.defaultSleepTimer = 10 * 60
        try PreferencesRepositoryLive(context: context).save(preferences)

        controller = SleepRoutineController(
            preferencesRepository: PreferencesRepositoryLive(context: context),
            routineRepository: RoutineRepositoryLive(context: context),
            alarmRepository: AlarmRepositoryLive(context: context),
            historyRepository: HistoryRepositoryLive(context: context),
            audioService: audio,
            spotifyService: SpotifyServiceStub()
        )
    }

    override func tearDownWithError() throws {
        controller = nil
        audio = nil
        container = nil
    }

    func testStartUsesAppOwnedAudio() async {
        await controller.startRoutine(now: Date(timeIntervalSince1970: 2_000_000_000))
        XCTAssertEqual(controller.state, .timerRunning)
        XCTAssertTrue(audio.isPlaying)
        XCTAssertEqual(audio.playCallCount, 1)
        XCTAssertEqual(controller.activeRoutine?.musicSource, .local)
    }

    func testInterruptionPausesRoutineState() async {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        await controller.startRoutine(now: now)
        audio.simulateInterruptionBegan()

        XCTAssertEqual(controller.state, .interrupted)
        XCTAssertFalse(audio.isPlaying)
    }

    func testInterruptionEndResumesWhenAllowed() async {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        await controller.startRoutine(now: now)
        audio.simulateInterruptionBegan()
        audio.simulateInterruptionEnded(shouldResume: true)

        XCTAssertEqual(controller.state, .timerRunning)
        XCTAssertTrue(audio.isPlaying)
    }

    func testRouteChangePausesPlayback() async {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        await controller.startRoutine(now: now)
        audio.simulateRouteChange(shouldPause: true)

        XCTAssertEqual(controller.state, .interrupted)
        XCTAssertFalse(audio.isPlaying)
    }

    func testEndRoutineStopsAudioAfterInterruption() async {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        await controller.startRoutine(now: now)
        audio.simulateInterruptionBegan()
        await controller.endRoutine(now: now.addingTimeInterval(30))

        XCTAssertEqual(controller.state, .idle)
        XCTAssertGreaterThanOrEqual(audio.stopCallCount, 1)
        XCTAssertFalse(audio.isPlaying)
    }

    func testTimerExpiryStopsAudio() async {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        await controller.startRoutine(now: now)
        await controller.handleCountdownTick(now: now.addingTimeInterval(10 * 60 + 1))

        XCTAssertEqual(controller.state, .idle)
        XCTAssertFalse(audio.isPlaying)
    }
}

final class RoutineInterruptedResumeTransitionTests: XCTestCase {
    func testInterruptedCanReturnToTimerRunning() throws {
        var state = RoutineState.idle
        state = try RoutineStateMachine.transition(from: state, to: .starting)
        state = try RoutineStateMachine.transition(from: state, to: .playing)
        state = try RoutineStateMachine.transition(from: state, to: .timerRunning)
        state = try RoutineStateMachine.transition(from: state, to: .interrupted)
        state = try RoutineStateMachine.transition(from: state, to: .timerRunning)
        XCTAssertEqual(state, .timerRunning)
    }
}
