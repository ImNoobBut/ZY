import Foundation

protocol SpotifyTokenStore: AnyObject {
    func load() throws -> SpotifyTokenSet?
    func save(_ tokens: SpotifyTokenSet) throws
    func clear() throws
}

final class SpotifyKeychainTokenStore: SpotifyTokenStore {
    private let keychain: any KeychainService
    private let storageKey = "spotify.tokenSet"

    init(keychain: any KeychainService) {
        self.keychain = keychain
    }

    func load() throws -> SpotifyTokenSet? {
        guard let data = try keychain.data(forKey: storageKey) else { return nil }
        return try JSONDecoder().decode(SpotifyTokenSet.self, from: data)
    }

    func save(_ tokens: SpotifyTokenSet) throws {
        let data = try JSONEncoder().encode(tokens)
        try keychain.set(data, forKey: storageKey)
        // Keep legacy individual keys cleared so tokens never linger in plain form elsewhere.
        try? keychain.delete(forKey: KeychainKey.spotifyAccessToken)
        try? keychain.delete(forKey: KeychainKey.spotifyRefreshToken)
        try? keychain.delete(forKey: KeychainKey.spotifyTokenExpiry)
    }

    func clear() throws {
        try keychain.delete(forKey: storageKey)
        try? keychain.delete(forKey: KeychainKey.spotifyAccessToken)
        try? keychain.delete(forKey: KeychainKey.spotifyRefreshToken)
        try? keychain.delete(forKey: KeychainKey.spotifyTokenExpiry)
    }
}

final class SpotifyTokenStoreMemory: SpotifyTokenStore {
    private var tokens: SpotifyTokenSet?

    func load() throws -> SpotifyTokenSet? { tokens }

    func save(_ tokens: SpotifyTokenSet) throws {
        self.tokens = tokens
    }

    func clear() throws {
        tokens = nil
    }
}
