import Foundation

/// Spotify Web API client using documented endpoints only.
actor SpotifyAPIClient {
    private let authManager: SpotifyAuthManager
    private let urlSession: URLSession
    private let baseURL = URL(string: "https://api.spotify.com/v1")!

    init(authManager: SpotifyAuthManager, urlSession: URLSession = .shared) {
        self.authManager = authManager
        self.urlSession = urlSession
    }

    func getCurrentUser() async throws -> SpotifyUser {
        struct MeResponse: Decodable {
            let id: String
            let displayName: String?

            enum CodingKeys: String, CodingKey {
                case id
                case displayName = "display_name"
            }
        }

        let response: MeResponse = try await get(path: "/me")
        return SpotifyUser(id: response.id, displayName: response.displayName ?? response.id)
    }

    func getPlaylists() async throws -> [SpotifyPlaylist] {
        struct PlaylistsResponse: Decodable {
            let items: [PlaylistItem]
        }
        struct PlaylistItem: Decodable {
            let id: String
            let name: String
            let uri: String
            let images: [Image]?
            let tracks: TracksRef?

            struct Image: Decodable { let url: String? }
            struct TracksRef: Decodable { let total: Int? }
        }

        let response: PlaylistsResponse = try await get(path: "/me/playlists", query: [
            URLQueryItem(name: "limit", value: "50")
        ])
        return response.items.map { item in
            SpotifyPlaylist(
                id: item.id,
                name: item.name,
                trackCount: item.tracks?.total ?? 0,
                uri: item.uri,
                imageURL: item.images?.first?.url.flatMap(URL.init(string:))
            )
        }
    }

    func getPlaylistTracks(playlistID: String) async throws -> [SpotifyTrack] {
        struct TracksResponse: Decodable {
            let items: [Item]
            struct Item: Decodable {
                let track: Track?
            }
            struct Track: Decodable {
                let id: String?
                let name: String?
                let uri: String?
                let artists: [Artist]?
            }
            struct Artist: Decodable { let name: String? }
        }

        let response: TracksResponse = try await get(path: "/playlists/\(playlistID)/tracks", query: [
            URLQueryItem(name: "limit", value: "50")
        ])
        return response.items.compactMap { item in
            guard
                let track = item.track,
                let id = track.id,
                let name = track.name,
                let uri = track.uri
            else { return nil }
            let artist = track.artists?.compactMap(\.name).joined(separator: ", ") ?? ""
            return SpotifyTrack(id: id, name: name, artistName: artist, uri: uri)
        }
    }

    func searchTracks(query: String) async throws -> [SpotifyTrack] {
        struct SearchResponse: Decodable {
            let tracks: Tracks?
            struct Tracks: Decodable { let items: [Track] }
            struct Track: Decodable {
                let id: String
                let name: String
                let uri: String
                let artists: [Artist]
            }
            struct Artist: Decodable { let name: String }
        }

        let response: SearchResponse = try await get(path: "/search", query: [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "track"),
            URLQueryItem(name: "limit", value: "20")
        ])
        return (response.tracks?.items ?? []).map { track in
            SpotifyTrack(
                id: track.id,
                name: track.name,
                artistName: track.artists.map(\.name).joined(separator: ", "),
                uri: track.uri
            )
        }
    }

    /// Starts playback on the user's active Spotify Connect device.
    /// Requires Premium and an active device (usually the Spotify app).
    func play(uri: String) async throws {
        var body: [String: Any] = [:]
        if uri.contains(":track:") {
            body["uris"] = [uri]
        } else {
            body["context_uri"] = uri
        }
        try await put(path: "/me/player/play", jsonBody: body)
    }

    func pause() async throws {
        try await put(path: "/me/player/pause", jsonBody: nil)
    }

    // MARK: - HTTP

    private func get<T: Decodable>(path: String, query: [URLQueryItem] = []) async throws -> T {
        let request = try await authorizedRequest(path: path, method: "GET", query: query)
        let (data, response) = try await urlSession.data(for: request)
        try throwIfNeeded(response: response, data: data)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SpotifyAPIError.decodingFailed
        }
    }

    private func put(path: String, jsonBody: [String: Any]?) async throws {
        var request = try await authorizedRequest(path: path, method: "PUT")
        if let jsonBody {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
        }
        let (data, response) = try await urlSession.data(for: request)
        try throwIfNeeded(response: response, data: data)
    }

    private func authorizedRequest(
        path: String,
        method: String,
        query: [URLQueryItem] = []
    ) async throws -> URLRequest {
        let token = try await authManager.validAccessToken()
        var components = URLComponents(string: "https://api.spotify.com/v1" + path)!
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else {
            throw SpotifyAPIError.decodingFailed
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func throwIfNeeded(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if (200..<300).contains(http.statusCode) { return }

        let message = String(data: data, encoding: .utf8)
        if http.statusCode == 401 {
            throw SpotifyAPIError.notAuthenticated
        }
        if http.statusCode == 403 {
            if message?.localizedCaseInsensitiveContains("premium") == true {
                throw SpotifyAPIError.premiumRequired
            }
            throw SpotifyAPIError.httpStatus(403, message)
        }
        if http.statusCode == 404 {
            // No active device is commonly returned as 404 for player endpoints.
            throw SpotifyAPIError.noActiveDevice
        }
        throw SpotifyAPIError.httpStatus(http.statusCode, message)
    }
}
