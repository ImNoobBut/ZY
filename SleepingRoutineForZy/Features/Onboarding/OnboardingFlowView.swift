import SwiftUI

struct OnboardingFlowView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel: OnboardingViewModel

    init(viewModel: OnboardingViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        ZStack {
            NightSkyBackground()

            VStack(spacing: 0) {
                progressIndicator
                    .padding(.top, 12)
                    .padding(.horizontal, AppTheme.horizontalPadding)

                Group {
                    switch viewModel.step {
                    case .welcome:
                        welcomePage
                    case .alarms:
                        alarmsPage
                    case .spotify:
                        spotifyPage
                    case .preferences:
                        preferencesPage(viewModel: viewModel)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: viewModel.step)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                footer
                    .padding(.horizontal, AppTheme.horizontalPadding)
                    .padding(.bottom, 24)
                    .padding(.top, 8)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                Capsule()
                    .fill(step.rawValue <= viewModel.step.rawValue ? AppTheme.accent : AppTheme.cardBackground)
                    .frame(height: 4)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel(
            String(
                localized: "onboarding.progress \(viewModel.step.rawValue + 1) of \(OnboardingStep.allCases.count)",
                defaultValue: "Step \(viewModel.step.rawValue + 1) of \(OnboardingStep.allCases.count)"
            )
        )
    }

    private var welcomePage: some View {
        OnboardingPageScaffold(
            title: String(localized: "onboarding.welcome.title", defaultValue: "Sleep better with a simple routine."),
            subtitle: String(
                localized: "onboarding.welcome.subtitle",
                defaultValue: "Set your music, sleep timer, and alarm in one place."
            )
        ) {
            EmptyView()
        }
    }

    private var alarmsPage: some View {
        OnboardingPageScaffold(
            title: String(localized: "onboarding.alarms.title", defaultValue: "Stay on schedule"),
            subtitle: String(
                localized: "onboarding.alarms.subtitle",
                defaultValue: viewModel.usesAlarmKit
                    ? "Allow wake alarms so Zy can use system alarms that break through Focus and silent mode."
                    : "Allow notifications so wake reminders can appear."
            )
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Text(
                    String(
                        localized: "onboarding.alarms.limitation",
                        defaultValue: viewModel.usesAlarmKit
                            ? "On iOS 26+, wake times use AlarmKit (system alarms). Older iOS versions use local notifications."
                            : "On this iOS version, alarms use local notifications. Delivery depends on permission and system behavior."
                    )
                )
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.tertiaryText)

                if let notificationGranted = viewModel.notificationGranted {
                    Text(
                        notificationGranted
                            ? String(
                                localized: "onboarding.alarms.granted",
                                defaultValue: viewModel.usesAlarmKit
                                    ? "Alarm access is on."
                                    : "Notifications are on."
                            )
                            : String(
                                localized: "onboarding.alarms.denied",
                                defaultValue: viewModel.usesAlarmKit
                                    ? "Alarm access is off. You can enable it later in Settings."
                                    : "Notifications are off. You can enable them later in Settings."
                            )
                    )
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.secondaryText)
                }

                if let errorMessage = viewModel.errorMessage, viewModel.step == .alarms {
                    Text(errorMessage)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.destructive)
                }
            }
        }
    }

    private var spotifyPage: some View {
        OnboardingPageScaffold(
            title: String(localized: "onboarding.spotify.title", defaultValue: "Music for bedtime"),
            subtitle: String(
                localized: "onboarding.spotify.subtitle",
                defaultValue: "Connect Spotify to choose what you listen to before sleeping."
            )
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text(
                    String(
                        localized: "onboarding.spotify.limitation",
                        defaultValue: "Sign-in uses Spotify OAuth (PKCE). Playback needs Spotify Premium and an active Spotify device on this iPhone. This app does not stream Spotify audio itself."
                    )
                )
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.tertiaryText)

                if let spotifyStatusMessage = viewModel.spotifyStatusMessage {
                    Text(spotifyStatusMessage)
                        .font(AppTheme.Typography.body)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
    }

    private func preferencesPage(viewModel: OnboardingViewModel) -> some View {
        @Bindable var viewModel = viewModel
        return OnboardingPageScaffold(
            title: String(localized: "onboarding.preferences.title", defaultValue: "Your routine"),
            subtitle: String(
                localized: "onboarding.preferences.subtitle",
                defaultValue: "Choose defaults you can change anytime."
            )
        ) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "onboarding.preferences.timer", defaultValue: "Default sleep timer"))
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.tertiaryText)
                        .textCase(.uppercase)

                    Picker(
                        String(localized: "onboarding.preferences.timer", defaultValue: "Default sleep timer"),
                        selection: $viewModel.defaultSleepTimerMinutes
                    ) {
                        ForEach(viewModel.timerChoices, id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel(String(localized: "onboarding.preferences.timer", defaultValue: "Default sleep timer"))
                }

                DatePicker(
                    String(localized: "onboarding.preferences.bedtime", defaultValue: "Preferred bedtime"),
                    selection: $viewModel.bedtime,
                    displayedComponents: .hourAndMinute
                )
                .tint(AppTheme.accent)
                .font(AppTheme.Typography.body)

                DatePicker(
                    String(localized: "onboarding.preferences.wake", defaultValue: "Preferred wake time"),
                    selection: $viewModel.wakeTime,
                    displayedComponents: .hourAndMinute
                )
                .tint(AppTheme.accent)
                .font(AppTheme.Typography.body)

                Toggle(
                    String(localized: "onboarding.preferences.default_alarm", defaultValue: "Default alarm"),
                    isOn: $viewModel.defaultAlarmEnabled
                )
                .tint(AppTheme.accent)
                .font(AppTheme.Typography.body)
                .accessibilityHint(
                    String(
                        localized: "onboarding.preferences.default_alarm.hint",
                        defaultValue: "Creates a wake alarm from your preferred wake time."
                    )
                )

                if let errorMessage = viewModel.errorMessage, viewModel.step == .preferences {
                    Text(errorMessage)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.destructive)
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            primaryAction

            if viewModel.canGoBack {
                Button(String(localized: "onboarding.back", defaultValue: "Back")) {
                    viewModel.goBack()
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityHint(String(localized: "onboarding.back.hint", defaultValue: "Go to the previous step"))
            }
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch viewModel.step {
        case .welcome:
            Button(String(localized: "onboarding.continue", defaultValue: "Continue")) {
                viewModel.goNext()
            }
            .buttonStyle(PrimaryButtonStyle())

        case .alarms:
            Button {
                Task {
                    if viewModel.notificationGranted == nil {
                        await viewModel.requestAlarmPermission()
                    }
                    viewModel.goNext()
                }
            } label: {
                if viewModel.isRequestingPermission {
                    ProgressView()
                        .tint(AppTheme.primaryText)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: AppTheme.minTouchTarget)
                } else {
                    Text(
                        viewModel.notificationGranted == nil
                            ? String(
                                localized: "onboarding.alarms.enable",
                                defaultValue: viewModel.usesAlarmKit
                                    ? "Allow alarms"
                                    : "Enable notifications"
                            )
                            : String(localized: "onboarding.continue", defaultValue: "Continue")
                    )
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(viewModel.isRequestingPermission)

        case .spotify:
            VStack(spacing: 12) {
                Button {
                    Task { await viewModel.connectSpotify() }
                } label: {
                    if viewModel.isConnectingSpotify {
                        ProgressView()
                            .tint(AppTheme.primaryText)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: AppTheme.minTouchTarget)
                    } else {
                        Text(String(localized: "onboarding.spotify.connect", defaultValue: "Connect Spotify"))
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(viewModel.isConnectingSpotify)

                Button(String(localized: "onboarding.spotify.skip", defaultValue: "Skip for now")) {
                    viewModel.skipSpotify()
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(viewModel.isConnectingSpotify)
            }

        case .preferences:
            Button {
                Task {
                    do {
                        _ = try await viewModel.finish()
                        appState.markOnboardingCompleted()
                    } catch {
                        viewModel.errorMessage = (error as? LocalizedError)?.errorDescription
                            ?? SleepRoutineError.persistenceFailed.errorDescription
                    }
                }
            } label: {
                if viewModel.isSaving {
                    ProgressView()
                        .tint(AppTheme.primaryText)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: AppTheme.minTouchTarget)
                } else {
                    Text(String(localized: "onboarding.start", defaultValue: "Start my routine"))
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(viewModel.isSaving)
        }
    }
}

private struct OnboardingPageScaffold<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(AppTheme.Typography.hero)
                    .foregroundStyle(AppTheme.primaryText)
                    .accessibilityAddTraits(.isHeader)

                Text(subtitle)
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.secondaryText)

                content
            }
            .padding(AppTheme.horizontalPadding)
            .padding(.top, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    let environment = AppEnvironment.preview()
    let viewModel = OnboardingViewModel(
        preferencesRepository: environment.preferencesRepository,
        alarmRepository: environment.alarmRepository,
        alarmAuthorization: environment.alarmAuthorization,
        spotifyService: environment.spotifyService
    )
    return OnboardingFlowView(viewModel: viewModel)
        .environment(AppState(environment: environment))
        .environment(\.appEnvironment, environment)
}
