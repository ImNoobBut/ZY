import Foundation
import SwiftData
import SwiftUI

struct AppEnvironment {
    let modelContainer: ModelContainer
    let preferencesRepository: any PreferencesRepository
    let routineRepository: any RoutineRepository
    let alarmRepository: any AlarmRepository
    let historyRepository: any HistoryRepository
    let keychain: any KeychainService
    let audioService: any AudioService
    let spotifyService: any SpotifyService
    let notificationService: any NotificationService
    let alarmScheduler: any AlarmScheduler
    let deviceStatusService: any DeviceStatusService
    let statusCheckInService: any StatusCheckInService
    let adminCredentialStore: any AdminCredentialStore
    let adminMonitoring: AdminMonitoringController
    let routineController: SleepRoutineController
    let configuration: AppConfiguration

    static func live() -> AppEnvironment {
        make(configuration: AppConfiguration.fromBundle(), inMemory: false)
    }

    static func preview() -> AppEnvironment {
        make(configuration: .preview, inMemory: true)
    }

    private static func make(configuration: AppConfiguration, inMemory: Bool) -> AppEnvironment {
        let container = inMemory
            ? PersistenceController.makeInMemoryContainer()
            : PersistenceController.makeContainer()
        let context = ModelContext(container)
        let preferencesRepository = PreferencesRepositoryLive(context: context)
        let routineRepository = RoutineRepositoryLive(context: context)
        let alarmRepository = AlarmRepositoryLive(context: context)
        let historyRepository = HistoryRepositoryLive(context: context)
        let audioService: any AudioService = inMemory ? AudioServiceStub() : AudioServiceLive()
        let keychain: any KeychainService = inMemory ? KeychainServiceMemory() : KeychainServiceLive()
        let adminCredentialStore = AdminCredentialStoreLive(keychain: keychain)
        let spotifyService: any SpotifyService = {
            if inMemory {
                return SpotifyServiceStub()
            }
            let tokenStore = SpotifyKeychainTokenStore(keychain: keychain)
            let authManager = SpotifyAuthManager(
                configuration: configuration,
                tokenStore: tokenStore
            )
            let apiClient = SpotifyAPIClient(authManager: authManager)
            return SpotifyServiceLive(
                authManager: authManager,
                apiClient: apiClient,
                configuration: configuration
            )
        }()
        let notificationService: any NotificationService = inMemory
            ? NotificationServiceMock(grantResult: true, statusResult: true)
            : NotificationServiceLive()
        let alarmScheduler: any AlarmScheduler = inMemory
            ? AlarmSchedulerMock()
            : AlarmSchedulerLive(notificationService: notificationService)

        let statusCheckInService: any StatusCheckInService = {
            if inMemory {
                return StatusCheckInServiceStub(configuration: configuration)
            }
            let apiClient = AdminAPIClient(configuration: configuration)
            return StatusCheckInServiceLive(
                apiClient: apiClient,
                credentialStore: adminCredentialStore,
                configuration: configuration
            )
        }()

        let routineController = SleepRoutineController(
            preferencesRepository: preferencesRepository,
            routineRepository: routineRepository,
            alarmRepository: alarmRepository,
            historyRepository: historyRepository,
            audioService: audioService,
            spotifyService: spotifyService
        )

        let adminMonitoring = AdminMonitoringController(
            preferencesRepository: preferencesRepository,
            routineRepository: routineRepository,
            alarmRepository: alarmRepository,
            deviceStatusService: DeviceStatusServiceLive(),
            statusCheckInService: statusCheckInService,
            spotifyService: spotifyService,
            audioService: audioService,
            routineController: routineController,
            credentialStore: adminCredentialStore
        )

        return AppEnvironment(
            modelContainer: container,
            preferencesRepository: preferencesRepository,
            routineRepository: routineRepository,
            alarmRepository: alarmRepository,
            historyRepository: historyRepository,
            keychain: keychain,
            audioService: audioService,
            spotifyService: spotifyService,
            notificationService: notificationService,
            alarmScheduler: alarmScheduler,
            deviceStatusService: DeviceStatusServiceLive(),
            statusCheckInService: statusCheckInService,
            adminCredentialStore: adminCredentialStore,
            adminMonitoring: adminMonitoring,
            routineController: routineController,
            configuration: configuration
        )
    }
}

private enum AppEnvironmentKey: EnvironmentKey {
    static let defaultValue = AppEnvironment.preview()
}

extension EnvironmentValues {
    var appEnvironment: AppEnvironment {
        get { self[AppEnvironmentKey.self] }
        set { self[AppEnvironmentKey.self] = newValue }
    }
}
