import Foundation

struct AppConfiguration: Sendable {
    var spotifyClientID: String
    var spotifyRedirectURI: String
    var backendBaseURL: URL

    static let preview = AppConfiguration(
        spotifyClientID: "",
        spotifyRedirectURI: "https://sleeping-routine-for-zy.pages.dev/callback",
        backendBaseURL: URL(string: "http://127.0.0.1:8080")!
    )

    static func fromBundle() -> AppConfiguration {
        let info = Bundle.main.infoDictionary ?? [:]
        let clientID = (info["SPOTIFY_CLIENT_ID"] as? String) ?? ""
        let redirect = (info["SPOTIFY_REDIRECT_URI"] as? String)
            ?? "https://sleeping-routine-for-zy.pages.dev/callback"
        let backendString = (info["BACKEND_BASE_URL"] as? String) ?? "http://127.0.0.1:8080"
        let backendURL = URL(string: backendString) ?? URL(string: "http://127.0.0.1:8080")!

        return AppConfiguration(
            spotifyClientID: clientID,
            spotifyRedirectURI: redirect,
            backendBaseURL: backendURL
        )
    }
}
