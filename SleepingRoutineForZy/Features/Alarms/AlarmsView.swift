import SwiftUI

struct AlarmsView: View {
    @Environment(\.appEnvironment) private var environment
    @State private var viewModel: AlarmsViewModel?
    @State private var editorAlarm: SleepAlarm?
    @State private var isPresentingEditor = false
    @State private var didConfigure = false

    var body: some View {
        NavigationStack {
            ZStack {
                NightSkyBackground(showMoonAndStars: true)

                if let viewModel {
                    alarmsContent(viewModel: viewModel)
                }
            }
            .navigationTitle(String(localized: "alarms.title", defaultValue: "Alarms"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editorAlarm = nil
                        isPresentingEditor = true
                    } label: {
                        Image(systemName: "plus")
                            .frame(minWidth: AppTheme.minTouchTarget, minHeight: AppTheme.minTouchTarget)
                    }
                    .accessibilityLabel(String(localized: "alarms.add", defaultValue: "Add Alarm"))
                }
            }
            .sheet(isPresented: $isPresentingEditor) {
                if let viewModel {
                    AlarmEditorView(
                        viewModel: AlarmEditorViewModel(alarm: editorAlarm),
                        onSave: { alarm in
                            Task {
                                await viewModel.save(
                                    alarm,
                                    successInfo: String(localized: "alarms.saved", defaultValue: "Alarm saved")
                                )
                                isPresentingEditor = false
                            }
                        },
                        onCancel: { isPresentingEditor = false }
                    )
                    .presentationDetents([.large])
                }
            }
        }
        .onAppear {
            if !didConfigure {
                viewModel = AlarmsViewModel(
                    alarmRepository: environment.alarmRepository,
                    alarmScheduler: environment.alarmScheduler,
                    alarmAuthorization: environment.alarmAuthorization
                )
                didConfigure = true
            }
            Task {
                await viewModel?.refresh()
                await viewModel?.reconcileScheduledNotifications()
            }
        }
    }

    @ViewBuilder
    private func alarmsContent(viewModel: AlarmsViewModel) -> some View {
        @Bindable var viewModel = viewModel
        VStack(alignment: .leading, spacing: 12) {
            limitationBanner

            if viewModel.notificationsAllowed == false {
                permissionCard(viewModel: viewModel)
            }

            if viewModel.alarms.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(viewModel.alarms) { alarm in
                        alarmRow(alarm: alarm, viewModel: viewModel)
                            .listRowBackground(AppTheme.cardBackground)
                            .listRowSeparatorTint(AppTheme.tertiaryText.opacity(0.3))
                    }
                    .onDelete { indexSet in
                        Task {
                            for index in indexSet {
                                await viewModel.delete(viewModel.alarms[index])
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.plain)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.destructive)
                    .padding(.horizontal, AppTheme.horizontalPadding)
            }

            if let infoMessage = viewModel.infoMessage {
                Text(infoMessage)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .padding(.horizontal, AppTheme.horizontalPadding)
            }
        }
    }

    private var limitationBanner: some View {
        Text(
            String(
                localized: "alarms.limitation",
                defaultValue: viewModel?.usesAlarmKit == true
                    ? "Wake alarms use AlarmKit on iOS 26+. They can alert even in Focus or silent mode after you grant access."
                    : "These alarms use iOS notifications. Delivery depends on permission and system behavior."
            )
        )
        .font(AppTheme.Typography.caption)
        .foregroundStyle(AppTheme.secondaryText)
        .padding(.horizontal, AppTheme.horizontalPadding)
        .padding(.top, 8)
    }

    private func permissionCard(viewModel: AlarmsViewModel) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text(
                    String(
                        localized: "alarms.permission.title",
                        defaultValue: viewModel.usesAlarmKit
                            ? "Alarm access is off"
                            : "Notifications are off"
                    )
                )
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.primaryText)
                Text(
                    String(
                        localized: "alarms.permission.body",
                        defaultValue: viewModel.usesAlarmKit
                            ? "Enable alarm access so wake alarms can ring."
                            : "Enable notifications so wake reminders can appear."
                    )
                )
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.secondaryText)

                Button(
                    String(
                        localized: "alarms.permission.enable",
                        defaultValue: viewModel.usesAlarmKit
                            ? "Allow alarms"
                            : "Enable notifications"
                    )
                ) {
                    Task { await viewModel.requestPermissionIfNeeded() }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(.horizontal, AppTheme.horizontalPadding)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer(minLength: 40)
            Text(String(localized: "alarms.empty.title", defaultValue: "No alarms yet"))
                .font(AppTheme.Typography.title)
                .foregroundStyle(AppTheme.primaryText)
            Text(
                String(
                    localized: "alarms.empty.body",
                    defaultValue: "Add a wake time to keep Zy on a steady morning routine."
                )
            )
            .font(AppTheme.Typography.body)
            .foregroundStyle(AppTheme.secondaryText)

            Button(String(localized: "alarms.add", defaultValue: "Add Alarm")) {
                editorAlarm = nil
                isPresentingEditor = true
            }
            .buttonStyle(PrimaryButtonStyle())
            Spacer()
        }
        .padding(AppTheme.horizontalPadding)
    }

    private func alarmRow(alarm: SleepAlarm, viewModel: AlarmsViewModel) -> some View {
        Button {
            editorAlarm = alarm
            isPresentingEditor = true
        } label: {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AlarmsViewModel.timeText(for: alarm))
                        .font(AppTheme.Typography.title)
                        .foregroundStyle(AppTheme.primaryText)
                    Text(AlarmsViewModel.repeatSummary(for: alarm))
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                    Text(alarm.label)
                        .font(AppTheme.Typography.body)
                        .foregroundStyle(AppTheme.secondaryText)
                    Text(alarm.isEnabled
                         ? String(localized: "alarms.status.on", defaultValue: "ON")
                         : String(localized: "alarms.status.off", defaultValue: "OFF"))
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(alarm.isEnabled ? AppTheme.accentSoft : AppTheme.tertiaryText)
                        .accessibilityLabel(
                            alarm.isEnabled
                                ? String(localized: "alarms.status.on.a11y", defaultValue: "Alarm on")
                                : String(localized: "alarms.status.off.a11y", defaultValue: "Alarm off")
                        )
                }
                Spacer()
                Toggle(
                    String(localized: "alarms.toggle", defaultValue: "Enabled"),
                    isOn: Binding(
                        get: {
                            viewModel.alarms.first(where: { $0.id == alarm.id })?.isEnabled ?? alarm.isEnabled
                        },
                        set: { newValue in
                            Task { await viewModel.setEnabled(alarm, isEnabled: newValue) }
                        }
                    )
                )
                .labelsHidden()
                .tint(AppTheme.accent)
                .accessibilityLabel(
                    alarm.isEnabled
                        ? String(localized: "alarms.status.on", defaultValue: "ON")
                        : String(localized: "alarms.status.off", defaultValue: "OFF")
                )
            }
            .frame(minHeight: AppTheme.minTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    let environment = AppEnvironment.preview()
    return AlarmsView()
        .environment(AppState(environment: environment))
        .environment(\.appEnvironment, environment)
}
