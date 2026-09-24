import Foundation
import CryptoKit

enum SpotifyPKCE {
    static func makeCodeVerifier(length: Int = 64) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in alphabet.randomElement(using: &generator)! })
    }

    static func makeCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64URLEncodedString()
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

struct SpotifyTokenSet: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var expiryDate: Date
    var scope: String?

    var isExpired: Bool {
        Date() >= expiryDate.addingTimeInterval(-60)
    }
}

enum SpotifyAuthError: Error {
    case missingClientID
    case invalidCallback
    case stateMismatch
    case tokenExchangeFailed
    case missingCodeVerifier
}

enum SpotifyAPIError: Error {
    case notAuthenticated
    case httpStatus(Int, String?)
    case decodingFailed
    case noActiveDevice
    case premiumRequired
}
