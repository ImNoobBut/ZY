import XCTest
@testable import SleepingRoutineForZy

final class AdminCredentialStoreTests: XCTestCase {
    func testPINRoundTrip() throws {
        let store = AdminCredentialStoreLive(keychain: KeychainServiceMemory())
        XCTAssertFalse(store.hasPIN())
        try store.setPIN("2468")
        XCTAssertTrue(store.hasPIN())
        XCTAssertTrue(try store.verifyPIN("2468"))
        XCTAssertFalse(try store.verifyPIN("0000"))
    }

    func testInvalidPINRejected() {
        let store = AdminCredentialStoreLive(keychain: KeychainServiceMemory())
        XCTAssertThrowsError(try store.setPIN("12")) { error in
            XCTAssertEqual(error as? SleepRoutineError, .adminPINInvalid)
        }
        XCTAssertThrowsError(try store.setPIN("abcd")) { error in
            XCTAssertEqual(error as? SleepRoutineError, .adminPINInvalid)
        }
    }

    func testDeviceCredentialsPersisted() throws {
        let store = AdminCredentialStoreLive(keychain: KeychainServiceMemory())
        let credentials = AdminDeviceCredentials(
            deviceId: "dev-1",
            accessToken: "a",
            refreshToken: "r",
            pairingCode: "123456",
            accessTokenExpiry: Date().addingTimeInterval(3600)
        )
        try store.saveDeviceCredentials(credentials)
        XCTAssertEqual(try store.loadDeviceCredentials()?.pairingCode, "123456")
        try store.clearDeviceCredentials()
        XCTAssertNil(try store.loadDeviceCredentials())
    }
}

@MainActor
final class AdminMonitoringControllerTests: XCTestCase {
    func testOptInRegisterAndCheckIn() async throws {
        let environment = AppEnvironment.preview()
        let monitoring = environment.adminMonitoring
        let checkIn = environment.statusCheckInService as! StatusCheckInServiceStub

        try monitoring.setPIN("1357")
        XCTAssertTrue(try monitoring.unlock(with: "1357"))

        try monitoring.setOptIn(true)
        await monitoring.registerIfNeeded()
        XCTAssertTrue(monitoring.isRegistered)
        XCTAssertNotNil(monitoring.pairingCode)

        await monitoring.checkInIfNeeded()
        XCTAssertNotNil(checkIn.lastCheckIn)
        XCTAssertNotNil(environment.preferencesRepository.load().lastSuccessfulCheckIn)
        XCTAssertNil(monitoring.lastError)
    }

    func testCheckInSkippedWhenNotOptedIn() async throws {
        let environment = AppEnvironment.preview()
        let monitoring = environment.adminMonitoring
        let checkIn = environment.statusCheckInService as! StatusCheckInServiceStub

        try monitoring.setOptIn(false)
        await monitoring.registerIfNeeded()
        XCTAssertEqual(monitoring.lastError, .adminNotOptedIn)
        await monitoring.checkInIfNeeded()
        XCTAssertNil(checkIn.lastCheckIn)
    }

    func testBuildStatusIncludesRoutineFields() {
        let environment = AppEnvironment.preview()
        let status = environment.adminMonitoring.buildCurrentStatus()
        XCTAssertFalse(status.routineActive)
        XCTAssertNotNil(status.lastCheckIn)
    }
}

final class APIEndpointTests: XCTestCase {
    func testCheckInURL() {
        let base = URL(string: "http://127.0.0.1:8080")!
        let url = APIEndpoint.deviceCheckIn.url(base: base)
        XCTAssertEqual(url.absoluteString, "http://127.0.0.1:8080/v1/devices/check-in")
    }
}
