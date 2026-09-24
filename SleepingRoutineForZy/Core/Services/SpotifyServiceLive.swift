import Foundation
import UIKit

/// Composes PKCE auth + Web API. Playback uses Spotify Web API player endpoints
/// (Premium + active Spotify device required). Does not embed the Spotify iOS SDK binaries;
/// App Remote can be added later via the official SpotifyiOS package on macOS/Xcode.
@MainActor
final class SpotifyServiceLive: SpotifyService {
    private let authManager: SpotifyAuthManager
    private let apiClient: SpotifyAPIClient
    private let configuration: AppConfiguration

    init(
        authManager: SpotifyAuthManager,
        apiClient: SpotifyAPIClient,
        configuration: AppConfiguration
    ) {
        self.authManager = authManager
        self.apiClient = apiClient
        self.configuration = configuration
    }

    var isAuthenticated: Bool {
        authManager.isAuthenticated
    }

    func authenticate() async throws {
        do {
            try await authManager.authenticate()
        } catch is SpotifyAuthError {
            throw SleepRoutineError.authenticationFailed
        } catch {
            throw SleepRoutineError.authenticationFailed
        }
    }

    func logout() async throws {
        try authManager.logout()
    }

    func getCurrentUser() async throws -> SpotifyUser {
        try await mapAPI {
            try await apiClient.getCurrentUser()
        }
    }

    func search(query: String) async throws -> [SpotifyTrack] {
        try await mapAPI {
            try await apiClient.searchTracks(query: query)
        }
    }

    func getPlaylists() async throws -> [SpotifyPlaylist] {
        try await mapAPI {
            try await apiClient.getPlaylists()
        }
    }

    func getPlaylistTracks(playlistID: String) async throws -> [SpotifyTrack] {
        try await mapAPI {
            try await apiClient.getPlaylistTracks(playlistID: playlistID)
        }
    }

    func play(uri: String) async throws {
        do {
            try await apiClient.play(uri: uri)
        } catch SpotifyAPIError.noActiveDevice {
            // Closest supported alternative: open Spotify so the user can activate a device.
            openSpotifyApp(uri: uri)
            throw SleepRoutineError.spotifyPlaybackUnavailable
        } catch SpotifyAPIError.premiumRequired {
            throw SleepRoutineError.spotifyPlaybackUnavailable
        } catch SpotifyAPIError.notAuthenticated {
            throw SleepRoutineError.spotifyNotConnected
        } catch {
            throw SleepRoutineError.spotifyPlaybackUnavailable
        }
    }

    func pause() async throws {
        do {
            try await apiClient.pause()
        } catch SpotifyAPIError.noActiveDevice, SpotifyAPIError.premiumRequired {
            throw SleepRoutineError.spotifyPlaybackUnavailable
        } catch SpotifyAPIError.notAuthenticated {
            throw SleepRoutineError.spotifyNotConnected
        } catch {
            throw SleepRoutineError.spotifyPlaybackUnavailable
        }
    }

    /// Opens the Spotify app (or App Store) — used when Web API has no active device.
    func openSpotifyApp(uri: String? = nil) {
        let candidates: [URL?] = [
            uri.flatMap { URL(string: $0) },
            URL(string: "spotify://"),
            URL(string: "https://apps.apple.com/app/spotify-music/id324684580")
        ]
        for url in candidates.compactMap({ $0 }) {
            if UIApplication.shared.canOpenURL(url) || url.scheme == "https" {
                UIApplication.shared.open(url)
                return
            }
        }
    }

    private func mapAPI<T>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch SpotifyAPIError.notAuthenticated {
            throw SleepRoutineError.spotifyNotConnected
        } catch is SpotifyAPIError {
            throw SleepRoutineError.networkUnavailable
        } catch {
            throw SleepRoutineError.networkUnavailable
        }
    }
}

/// Phase 1 stub — kept for tests/previews.
final class SpotifyServiceStub: SpotifyService {
    private(set) var isAuthenticated = false
    var playURI: String?
    var shouldFailPlay = true

    func authenticate() async throws {
        isAuthenticated = true
    }

    func logout() async throws {
        isAuthenticated = false
        playURI = nil
    }

    func getCurrentUser() async throws -> SpotifyUser {
        guard isAuthenticated else { throw SleepRoutineError.spotifyNotConnected }
        return SpotifyUser(id: "stub", displayName: "Stub User")
    }

    func search(query: String) async throws -> [SpotifyTrack] {
        guard isAuthenticated else { throw SleepRoutineError.spotifyNotConnected }
        return [
            SpotifyTrack(id: "1", name: "Quiet Evening", artistName: "Demo", uri: "spotify:track:demo1")
        ].filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    }

    func getPlaylists() async throws -> [SpotifyPlaylist] {
        guard isAuthenticated else { throw SleepRoutineError.spotifyNotConnected }
        return [
            SpotifyPlaylist(
                id: "pl1",
                name: "Sleep Playlist",
                trackCount: 12,
                uri: "spotify:playlist:demo",
                imageURL: nil
            )
        ]
    }

    func getPlaylistTracks(playlistID: String) async throws -> [SpotifyTrack] {
        _ = playlistID
        guard isAuthenticated else { throw SleepRoutineError.spotifyNotConnected }
        return [
            SpotifyTrack(id: "1", name: "Quiet Evening", artistName: "Demo", uri: "spotify:track:demo1"),
            SpotifyTrack(id: "2", name: "Soft Rain", artistName: "Demo", uri: "spotify:track:demo2")
        ]
    }

    func play(uri: String) async throws {
        guard isAuthenticated else { throw SleepRoutineError.spotifyNotConnected }
        if shouldFailPlay {
            throw SleepRoutineError.spotifyPlaybackUnavailable
        }
        playURI = uri
    }

    func pause() async throws {
        guard isAuthenticated else { throw SleepRoutineError.spotifyNotConnected }
        if shouldFailPlay {
            throw SleepRoutineError.spotifyPlaybackUnavailable
        }
        playURI = nil
    }
}
