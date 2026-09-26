import SwiftUI

struct AdminView: View {
    @Environment(\.appEnvironment) private var environment
    @State private var viewModel: AdminViewModel?
    @State private var didConfigure = false

    var body: some View {
        ZStack {
            NightSkyBackground(showMoonAndStars: true)
            if let viewModel {
                content(viewModel: viewModel)
            }
        }
        .navigationTitle(String(localized: "admin.title", defaultValue: "Admin"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !didConfigure {
                viewModel = AdminViewModel(
                    monitoring: environment.adminMonitoring,
                    configuration: environment.configuration
                )
                didConfigure = true
            }
        }
    }

    @ViewBuilder
    private func content(viewModel: AdminViewModel) -> some View {
        @Bindable var viewModel = viewModel
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                limitationCard

                if !viewModel.hasPIN {
                    pinSetupCard(viewModel: viewModel)
                } else if !viewModel.isUnlocked {
                    unlockCard(viewModel: viewModel)
                } else {
                    monitoringCard(viewModel: viewModel)
                    statusCard(viewModel: viewModel)
                    pairingCard(viewModel: viewModel)
                    actionsCard(viewModel: viewModel)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.destructive)
                }
                if let infoMessage = viewModel.infoMessage {
                    Text(infoMessage)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            .padding(AppTheme.horizontalPadding)
            .padding(.vertical, 12)
        }
    }

    private var limitationCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "admin.limitation.title", defaultValue: "Remote monitoring"))
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.primaryText)
                Text(
                    String(
                        localized: "admin.limitation.body",
                        defaultValue: "Only opted-in status is uploaded over HTTPS. Check-ins happen when the app is active — status may be delayed when the app is not running. This is not real-time surveillance."
                    )
                )
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }

    private func pinSetupCard(viewModel: AdminViewModel) -> some View {
        @Bindable var viewModel = viewModel
        return CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "admin.pin.setup", defaultValue: "Create an Admin PIN"))
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.primaryText)
                Text(
                    String(
                        localized: "admin.pin.setup.hint",
                        defaultValue: "A 4–8 digit PIN protects Admin settings on this iPhone. It is separate from remote backend auth."
                    )
                )
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.secondaryText)

                SecureField(
                    String(localized: "admin.pin.placeholder", defaultValue: "PIN"),
                    text: $viewModel.pinInput
                )
                .keyboardType(.numberPad)
                .textFieldStyle(.plain)
                .padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(AppTheme.cardBackground.opacity(0.6)))
                .foregroundStyle(AppTheme.primaryText)

                SecureField(
                    String(localized: "admin.pin.confirm", defaultValue: "Confirm PIN"),
                    text: $viewModel.confirmPinInput
                )
                .keyboardType(.numberPad)
                .textFieldStyle(.plain)
                .padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(AppTheme.cardBackground.opacity(0.6)))
                .foregroundStyle(AppTheme.primaryText)

                Button(String(localized: "admin.pin.save", defaultValue: "Save PIN")) {
                    viewModel.setupPIN()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    private func unlockCard(viewModel: AdminViewModel) -> some View {
        @Bindable var viewModel = viewModel
        return CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "admin.unlock", defaultValue: "Enter Admin PIN"))
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.primaryText)

                SecureField(
                    String(localized: "admin.pin.placeholder", defaultValue: "PIN"),
                    text: $viewModel.pinInput
                )
                .keyboardType(.numberPad)
                .textFieldStyle(.plain)
                .padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(AppTheme.cardBackground.opacity(0.6)))
                .foregroundStyle(AppTheme.primaryText)

                Button(String(localized: "admin.unlock.action", defaultValue: "Unlock")) {
                    viewModel.unlock()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    private func monitoringCard(viewModel: AdminViewModel) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(
                    String(localized: "admin.opt_in", defaultValue: "Share status with remote Admin"),
                    isOn: Binding(
                        get: { viewModel.remoteOptIn },
                        set: { newValue in
                            Task { await viewModel.setOptIn(newValue) }
                        }
                    )
                )
                .tint(AppTheme.accent)
                .foregroundStyle(AppTheme.primaryText)

                Text(
                    String(
                        localized: "admin.backend \(viewModel.backendURLText)",
                        defaultValue: "Backend: \(viewModel.backendURLText)"
                    )
                )
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.tertiaryText)
            }
        }
    }

    private func statusCard(viewModel: AdminViewModel) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "admin.status.title", defaultValue: "Tonight’s status"))
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.primaryText)

                if let status = viewModel.latestStatus {
                    statusRow("Routine", status.routineActive ? "Active" : "Idle")
                    statusRow(
                        "Battery",
                        batteryText(status)
                    )
                    statusRow("Spotify", status.spotifyConnected ? "Connected" : "Not connected")
                    statusRow("Alarm", status.alarmEnabled ? "On" : "Off")
                    statusRow(
                        "App audio",
                        status.isPlayingOwnAudio ? "Playing" : "Stopped"
                    )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "admin.last_updated", defaultValue: "Last updated"))
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.tertiaryText)
                        .textCase(.uppercase)
                    Text(viewModel.formattedCheckIn(viewModel.lastSuccessfulCheckIn))
                        .font(AppTheme.Typography.headline)
                        .foregroundStyle(AppTheme.primaryText)
                    Text(
                        String(
                            localized: "admin.stale_warning",
                            defaultValue: "Status may be delayed when the app is not running."
                        )
                    )
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
    }

    private func pairingCard(viewModel: AdminViewModel) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "admin.pairing.title", defaultValue: "Guardian pairing code"))
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.primaryText)
                if let code = viewModel.pairingCode, viewModel.isRegistered {
                    Text(code)
                        .font(AppTheme.Typography.hero)
                        .foregroundStyle(AppTheme.accent)
                        .textSelection(.enabled)
                    Text(
                        String(
                            localized: "admin.pairing.hint",
                            defaultValue: "Guardian opens the Admin dashboard, enters this code, then can view opted-in status."
                        )
                    )
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                } else {
                    Text(
                        String(
                            localized: "admin.pairing.none",
                            defaultValue: "Turn on sharing to register this phone and get a pairing code."
                        )
                    )
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
    }

    private func actionsCard(viewModel: AdminViewModel) -> some View {
        VStack(spacing: 12) {
            Button {
                Task { await viewModel.refreshAndCheckIn() }
            } label: {
                if viewModel.isBusy {
                    ProgressView().tint(AppTheme.primaryText)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: AppTheme.minTouchTarget)
                } else {
                    Text(String(localized: "admin.check_in_now", defaultValue: "Check in now"))
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(viewModel.isBusy)

            Button(String(localized: "admin.lock", defaultValue: "Lock Admin")) {
                viewModel.lock()
            }
            .buttonStyle(SecondaryButtonStyle())

            if viewModel.isRegistered {
                Button(String(localized: "admin.disconnect", defaultValue: "Disconnect remote")) {
                    Task { await viewModel.disconnect() }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private func statusRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.secondaryText)
            Spacer()
            Text(value)
                .font(AppTheme.Typography.headline)
                .foregroundStyle(AppTheme.primaryText)
        }
        .frame(minHeight: AppTheme.minTouchTarget)
    }

    private func batteryText(_ status: DeviceStatus) -> String {
        let level = status.batteryLevel.map { "\(Int(($0 * 100).rounded()))%" } ?? "—"
        if status.isCharging == true {
            return "\(level) · Charging"
        }
        return level
    }
}

struct PrivacyView: View {
    var body: some View {
        ZStack {
            NightSkyBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(String(localized: "privacy.title", defaultValue: "Privacy"))
                        .font(AppTheme.Typography.title)
                        .foregroundStyle(AppTheme.primaryText)

                    privacySection(
                        title: String(localized: "privacy.collect.title", defaultValue: "What we collect"),
                        body: String(
                            localized: "privacy.collect.body",
                            defaultValue: "Account email and display name when you sign up (password is sent only to create a server-side hash — never stored in the app). Sleep routine and alarm settings, Spotify connection state (tokens stay in the Keychain), app-generated sleep session history, and device status fields you explicitly enable for remote Admin."
                        )
                    )

                    privacySection(
                        title: String(localized: "privacy.not_collect.title", defaultValue: "What we never collect"),
                        body: String(
                            localized: "privacy.not_collect.body",
                            defaultValue: "Messages, browsing history, keystrokes, other apps’ private content, microphone, camera, location, or screen contents. We never store your account password in plaintext."
                        )
                    )

                    privacySection(
                        title: String(localized: "privacy.remote.title", defaultValue: "Remote Admin"),
                        body: String(
                            localized: "privacy.remote.body",
                            defaultValue: "Remote monitoring is off by default. When you opt in, status is sent only to your configured backend over HTTPS. Tokens stay in the Keychain. You can disconnect anytime."
                        )
                    )
                }
                .padding(AppTheme.horizontalPadding)
                .padding(.vertical, 12)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func privacySection(title: String, body: String) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.primaryText)
                Text(body)
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }
}

#Preview {
    NavigationStack {
        AdminView()
            .environment(\.appEnvironment, AppEnvironment.preview())
    }
}
