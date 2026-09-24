import Foundation

/// REST paths for the Remote Admin backend.
enum APIEndpoint {
    case deviceRegister
    case deviceCheckIn
    case deviceRefresh
    case deviceStatus(id: String)
    case adminPair

    var path: String {
        switch self {
        case .deviceRegister:
            return "/v1/devices/register"
        case .deviceCheckIn:
            return "/v1/devices/check-in"
        case .deviceRefresh:
            return "/v1/devices/refresh"
        case .deviceStatus(let id):
            return "/v1/devices/\(id)/status"
        case .adminPair:
            return "/v1/admin/pair"
        }
    }

    func url(base: URL) -> URL {
        URL(string: path, relativeTo: base)!.absoluteURL
    }
}

struct DeviceRegisterResponse: Codable, Equatable, Sendable {
    let deviceId: String
    let accessToken: String
    let refreshToken: String
    let pairingCode: String
    let expiresIn: Int
}

struct DeviceTokenRefreshResponse: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
}

struct AdminPairResponse: Codable, Equatable, Sendable {
    let adminToken: String
    let deviceId: String
    let expiresIn: Int
}

struct DeviceCheckInPayload: Codable, Equatable, Sendable {
    let deviceStatus: DeviceStatus
}
