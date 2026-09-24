import XCTest
@testable import SleepingRoutineForZy

final class SpotifyPKCETests: XCTestCase {
    func testCodeChallengeIsBase64URLWithoutPadding() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let challenge = SpotifyPKCE.makeCodeChallenge(from: verifier)
        XCTAssertFalse(challenge.contains("+"))
        XCTAssertFalse(challenge.contains("/"))
        XCTAssertFalse(challenge.contains("="))
        // RFC 7636 appendix B known vector
        XCTAssertEqual(challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testCodeVerifierLengthAndAlphabet() {
        let verifier = SpotifyPKCE.makeCodeVerifier(length: 64)
        XCTAssertEqual(verifier.count, 64)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        XCTAssertTrue(verifier.unicodeScalars.allSatisfy { allowed.contains($0) })
    }
}

@MainActor
final class SpotifyViewModelTests: XCTestCase {
    func testConnectAndSelectPlaylistPersistsURI() async throws {
        let environment = AppEnvironment.preview()
        let spotify = environment.spotifyService as! SpotifyServiceStub
        spotify.shouldFailPlay = false
        var config = environment.configuration
        config.spotifyClientID = "test-client-id"

        let viewModel = SpotifyViewModel(
            spotifyService: spotify,
            preferencesRepository: environment.preferencesRepository,
            configuration: config
        )

        await viewModel.connect()
        XCTAssertTrue(viewModel.isAuthenticated)

        await viewModel.refresh()
        XCTAssertEqual(viewModel.playlists.count, 1)

        let playlist = try XCTUnwrap(viewModel.playlists.first)
        viewModel.select(playlist: playlist)

        let preferences = environment.preferencesRepository.load()
        XCTAssertEqual(preferences.selectedSpotifyURI, playlist.uri)
        XCTAssertEqual(preferences.selectedSpotifyTitle, playlist.name)
        XCTAssertEqual(viewModel.selectedTitle, playlist.name)
    }

    func testMissingClientIDSurfacesError() async {
        let environment = AppEnvironment.preview()
        var config = environment.configuration
        config.spotifyClientID = ""

        let viewModel = SpotifyViewModel(
            spotifyService: SpotifyServiceStub(),
            preferencesRepository: environment.preferencesRepository,
            configuration: config
        )
        await viewModel.connect()
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isAuthenticated)
    }
}

@MainActor
final class SpotifyRoutineIntegrationTests: XCTestCase {
    func testStartRoutinePlaysSelectedSpotifyURI() async throws {
        let environment = AppEnvironment.preview()
        let spotify = environment.spotifyService as! SpotifyServiceStub
        spotify.shouldFailPlay = false
        try await spotify.authenticate()

        var preferences = environment.preferencesRepository.load()
        preferences.selectedSpotifyURI = "spotify:playlist:bedtime"
        preferences.selectedSpotifyTitle = "Bedtime Mix"
        preferences.defaultSleepTimer = 20 * 60
        try environment.preferencesRepository.save(preferences)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        await environment.routineController.startRoutine(now: now)

        XCTAssertEqual(environment.routineController.state, .timerRunning)
        XCTAssertEqual(spotify.playURI, "spotify:playlist:bedtime")
        XCTAssertEqual(environment.routineController.musicLabel, "Bedtime Mix")
        XCTAssertEqual(environment.routineRepository.loadActiveRoutine()?.musicSource, .spotify)
    }

    func testAuthenticatedWithoutSelectionFallsBackToLocalAudio() async throws {
        let environment = AppEnvironment.preview()
        let spotify = environment.spotifyService as! SpotifyServiceStub
        try await spotify.authenticate()

        var preferences = environment.preferencesRepository.load()
        preferences.selectedSpotifyURI = nil
        preferences.selectedSpotifyTitle = nil
        preferences.defaultSleepTimer = 10 * 60
        try environment.preferencesRepository.save(preferences)

        let audio = environment.audioService as! AudioServiceStub
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        await environment.routineController.startRoutine(now: now)

        XCTAssertEqual(environment.routineController.state, .timerRunning)
        XCTAssertTrue(audio.isPlaying)
        XCTAssertNil(spotify.playURI)
        XCTAssertEqual(environment.routineRepository.loadActiveRoutine()?.musicSource, .local)
    }
}
