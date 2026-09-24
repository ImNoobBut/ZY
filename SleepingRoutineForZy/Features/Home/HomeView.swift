import SwiftUI

struct HomeView: View {
    @Environment(\.appEnvironment) private var environment
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: HomeViewModel?
    @State private var didConfigure = false

    var body: some View {
        ZStack {
            NightSkyBackground(showMoonAndStars: true)

            if let viewModel {
                // Touch controller fields so Observation refreshes when routine state changes.
                let _ = environment.routineController.state
                let _ = environment.routineController.timer.isRunning
                homeContent(viewModel: viewModel)
            }
        }
        .onAppear {
            if !didConfigure {
                viewModel = HomeViewModel(routineController: environment.routineController)
                didConfigure = true
            }
            viewModel?.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                viewModel?.refresh()
            }
        }
    }

    @ViewBuilder
    private func homeContent(viewModel: HomeViewModel) -> some View {
        @Bindable var viewModel = viewModel
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if viewModel.isActive {
                    Text(String(localized: "home.active.title", defaultValue: "Sleep routine active"))
                        .font(AppTheme.Typography.hero)
                        .foregroundStyle(AppTheme.primaryText)
                        .accessibilityAddTraits(.isHeader)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "home.greeting", defaultValue: "Good evening, Zy"))
                            .font(AppTheme.Typography.hero)
                            .foregroundStyle(AppTheme.primaryText)
                            .accessibilityAddTraits(.isHeader)

                        Text(String(localized: "home.tonight", defaultValue: "Tonight"))
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.tertiaryText)
                            .textCase(.uppercase)
                    }
                }

                CardContainer {
                    if viewModel.isActive {
                        activeStatusCard(viewModel: viewModel)
                    } else {
                        idleStatusCard(viewModel: viewModel)
                    }
                }

                Button {
                    Task {
                        if viewModel.isActive {
                            await viewModel.end()
                        } else {
                            await viewModel.start()
                        }
                    }
                } label: {
                    if viewModel.isBusy {
                        ProgressView()
                            .tint(AppTheme.primaryText)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: AppTheme.minTouchTarget)
                    } else {
                        Text(
                            viewModel.isActive
                                ? String(localized: "home.end_routine", defaultValue: "End Routine")
                                : String(localized: "home.start_routine", defaultValue: "Start Sleep Routine")
                        )
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(viewModel.isBusy)

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.destructive)
                }

                Text(
                    String(
                        localized: "home.timer.source_of_truth",
                        defaultValue: "The sleep timer uses saved start and end times, so it stays accurate after leaving the app."
                    )
                )
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.tertiaryText)
            }
            .padding(AppTheme.horizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .task(id: viewModel.isActive) {
            guard viewModel.isActive else { return }
            while !Task.isCancelled {
                await viewModel.tick(now: Date())
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func idleStatusCard(viewModel: HomeViewModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            statusRow(
                title: String(localized: "home.routine", defaultValue: "Sleep routine"),
                value: viewModel.routineStatusText
            )
            statusRow(
                title: String(localized: "home.music", defaultValue: "Music"),
                value: viewModel.musicText
            )
            statusRow(
                title: String(localized: "home.sleep_timer", defaultValue: "Sleep timer"),
                value: viewModel.configuredTimerText
            )
            statusRow(
                title: String(localized: "home.alarm", defaultValue: "Alarm"),
                value: viewModel.alarmText
            )
        }
    }

    private func activeStatusCard(viewModel: HomeViewModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            statusRow(
                title: String(localized: "home.playing", defaultValue: "Playing"),
                value: viewModel.musicText
            )

            TimelineView(.periodic(from: .now, by: 1)) { context in
                statusRow(
                    title: String(localized: "home.music_stops_in", defaultValue: "Music stops in"),
                    value: viewModel.remainingText(at: context.date)
                )
            }

            statusRow(
                title: String(localized: "home.alarm", defaultValue: "Alarm"),
                value: viewModel.alarmText
            )
        }
    }

    private func statusRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.secondaryText)
            Spacer()
            Text(value)
                .font(AppTheme.Typography.headline)
                .foregroundStyle(AppTheme.primaryText)
                .accessibilityLabel("\(title), \(value)")
        }
        .frame(minHeight: AppTheme.minTouchTarget)
    }
}

#Preview {
    let environment = AppEnvironment.preview()
    return HomeView()
        .environment(AppState(environment: environment))
        .environment(\.appEnvironment, environment)
}
