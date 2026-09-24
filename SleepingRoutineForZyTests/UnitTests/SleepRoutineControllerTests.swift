import XCTest
import SwiftData
@testable import SleepingRoutineForZy

@MainActor
final class SleepRoutineControllerTests: XCTestCase {
    private var container: ModelContainer!
    private var preferencesRepository: PreferencesRepositoryLive!
    private var routineRepository: RoutineRepositoryLive!
    private var alarmRepository: AlarmRepositoryLive!
    private var historyRepository: HistoryRepositoryLive!
    private var audio: AudioServiceStub!
    private var spotify: SpotifyServiceStub!
    private var controller: SleepRoutineController!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        let context = ModelContext(container)
        preferencesRepository = PreferencesRepositoryLive(context: context)
        routineRepository = RoutineRepositoryLive(context: context)
        alarmRepository = AlarmRepositoryLive(context: context)
        historyRepository = HistoryRepositoryLive(context: context)
        audio = AudioServiceStub()
        spotify = SpotifyServiceStub()

        var preferences = UserPreferences.default
        preferences.defaultSleepTimer = 15 * 60
        preferences.hasCompletedOnboarding = true
        try preferencesRepository.save(preferences)

        try alarmRepository.save(SleepAlarm.makeDefault(hour: 7, minute: 0))

        controller = SleepRoutineController(
            preferencesRepository: preferencesRepository,
            routineRepository: routineRepository,
            alarmRepository: alarmRepository,
            historyRepository: historyRepository,
            audioService: audio,
            spotifyService: spotify
        )
    }

    override func tearDownWithError() throws {
        controller = nil
        preferencesRepository = nil
        routineRepository = nil
        alarmRepository = nil
        historyRepository = nil
        audio = nil
        spotify = nil
        container = nil
    }

    func testStartRoutinePersistsTimestampsAndPlaysAudio() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        await controller.startRoutine(now: now)

        XCTAssertEqual(controller.state, .timerRunning)
        XCTAssertTrue(controller.isRoutineActive)
        XCTAssertTrue(audio.isPlaying)
        XCTAssertEqual(controller.timer.startedAt, now)
        XCTAssertEqual(controller.timer.endsAt?.timeIntervalSince(now), 15 * 60, accuracy: 0.001)

        let saved = routineRepository.loadActiveRoutine()
        XCTAssertEqual(saved?.startedAt, now)
        XCTAssertEqual(saved?.endsAt?.timeIntervalSince(now), 15 * 60, accuracy: 0.001)
    }

    func testReconcileRestoresRunningTimerAfterRelaunch() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        await controller.startRoutine(now: now)

        let relaunched = SleepRoutineController(
            preferencesRepository: preferencesRepository,
            routineRepository: routineRepository,
            alarmRepository: alarmRepository,
            historyRepository: historyRepository,
            audioService: AudioServiceStub(),
            spotifyService: SpotifyServiceStub()
        )

        let mid = now.addingTimeInterval(5 * 60)
        relaunched.reconcile(now: mid)
        XCTAssertEqual(relaunched.state, .timerRunning)
        XCTAssertEqual(relaunched.timer.remaining(at: mid), 10 * 60, accuracy: 0.001)
    }

    func testEndRoutineStopsAudioAndWritesHistory() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        await controller.startRoutine(now: now)
        let end = now.addingTimeInterval(120)
        await controller.endRoutine(now: end)

        XCTAssertEqual(controller.state, .idle)
        XCTAssertFalse(audio.isPlaying)
        XCTAssertNil(routineRepository.loadActiveRoutine())
        XCTAssertEqual(historyRepository.fetchRecent(limit: 5).count, 1)
    }

    func testExpiredTimerCompletesOnTick() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        await controller.startRoutine(now: now)
        let afterEnd = now.addingTimeInterval(15 * 60 + 1)
        await controller.handleCountdownTick(now: afterEnd)

        XCTAssertEqual(controller.state, .idle)
        XCTAssertFalse(audio.isPlaying)
        XCTAssertEqual(historyRepository.fetchRecent(limit: 5).count, 1)
    }
}

@MainActor
final class SleepTimerViewModelTests: XCTestCase {
    func testSaveCustomDuration() throws {
        let environment = AppEnvironment.preview()
        let viewModel = SleepTimerViewModel(
            preferencesRepository: environment.preferencesRepository,
            routineController: environment.routineController
        )
        viewModel.selectCustom()
        viewModel.customMinutes = 42
        viewModel.saveDefault()

        let loaded = environment.preferencesRepository.load()
        XCTAssertEqual(loaded.defaultSleepTimer, 42 * 60, accuracy: 0.001)
        XCTAssertNotNil(viewModel.saveMessage)
    }

    func testPresetSelection() {
        let environment = AppEnvironment.preview()
        let viewModel = SleepTimerViewModel(
            preferencesRepository: environment.preferencesRepository,
            routineController: environment.routineController
        )
        viewModel.selectPreset(.ninety)
        XCTAssertEqual(viewModel.effectiveMinutes, 90)
        XCTAssertFalse(viewModel.isCustomSelected)
    }
}
