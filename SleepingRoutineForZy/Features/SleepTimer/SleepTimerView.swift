import SwiftUI

struct SleepTimerView: View {
    @Environment(\.appEnvironment) private var environment
    @State private var viewModel: SleepTimerViewModel?
    @State private var didConfigure = false

    var body: some View {
        ZStack {
            NightSkyBackground(showMoonAndStars: true)

            if let viewModel {
                content(viewModel: viewModel)
            }
        }
        .onAppear {
            if !didConfigure {
                viewModel = SleepTimerViewModel(
                    preferencesRepository: environment.preferencesRepository,
                    routineController: environment.routineController
                )
                didConfigure = true
            } else {
                viewModel?.loadFromPreferences()
            }
        }
    }

    @ViewBuilder
    private func content(viewModel: SleepTimerViewModel) -> some View {
        @Bindable var viewModel = viewModel
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(String(localized: "sleep.title", defaultValue: "Sleep"))
                    .font(AppTheme.Typography.hero)
                    .foregroundStyle(AppTheme.primaryText)
                    .accessibilityAddTraits(.isHeader)

                Text(
                    String(
                        localized: "sleep.subtitle",
                        defaultValue: "Choose when music should stop. The countdown is based on saved times, not an in-memory timer."
                    )
                )
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.secondaryText)

                if let remaining = viewModel.remainingText {
                    CardContainer {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(localized: "sleep.active_remaining", defaultValue: "Music stops in"))
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.tertiaryText)
                                .textCase(.uppercase)
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                Text(
                                    environment.routineController.timer.remaining(at: context.date).mmssCountdown
                                )
                                .font(AppTheme.Typography.title)
                                .foregroundStyle(AppTheme.primaryText)
                                .accessibilityLabel("Remaining \(remaining)")
                            }
                        }
                    }
                }

                CardContainer {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(String(localized: "sleep.presets", defaultValue: "Presets"))
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.tertiaryText)
                            .textCase(.uppercase)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(SleepTimerPreset.allCases) { preset in
                                presetButton(
                                    title: "\(preset.rawValue) min",
                                    isSelected: !viewModel.isCustomSelected && viewModel.selectedPreset == preset
                                ) {
                                    viewModel.selectPreset(preset)
                                }
                            }

                            presetButton(
                                title: String(localized: "sleep.custom", defaultValue: "Custom"),
                                isSelected: viewModel.isCustomSelected
                            ) {
                                viewModel.selectCustom()
                            }
                        }

                        if viewModel.isCustomSelected {
                            Stepper(
                                value: $viewModel.customMinutes,
                                in: 1...180,
                                step: 1
                            ) {
                                Text(
                                    String(
                                        localized: "sleep.custom_minutes \(viewModel.customMinutes)",
                                        defaultValue: "\(viewModel.customMinutes) minutes"
                                    )
                                )
                                .font(AppTheme.Typography.body)
                                .foregroundStyle(AppTheme.primaryText)
                            }
                            .tint(AppTheme.accent)
                            .accessibilityHint(
                                String(
                                    localized: "sleep.custom.hint",
                                    defaultValue: "Choose between 1 and 180 minutes"
                                )
                            )
                        }
                    }
                }

                Button(String(localized: "sleep.save", defaultValue: "Save as default")) {
                    viewModel.saveDefault()
                }
                .buttonStyle(PrimaryButtonStyle())

                if let saveMessage = viewModel.saveMessage {
                    Text(saveMessage)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.destructive)
                }
            }
            .padding(AppTheme.horizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
    }

    private func presetButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppTheme.Typography.headline)
                .foregroundStyle(AppTheme.primaryText)
                .frame(maxWidth: .infinity)
                .frame(minHeight: AppTheme.minTouchTarget)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isSelected ? AppTheme.accent.opacity(0.9) : AppTheme.cardBackground)
                )
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    let environment = AppEnvironment.preview()
    return SleepTimerView()
        .environment(AppState(environment: environment))
        .environment(\.appEnvironment, environment)
}
