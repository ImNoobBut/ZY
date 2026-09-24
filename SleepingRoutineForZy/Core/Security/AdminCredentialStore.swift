import Foundation
import CryptoKit

struct AdminDeviceCredentials: Codable, Equatable, Sendable {
    var deviceId: String
    var accessToken: String
    var refreshToken: String
    var pairingCode: String
    var accessTokenExpiry: Date
}

protocol AdminCredentialStore: AnyObject {
    func loadDeviceCredentials() throws -> AdminDeviceCredentials?
    func saveDeviceCredentials(_ credentials: AdminDeviceCredentials) throws
    func clearDeviceCredentials() throws

    func hasPIN() -> Bool
    func setPIN(_ pin: String) throws
    func verifyPIN(_ pin: String) throws -> Bool
    func clearPIN() throws

    func loadAdminSessionToken() throws -> String?
    func saveAdminSessionToken(_ token: String) throws
    func clearAdminSessionToken() throws
}

final class AdminCredentialStoreLive: AdminCredentialStore {
    private let keychain: any KeychainService
    private let credentialsKey = "admin.deviceCredentials"
    private let pinSaltKey = "admin.pinSalt"
    private let pinHashKey = "admin.pinHash"
    private let adminTokenKey = "admin.sessionToken"

    init(keychain: any KeychainService) {
        self.keychain = keychain
    }

    func loadDeviceCredentials() throws -> AdminDeviceCredentials? {
        guard let data = try keychain.data(forKey: credentialsKey) else { return nil }
        return try JSONDecoder().decode(AdminDeviceCredentials.self, from: data)
    }

    func saveDeviceCredentials(_ credentials: AdminDeviceCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        try keychain.set(data, forKey: credentialsKey)
    }

    func clearDeviceCredentials() throws {
        try keychain.delete(forKey: credentialsKey)
    }

    func hasPIN() -> Bool {
        (try? keychain.data(forKey: pinHashKey)) != nil
    }

    func setPIN(_ pin: String) throws {
        let normalized = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= 4, normalized.count <= 8, normalized.allSatisfy(\.isNumber) else {
            throw SleepRoutineError.adminPINInvalid
        }
        let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let hash = Self.hash(pin: normalized, salt: salt)
        try keychain.set(salt, forKey: pinSaltKey)
        try keychain.set(hash, forKey: pinHashKey)
    }

    func verifyPIN(_ pin: String) throws -> Bool {
        guard
            let salt = try keychain.data(forKey: pinSaltKey),
            let expected = try keychain.data(forKey: pinHashKey)
        else {
            return false
        }
        let hash = Self.hash(pin: pin.trimmingCharacters(in: .whitespacesAndNewlines), salt: salt)
        return hash == expected
    }

    func clearPIN() throws {
        try keychain.delete(forKey: pinSaltKey)
        try keychain.delete(forKey: pinHashKey)
    }

    func loadAdminSessionToken() throws -> String? {
        try keychain.string(forKey: adminTokenKey)
    }

    func saveAdminSessionToken(_ token: String) throws {
        try keychain.setString(token, forKey: adminTokenKey)
    }

    func clearAdminSessionToken() throws {
        try keychain.delete(forKey: adminTokenKey)
    }

    private static func hash(pin: String, salt: Data) -> Data {
        var combined = salt
        combined.append(Data(pin.utf8))
        let digest = SHA256.hash(data: combined)
        return Data(digest)
    }
}
