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
                let _ = environment.routineController.state
                let _ = environment.routineController.timer.isRunning
                let _ = environment.routineController.fadeStarted
                homeContent(viewModel: viewModel)
            }
        }
        .onAppear {
            if !didConfigure {
                viewModel = HomeViewModel(
                    routineController: environment.routineController,
                    preferencesRepository: environment.preferencesRepository
                )
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

                        Text(viewModel.streakText)
                            .font(AppTheme.Typography.body)
                            .foregroundStyle(AppTheme.secondaryText)

                        Text(String(localized: "home.tonight", defaultValue: "Tonight"))
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.tertiaryText)
                            .textCase(.uppercase)
                    }
                }

                if viewModel.isActive {
                    Text(viewModel.streakText)
                        .font(AppTheme.Typography.body)
                        .foregroundStyle(AppTheme.secondaryText)
                }

                CardContainer {
                    if viewModel.isActive {
                        activeStatusCard(viewModel: viewModel)
                    } else {
                        idleStatusCard(viewModel: viewModel)
                    }
                }

                if !viewModel.isActive {
                    timerPresets(viewModel: viewModel)
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

                if !viewModel.usingSpotify {
                    NavigationLink {
                        SpotifyView()
                    } label: {
                        Text(String(localized: "home.choose_spotify", defaultValue: "Choose Spotify music"))
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: AppTheme.minTouchTarget)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }

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
            NavigationLink {
                if viewModel.usingSpotify {
                    SpotifyView()
                } else {
                    QuietSoundSettingsView()
                }
            } label: {
                statusRow(
                    title: String(localized: "home.music", defaultValue: "Music"),
                    value: viewModel.musicText
                )
            }
            statusRow(
                title: String(localized: "home.sleep_timer", defaultValue: "Sleep timer"),
                value: viewModel.configuredTimerText
            )
            NavigationLink {
                BedtimeSettingsView()
            } label: {
                statusRow(
                    title: String(localized: "home.bedtime", defaultValue: "Bedtime"),
                    value: viewModel.bedtimeText
                )
            }
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

            if viewModel.isFading {
                statusRow(
                    title: String(localized: "home.audio", defaultValue: "Audio"),
                    value: String(localized: "home.fading", defaultValue: "Fading out…")
                )
            }

            statusRow(
                title: String(localized: "home.bedtime", defaultValue: "Bedtime"),
                value: viewModel.bedtimeText
            )
            statusRow(
                title: String(localized: "home.alarm", defaultValue: "Alarm"),
                value: viewModel.alarmText
            )
        }
    }

    private func timerPresets(viewModel: HomeViewModel) -> some View {
        let current = viewModel.preferences.defaultSleepTimer / 60
        return VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "home.timer_length", defaultValue: "Timer length"))
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.secondaryText)

            FlowLayout(spacing: 8) {
                ForEach(SleepTimerPreset.allCases) { preset in
                    let selected = Int(current) == preset.rawValue
                    Button {
                        viewModel.setTimerMinutes(preset.rawValue)
                    } label: {
                        Text("\(preset.rawValue) min")
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selected ? AppTheme.accent.opacity(0.35) : AppTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.primaryText)
                }
            }

            CardContainer {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Custom: \(Int(current)) min")
                        .foregroundStyle(AppTheme.primaryText)
                    Slider(
                        value: Binding(
                            get: { current },
                            set: { viewModel.setTimerMinutes(Int($0.rounded())) }
                        ),
                        in: 1...180,
                        step: 1
                    )
                    .tint(AppTheme.accent)
                }
            }
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
                .multilineTextAlignment(.trailing)
                .accessibilityLabel("\(title), \(value)")
        }
        .frame(minHeight: AppTheme.minTouchTarget)
    }
}

/// Simple wrapping layout for preset chips.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var width: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            width = max(width, x - spacing)
        }
        return (CGSize(width: width, height: y + rowHeight), frames)
    }
}

#Preview {
    let environment = AppEnvironment.preview()
    return NavigationStack {
        HomeView()
            .environment(AppState(environment: environment))
            .environment(\.appEnvironment, environment)
    }
}
