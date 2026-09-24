import Foundation
import Security

protocol KeychainService: AnyObject {
    func set(_ value: Data, forKey key: String) throws
    func data(forKey key: String) throws -> Data?
    func delete(forKey key: String) throws
    func setString(_ value: String, forKey key: String) throws
    func string(forKey key: String) throws -> String?
}

enum KeychainError: Error {
    case unexpectedStatus(OSStatus)
    case encodingFailed
}

final class KeychainServiceLive: KeychainService {
    private let service: String

    init(service: String = Bundle.main.bundleIdentifier ?? "com.zy.sleepingroutine") {
        self.service = service
    }

    func set(_ value: Data, forKey key: String) throws {
        try delete(forKey: key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: value,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func data(forKey key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        return item as? Data
    }

    func delete(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func setString(_ value: String, forKey key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        try set(data, forKey: key)
    }

    func string(forKey key: String) throws -> String? {
        guard let data = try data(forKey: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// In-memory keychain for previews and unit tests. Never use for production tokens.
final class KeychainServiceMemory: KeychainService {
    private var storage: [String: Data] = [:]

    func set(_ value: Data, forKey key: String) throws {
        storage[key] = value
    }

    func data(forKey key: String) throws -> Data? {
        storage[key]
    }

    func delete(forKey key: String) throws {
        storage.removeValue(forKey: key)
    }

    func setString(_ value: String, forKey key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        try set(data, forKey: key)
    }

    func string(forKey key: String) throws -> String? {
        guard let data = try data(forKey: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

enum KeychainKey {
    static let spotifyAccessToken = "spotify.accessToken"
    static let spotifyRefreshToken = "spotify.refreshToken"
    static let spotifyTokenExpiry = "spotify.tokenExpiry"
    static let backendAccessToken = "backend.accessToken"
    static let backendRefreshToken = "backend.refreshToken"
}
