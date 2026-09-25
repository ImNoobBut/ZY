import XCTest
import SwiftData
@testable import SleepingRoutineForZy

@MainActor
final class OnboardingViewModelTests: XCTestCase {
    private var container: ModelContainer!
    private var preferencesRepository: PreferencesRepositoryLive!
    private var alarmRepository: AlarmRepositoryLive!
    private var alarmAuthorization: AlarmAuthorizationServiceMock!
    private var spotify: SpotifyServiceStub!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        let context = ModelContext(container)
        preferencesRepository = PreferencesRepositoryLive(context: context)
        alarmRepository = AlarmRepositoryLive(context: context)
        alarmAuthorization = AlarmAuthorizationServiceMock(usesAlarmKit: false, grantResult: true, statusResult: false)
        spotify = SpotifyServiceStub()
    }

    override func tearDownWithError() throws {
        preferencesRepository = nil
        alarmRepository = nil
        alarmAuthorization = nil
        spotify = nil
        container = nil
    }

    private func makeViewModel() -> OnboardingViewModel {
        OnboardingViewModel(
            preferencesRepository: preferencesRepository,
            alarmRepository: alarmRepository,
            alarmAuthorization: alarmAuthorization,
            spotifyService: spotify,
            calendar: Calendar(identifier: .gregorian),
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    func testWelcomeToPreferencesNavigation() {
        let viewModel = makeViewModel()
        XCTAssertEqual(viewModel.step, .welcome)
        viewModel.goNext()
        XCTAssertEqual(viewModel.step, .alarms)
        viewModel.goNext()
        XCTAssertEqual(viewModel.step, .spotify)
        viewModel.goNext()
        XCTAssertEqual(viewModel.step, .preferences)
        viewModel.goBack()
        XCTAssertEqual(viewModel.step, .spotify)
    }

    func testAlarmPermissionGranted() async {
        let viewModel = makeViewModel()
        viewModel.goNext()
        await viewModel.requestAlarmPermission()
        XCTAssertEqual(alarmAuthorization.requestCount, 1)
        XCTAssertEqual(viewModel.notificationGranted, true)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testAlarmPermissionDeniedStoresMessage() async {
        alarmAuthorization.grantResult = false
        let viewModel = makeViewModel()
        viewModel.goNext()
        await viewModel.requestAlarmPermission()
        XCTAssertEqual(viewModel.notificationGranted, false)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testSkipSpotifyAdvances() {
        let viewModel = makeViewModel()
        viewModel.goNext()
        viewModel.goNext()
        XCTAssertEqual(viewModel.step, .spotify)
        viewModel.skipSpotify()
        XCTAssertEqual(viewModel.step, .preferences)
    }

    func testConnectSpotifyFailureDoesNotAdvance() async {
        let viewModel = makeViewModel()
        viewModel.goNext()
        viewModel.goNext()
        await viewModel.connectSpotify()
        XCTAssertEqual(viewModel.step, .spotify)
        XCTAssertNotNil(viewModel.spotifyStatusMessage)
    }

    func testFinishPersistsPreferencesAndDefaultAlarm() async throws {
        let viewModel = makeViewModel()
        viewModel.defaultSleepTimerMinutes = 45
        viewModel.defaultAlarmEnabled = true
        viewModel.goNext()
        viewModel.goNext()
        viewModel.goNext()

        let preferences = try await viewModel.finish()
        XCTAssertTrue(preferences.hasCompletedOnboarding)
        XCTAssertEqual(preferences.defaultSleepTimer, 45 * 60, accuracy: 0.001)
        XCTAssertTrue(preferences.defaultAlarmEnabled)

        let loaded = preferencesRepository.load()
        XCTAssertTrue(loaded.hasCompletedOnboarding)
        XCTAssertEqual(loaded.defaultSleepTimer, 45 * 60, accuracy: 0.001)

        let alarms = alarmRepository.fetchAll()
        XCTAssertEqual(alarms.count, 1)
        XCTAssertEqual(alarms.first?.hour, preferences.preferredWakeTime?.hour)
        XCTAssertEqual(alarms.first?.minute, preferences.preferredWakeTime?.minute)
    }

    func testFinishWithoutDefaultAlarmSkipsAlarmCreation() async throws {
        let viewModel = makeViewModel()
        viewModel.defaultAlarmEnabled = false
        _ = try await viewModel.finish()
        XCTAssertTrue(alarmRepository.fetchAll().isEmpty)
    }
}
