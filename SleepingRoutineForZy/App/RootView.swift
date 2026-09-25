import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.appEnvironment) private var environment

    var body: some View {
        Group {
            if appState.hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingFlowView(
                    viewModel: OnboardingViewModel(
                        preferencesRepository: environment.preferencesRepository,
                        alarmRepository: environment.alarmRepository,
                        alarmAuthorization: environment.alarmAuthorization,
                        spotifyService: environment.spotifyService,
                        alarmScheduler: environment.alarmScheduler
                    )
                )
            }
        }
        .onAppear {
            appState.refreshFromPersistence()
        }
    }
}

private struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var appState = appState
        TabView(selection: $appState.selectedTab) {
            NavigationStack {
                HomeView()
            }
                .tabItem {
                    Label(
                        String(localized: "tab.home", defaultValue: "Home"),
                        systemImage: "moon.stars.fill"
                    )
                }
                .tag(AppTab.home)

            AlarmsView()
                .tabItem {
                    Label(
                        String(localized: "tab.alarms", defaultValue: "Alarms"),
                        systemImage: "alarm.fill"
                    )
                }
                .tag(AppTab.alarms)

            SettingsView()
                .tabItem {
                    Label(
                        String(localized: "tab.settings", defaultValue: "Settings"),
                        systemImage: "gearshape.fill"
                    )
                }
                .tag(AppTab.settings)
        }
        .tint(AppTheme.accent)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                appState.refreshFromPersistence()
            }
        }
    }
}

#Preview("Main") {
    let environment = AppEnvironment.preview()
    var preferences = UserPreferences.default
    preferences.hasCompletedOnboarding = true
    try? environment.preferencesRepository.save(preferences)
    return RootView()
        .environment(AppState(environment: environment))
        .environment(\.appEnvironment, environment)
        .modelContainer(environment.modelContainer)
}

#Preview("Onboarding") {
    let environment = AppEnvironment.preview()
    return RootView()
        .environment(AppState(environment: environment))
        .environment(\.appEnvironment, environment)
        .modelContainer(environment.modelContainer)
}
