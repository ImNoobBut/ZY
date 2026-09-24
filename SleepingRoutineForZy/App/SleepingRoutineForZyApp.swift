import SwiftUI
import SwiftData

@main
struct SleepingRoutineForZyApp: App {
    @State private var appState: AppState
    private let environment: AppEnvironment

    init() {
        let environment = AppEnvironment.live()
        self.environment = environment
        _appState = State(initialValue: AppState(environment: environment))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(\.appEnvironment, environment)
                .modelContainer(environment.modelContainer)
                .preferredColorScheme(.dark)
        }
    }
}
