import Foundation
import Observation

@Observable
@MainActor
final class SpotifyViewModel {
    var isAuthenticated = false
    var userDisplayName: String?
    var playlists: [SpotifyPlaylist] = []
    var searchResults: [SpotifyTrack] = []
    var deviceNames: [String] = []
    var searchQuery = ""
    var isBusy = false
    var errorMessage: String?
    var infoMessage: String?
    var selectedTitle: String?

    private let spotifyService: any SpotifyService
    private let preferencesRepository: any PreferencesRepository
    private let configuration: AppConfiguration

    init(
        spotifyService: any SpotifyService,
        preferencesRepository: any PreferencesRepository,
        configuration: AppConfiguration
    ) {
        self.spotifyService = spotifyService
        self.preferencesRepository = preferencesRepository
        self.configuration = configuration
        selectedTitle = preferencesRepository.load().selectedSpotifyTitle
        isAuthenticated = spotifyService.isAuthenticated
    }

    var clientIDConfigured: Bool {
        !configuration.spotifyClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var devicesSummary: String {
        if deviceNames.isEmpty {
            return String(
                localized: "spotify.devices.none",
                defaultValue: "Devices: none — open Spotify and play a track once."
            )
        }
        let lines = deviceNames.map { "• \($0)" }.joined(separator: "\n")
        return String(localized: "spotify.devices.list", defaultValue: "Devices:\n\(lines)")
    }

    func refresh() async {
        isAuthenticated = spotifyService.isAuthenticated
        selectedTitle = preferencesRepository.load().selectedSpotifyTitle
        guard isAuthenticated else {
            playlists = []
            deviceNames = []
            userDisplayName = nil
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let user = try await spotifyService.getCurrentUser()
            userDisplayName = user.displayName
            playlists = try await spotifyService.getPlaylists()
            deviceNames = (try? await spotifyService.listDeviceNames()) ?? []
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? SleepRoutineError.spotifyNotConnected.errorDescription
            if !spotifyService.isAuthenticated {
                playlists = []
                deviceNames = []
                isAuthenticated = false
            }
        }
    }

    func connect() async {
        errorMessage = nil
        infoMessage = nil
        guard clientIDConfigured else {
            errorMessage = String(
                localized: "spotify.error.missing_client_id",
                defaultValue: "Add your Spotify Client ID in Config/Secrets.xcconfig, then rebuild."
            )
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            try await spotifyService.authenticate()
            isAuthenticated = true
            infoMessage = String(localized: "spotify.connected", defaultValue: "Spotify is connected.")
            await refresh()
        } catch {
            isAuthenticated = false
            errorMessage = SleepRoutineError.authenticationFailed.errorDescription
        }
    }

    func disconnect() async {
        isBusy = true
        defer { isBusy = false }
        try? await spotifyService.logout()
        clearSelectionPrefs()
        isAuthenticated = false
        playlists = []
        searchResults = []
        deviceNames = []
        userDisplayName = nil
        selectedTitle = nil
        errorMessage = nil
        infoMessage = String(localized: "spotify.disconnected", defaultValue: "Spotify disconnected.")
    }

    func search() async {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            searchResults = try await spotifyService.search(query: query)
            errorMessage = nil
            if searchResults.isEmpty {
                infoMessage = String(
                    localized: "spotify.search.empty",
                    defaultValue: "No tracks found."
                )
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
            searchResults = []
        }
    }

    func select(playlist: SpotifyPlaylist) {
        saveSelection(uri: playlist.uri, title: playlist.name)
    }

    func select(track: SpotifyTrack) {
        saveSelection(uri: track.uri, title: "\(track.name) — \(track.artistName)")
    }

    func playSelected() async {
        guard let uri = preferencesRepository.load().selectedSpotifyURI else {
            errorMessage = String(
                localized: "spotify.error.none_selected",
                defaultValue: "Choose a playlist or track first."
            )
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            try await spotifyService.play(uri: uri)
            deviceNames = (try? await spotifyService.listDeviceNames()) ?? deviceNames
            infoMessage = String(
                localized: "spotify.playback.started",
                defaultValue: "Playback requested on your active Spotify device."
            )
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? SleepRoutineError.spotifyPlaybackUnavailable.errorDescription
            infoMessage = String(
                localized: "spotify.playback.open_app",
                defaultValue: "If nothing plays, open Spotify on this iPhone so an active device is available. Premium is required for remote playback."
            )
        }
    }

    private func saveSelection(uri: String, title: String) {
        var preferences = preferencesRepository.load()
        preferences.selectedSpotifyURI = uri
        preferences.selectedSpotifyTitle = title
        try? preferencesRepository.save(preferences)
        selectedTitle = title
        infoMessage = String(
            localized: "spotify.selection.saved",
            defaultValue: "Selected “\(title)” for bedtime."
        )
    }

    private func clearSelectionPrefs() {
        var preferences = preferencesRepository.load()
        preferences.selectedSpotifyURI = nil
        preferences.selectedSpotifyTitle = nil
        try? preferencesRepository.save(preferences)
    }
}
