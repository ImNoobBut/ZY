import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class AdminViewModel {
    var pinInput = ""
    var confirmPinInput = ""
    var isUnlocked = false
    var isBusy = false
    var remoteOptIn = false
    var errorMessage: String?
    var infoMessage: String?
    var latestStatus: DeviceStatus?

    private let monitoring: AdminMonitoringController
    private let configuration: AppConfiguration

    init(monitoring: AdminMonitoringController, configuration: AppConfiguration) {
        self.monitoring = monitoring
        self.configuration = configuration
        remoteOptIn = monitoring.isOptedIn
        latestStatus = monitoring.buildCurrentStatus()
    }

    var hasPIN: Bool { monitoring.hasPIN }
    var isRegistered: Bool { monitoring.isRegistered }
    var pairingCode: String? { monitoring.pairingCode }
    var lastSuccessfulCheckIn: Date? { monitoring.lastSuccessfulCheckIn }
    var backendURLText: String { configuration.backendBaseURL.absoluteString }

    func setupPIN() {
        errorMessage = nil
        do {
            guard pinInput == confirmPinInput else {
                errorMessage = SleepRoutineError.adminPINIncorrect.errorDescription
                return
            }
            try monitoring.setPIN(pinInput)
            pinInput = ""
            confirmPinInput = ""
            isUnlocked = true
            infoMessage = String(localized: "admin.pin.set", defaultValue: "Admin PIN saved on this iPhone.")
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
        }
    }

    func unlock() {
        errorMessage = nil
        do {
            _ = try monitoring.unlock(with: pinInput)
            pinInput = ""
            isUnlocked = true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? SleepRoutineError.adminPINIncorrect.errorDescription
        }
    }

    func lock() {
        isUnlocked = false
        pinInput = ""
        confirmPinInput = ""
    }

    func setOptIn(_ enabled: Bool) async {
        errorMessage = nil
        infoMessage = nil
        do {
            try monitoring.setOptIn(enabled)
            remoteOptIn = enabled
            if enabled {
                await monitoring.registerIfNeeded()
                await monitoring.checkInIfNeeded()
                if let error = monitoring.lastError {
                    errorMessage = error.errorDescription
                } else {
                    infoMessage = String(
                        localized: "admin.opt_in.enabled",
                        defaultValue: "Remote monitoring is on. Share the pairing code with your guardian."
                    )
                }
            } else {
                infoMessage = String(
                    localized: "admin.opt_in.disabled",
                    defaultValue: "Remote monitoring is off. No new status will be uploaded."
                )
            }
            latestStatus = monitoring.buildCurrentStatus()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
        }
    }

    func refreshAndCheckIn() async {
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        latestStatus = monitoring.buildCurrentStatus()
        if monitoring.isOptedIn {
            if !monitoring.isRegistered {
                await monitoring.registerIfNeeded()
            }
            await monitoring.checkInIfNeeded()
            if let error = monitoring.lastError {
                errorMessage = error.errorDescription
            } else {
                infoMessage = String(
                    localized: "admin.check_in.ok",
                    defaultValue: "Status sent to the Admin backend."
                )
            }
        }
    }

    func disconnect() async {
        await monitoring.disconnectRemote()
        remoteOptIn = false
        latestStatus = monitoring.buildCurrentStatus()
        infoMessage = String(
            localized: "admin.disconnected",
            defaultValue: "Device unregistered. Remote monitoring is off."
        )
    }

    func formattedCheckIn(_ date: Date?) -> String {
        guard let date else {
            return String(localized: "admin.never_checked_in", defaultValue: "Never")
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
