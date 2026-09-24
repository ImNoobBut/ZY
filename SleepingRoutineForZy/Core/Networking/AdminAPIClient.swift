import Foundation

/// HTTPS client for Remote Admin device registration and check-in.
actor AdminAPIClient {
    private let configuration: AppConfiguration
    private let urlSession: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(configuration: AppConfiguration, urlSession: URLSession = .shared) {
        self.configuration = configuration
        self.urlSession = urlSession
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    func register(displayName: String) async throws -> DeviceRegisterResponse {
        struct Body: Encodable { let displayName: String }
        return try await post(
            endpoint: .deviceRegister,
            body: Body(displayName: displayName),
            authorizedWith: nil
        )
    }

    func checkIn(status: DeviceStatus, accessToken: String) async throws {
        let payload = DeviceCheckInPayload(deviceStatus: status)
        var request = URLRequest(url: APIEndpoint.deviceCheckIn.url(base: configuration.backendBaseURL))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(payload)
        let (data, response) = try await urlSession.data(for: request)
        try throwIfNeeded(response: response, data: data)
    }

    func refresh(refreshToken: String) async throws -> DeviceTokenRefreshResponse {
        struct Body: Encodable { let refreshToken: String }
        return try await post(
            endpoint: .deviceRefresh,
            body: Body(refreshToken: refreshToken),
            authorizedWith: nil
        )
    }

    func pairAdmin(pairingCode: String) async throws -> AdminPairResponse {
        struct Body: Encodable { let pairingCode: String }
        return try await post(
            endpoint: .adminPair,
            body: Body(pairingCode: pairingCode),
            authorizedWith: nil
        )
    }

    func fetchStatus(deviceId: String, adminToken: String) async throws -> DeviceStatus {
        struct Envelope: Decodable { let deviceStatus: DeviceStatus }
        let envelope: Envelope = try await get(
            endpoint: .deviceStatus(id: deviceId),
            authorizedWith: adminToken
        )
        return envelope.deviceStatus
    }

    // MARK: - HTTP

    private func post<Body: Encodable, Response: Decodable>(
        endpoint: APIEndpoint,
        body: Body,
        authorizedWith token: String?
    ) async throws -> Response {
        var request = URLRequest(url: endpoint.url(base: configuration.backendBaseURL))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await urlSession.data(for: request)
        try throwIfNeeded(response: response, data: data)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw SleepRoutineError.adminBackendUnavailable
        }
    }

    private func get<Response: Decodable>(
        endpoint: APIEndpoint,
        authorizedWith token: String
    ) async throws -> Response {
        var request = URLRequest(url: endpoint.url(base: configuration.backendBaseURL))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await urlSession.data(for: request)
        try throwIfNeeded(response: response, data: data)
        return try decoder.decode(Response.self, from: data)
    }

    private func throwIfNeeded(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if (200..<300).contains(http.statusCode) { return }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw SleepRoutineError.authenticationFailed
        }
        if http.statusCode == 404 {
            throw SleepRoutineError.adminNotRegistered
        }
        _ = data
        throw SleepRoutineError.adminBackendUnavailable
    }
}
