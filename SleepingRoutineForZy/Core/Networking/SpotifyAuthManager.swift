import AuthenticationServices
import Foundation
import UIKit

/// Handles Spotify Authorization Code + PKCE and secure token persistence.
@MainActor
final class SpotifyAuthManager: NSObject {
    private let configuration: AppConfiguration
    private let tokenStore: any SpotifyTokenStore
    private let urlSession: URLSession
    private var pendingVerifier: String?
    private var pendingState: String?
    private var authSession: ASWebAuthenticationSession?

    private let authorizeURL = URL(string: "https://accounts.spotify.com/authorize")!
    private let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!

    static let requiredScopes = [
        "user-read-private",
        "playlist-read-private",
        "playlist-read-collaborative",
        "user-modify-playback-state",
        "user-read-playback-state"
    ].joined(separator: " ")

    init(
        configuration: AppConfiguration,
        tokenStore: any SpotifyTokenStore,
        urlSession: URLSession = .shared
    ) {
        self.configuration = configuration
        self.tokenStore = tokenStore
        self.urlSession = urlSession
    }

    var isAuthenticated: Bool {
        (try? tokenStore.load()) != nil
    }

    func currentTokens() throws -> SpotifyTokenSet? {
        try tokenStore.load()
    }

    func validAccessToken() async throws -> String {
        guard var tokens = try tokenStore.load() else {
            throw SpotifyAPIError.notAuthenticated
        }
        if tokens.isExpired {
            tokens = try await refresh(tokens: tokens)
        }
        return tokens.accessToken
    }

    func authenticate() async throws {
        let clientID = configuration.spotifyClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else {
            throw SpotifyAuthError.missingClientID
        }

        let verifier = SpotifyPKCE.makeCodeVerifier()
        let challenge = SpotifyPKCE.makeCodeChallenge(from: verifier)
        let state = UUID().uuidString
        pendingVerifier = verifier
        pendingState = state

        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: configuration.spotifyRedirectURI),
            URLQueryItem(name: "scope", value: Self.requiredScopes),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "state", value: state)
        ]

        guard let authURL = components.url else {
            throw SpotifyAuthError.invalidCallback
        }

        let callbackURL = try await startWebAuth(url: authURL)
        let code = try parseAuthorizationCode(from: callbackURL, expectedState: state)
        let tokens = try await exchangeCode(code, verifier: verifier, clientID: clientID)
        try tokenStore.save(tokens)
        pendingVerifier = nil
        pendingState = nil
    }

    func logout() throws {
        try tokenStore.clear()
        pendingVerifier = nil
        pendingState = nil
    }

    private func startWebAuth(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let scheme = URL(string: configuration.spotifyRedirectURI)?.scheme ?? "sleepingroutineforzy"
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: SpotifyAuthError.invalidCallback)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            if !session.start() {
                continuation.resume(throwing: SleepRoutineError.authenticationFailed)
            }
        }
    }

    private func parseAuthorizationCode(from url: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if items.contains(where: { $0.name == "error" }) {
            throw SleepRoutineError.authenticationFailed
        }
        let state = items.first(where: { $0.name == "state" })?.value
        guard state == expectedState else {
            throw SpotifyAuthError.stateMismatch
        }
        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw SpotifyAuthError.invalidCallback
        }
        return code
    }

    private func exchangeCode(_ code: String, verifier: String, clientID: String) async throws -> SpotifyTokenSet {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": configuration.spotifyRedirectURI,
            "client_id": clientID,
            "code_verifier": verifier
        ]
        request.httpBody = body.urlEncodedFormData()

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SpotifyAuthError.tokenExchangeFailed
        }
        return try decodeTokenResponse(data)
    }

    private func refresh(tokens: SpotifyTokenSet) async throws -> SpotifyTokenSet {
        guard let refreshToken = tokens.refreshToken else {
            throw SpotifyAPIError.notAuthenticated
        }
        let clientID = configuration.spotifyClientID
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID
        ]
        request.httpBody = body.urlEncodedFormData()

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            try? tokenStore.clear()
            throw SpotifyAuthError.tokenExchangeFailed
        }
        var refreshed = try decodeTokenResponse(data)
        if refreshed.refreshToken == nil {
            refreshed.refreshToken = refreshToken
        }
        try tokenStore.save(refreshed)
        return refreshed
    }

    private func decodeTokenResponse(_ data: Data) throws -> SpotifyTokenSet {
        struct TokenResponse: Decodable {
            let accessToken: String
            let tokenType: String?
            let scope: String?
            let expiresIn: Int
            let refreshToken: String?

            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case tokenType = "token_type"
                case scope
                case expiresIn = "expires_in"
                case refreshToken = "refresh_token"
            }
        }

        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        return SpotifyTokenSet(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken,
            expiryDate: Date().addingTimeInterval(TimeInterval(decoded.expiresIn)),
            scope: decoded.scope
        )
    }
}

extension SpotifyAuthManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
            return window
        }
        return scenes.flatMap(\.windows).first ?? ASPresentationAnchor()
    }
}

private extension Dictionary where Key == String, Value == String {
    func urlEncodedFormData() -> Data {
        map { key, value in
            "\(key.urlFormEncoded)=\(value.urlFormEncoded)"
        }
        .joined(separator: "&")
        .data(using: .utf8) ?? Data()
    }
}

private extension String {
    var urlFormEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)?
            .replacingOccurrences(of: "+", with: "%2B")
            ?? self
    }
}
