import Foundation

/// Live Remote Admin check-in using authenticated HTTPS against the backend.
final class StatusCheckInServiceLive: StatusCheckInService {
    private let apiClient: AdminAPIClient
    private let credentialStore: any AdminCredentialStore
    private let configuration: AppConfiguration

    init(
        apiClient: AdminAPIClient,
        credentialStore: any AdminCredentialStore,
        configuration: AppConfiguration
    ) {
        self.apiClient = apiClient
        self.credentialStore = credentialStore
        self.configuration = configuration
    }

    var isRegistered: Bool {
        (try? credentialStore.loadDeviceCredentials()) != nil
    }

    var pairingCode: String? {
        try? credentialStore.loadDeviceCredentials()?.pairingCode
    }

    var deviceId: String? {
        try? credentialStore.loadDeviceCredentials()?.deviceId
    }

    func registerDevice(displayName: String) async throws {
        do {
            let response = try await apiClient.register(displayName: displayName)
            let credentials = AdminDeviceCredentials(
                deviceId: response.deviceId,
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                pairingCode: response.pairingCode,
                accessTokenExpiry: Date().addingTimeInterval(TimeInterval(response.expiresIn))
            )
            try credentialStore.saveDeviceCredentials(credentials)
        } catch let error as SleepRoutineError {
            throw error
        } catch {
            throw SleepRoutineError.adminBackendUnavailable
        }
    }

    func checkIn(_ status: DeviceStatus) async throws {
        guard var credentials = try credentialStore.loadDeviceCredentials() else {
            throw SleepRoutineError.adminNotRegistered
        }
        do {
            if credentials.accessTokenExpiry <= Date().addingTimeInterval(60) {
                credentials = try await refresh(credentials)
            }
            try await apiClient.checkIn(status: status, accessToken: credentials.accessToken)
        } catch SleepRoutineError.authenticationFailed {
            credentials = try await refresh(credentials)
            try await apiClient.checkIn(status: status, accessToken: credentials.accessToken)
        } catch let error as SleepRoutineError {
            throw error
        } catch {
            throw SleepRoutineError.networkUnavailable
        }
    }

    func clearRegistration() async throws {
        try credentialStore.clearDeviceCredentials()
        try? credentialStore.clearAdminSessionToken()
    }

    private func refresh(_ credentials: AdminDeviceCredentials) async throws -> AdminDeviceCredentials {
        let refreshed = try await apiClient.refresh(refreshToken: credentials.refreshToken)
        var updated = credentials
        updated.accessToken = refreshed.accessToken
        if let refreshToken = refreshed.refreshToken {
            updated.refreshToken = refreshToken
        }
        updated.accessTokenExpiry = Date().addingTimeInterval(TimeInterval(refreshed.expiresIn))
        try credentialStore.saveDeviceCredentials(updated)
        return updated
    }
}
