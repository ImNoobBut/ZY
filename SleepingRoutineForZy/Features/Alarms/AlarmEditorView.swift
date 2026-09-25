import SwiftUI

struct AlarmEditorView: View {
    @State private var viewModel: AlarmEditorViewModel
    let onSave: (SleepAlarm) -> Void
    let onCancel: () -> Void

    private static let dayOrder: [Weekday] = [
        .monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday
    ]

    init(
        viewModel: AlarmEditorViewModel,
        onSave: @escaping (SleepAlarm) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        NavigationStack {
            ZStack {
                NightSkyBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(String(localized: "alarms.editor.title", defaultValue: "Set alarm"))
                            .font(AppTheme.Typography.title)
                            .foregroundStyle(AppTheme.primaryText)

                        DatePicker(
                            String(localized: "alarms.editor.time", defaultValue: "Time"),
                            selection: $viewModel.timeDate,
                            displayedComponents: .hourAndMinute
                        )
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .tint(AppTheme.accent)
                        .accessibilityLabel(String(localized: "alarms.editor.time", defaultValue: "Time"))

                        VStack(alignment: .leading, spacing: 10) {
                            Text(String(localized: "alarms.editor.repeat", defaultValue: "Repeat"))
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.tertiaryText)
                                .textCase(.uppercase)

                            HStack(spacing: 8) {
                                ForEach(Self.dayOrder, id: \.rawValue) { day in
                                    dayButton(day, viewModel: viewModel)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(localized: "alarms.editor.label", defaultValue: "Label"))
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.tertiaryText)
                                .textCase(.uppercase)
                            TextField(
                                String(localized: "alarm.default_label", defaultValue: "Wake up"),
                                text: $viewModel.label
                            )
                            .textFieldStyle(.plain)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(AppTheme.cardBackground)
                            )
                            .foregroundStyle(AppTheme.primaryText)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(localized: "alarms.editor.sound", defaultValue: "Sound"))
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.tertiaryText)
                                .textCase(.uppercase)

                            Picker(
                                String(localized: "alarms.editor.sound", defaultValue: "Sound"),
                                selection: $viewModel.sound
                            ) {
                                Text(String(localized: "alarms.sound.default", defaultValue: "Default")).tag(AlarmSound.default)
                                Text(String(localized: "alarms.sound.gentle", defaultValue: "Gentle")).tag(AlarmSound.gentle)
                                Text(String(localized: "alarms.sound.chime", defaultValue: "Chime")).tag(AlarmSound.chime)
                            }
                            .pickerStyle(.segmented)
                        }

                        Toggle(
                            String(localized: "alarms.editor.vibration", defaultValue: "Vibration preference"),
                            isOn: $viewModel.vibrationEnabled
                        )
                        .tint(AppTheme.accent)
                        .foregroundStyle(AppTheme.primaryText)

                        Text(
                            String(
                                localized: "alarms.editor.vibration.note",
                                defaultValue: "iOS controls vibration with the system notification sound. This setting is saved for future use."
                            )
                        )
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.tertiaryText)

                        Toggle(
                            String(localized: "alarms.editor.enabled", defaultValue: "Alarm enabled"),
                            isOn: $viewModel.isEnabled
                        )
                        .tint(AppTheme.accent)
                        .foregroundStyle(AppTheme.primaryText)

                        Text(
                            String(
                                localized: "alarms.editor.limitation",
                                defaultValue: "Delivery depends on alarm permission and iOS scheduling."
                            )
                        )
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.secondaryText)

                        Button(String(localized: "alarms.editor.save", defaultValue: "Save Alarm")) {
                            onSave(viewModel.makeAlarm())
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    .padding(AppTheme.horizontalPadding)
                    .padding(.vertical, 16)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "alarms.editor.cancel", defaultValue: "Cancel"), action: onCancel)
                }
            }
        }
    }

    private func dayButton(_ day: Weekday, viewModel: AlarmEditorViewModel) -> some View {
        let selected = viewModel.repeatDays.contains(day.rawValue)
        return Button {
            viewModel.toggleDay(day)
        } label: {
            Text(day.shortLabel)
                .font(AppTheme.Typography.headline)
                .foregroundStyle(AppTheme.primaryText)
                .frame(maxWidth: .infinity)
                .frame(minHeight: AppTheme.minTouchTarget)
                .background(
                    Circle()
                        .fill(selected ? AppTheme.accent.opacity(0.9) : AppTheme.cardBackground)
                )
        }
        .accessibilityLabel(day.accessibilityName)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

private extension Weekday {
    var accessibilityName: String {
        switch self {
        case .sunday: return String(localized: "weekday.sunday", defaultValue: "Sunday")
        case .monday: return String(localized: "weekday.monday", defaultValue: "Monday")
        case .tuesday: return String(localized: "weekday.tuesday", defaultValue: "Tuesday")
        case .wednesday: return String(localized: "weekday.wednesday", defaultValue: "Wednesday")
        case .thursday: return String(localized: "weekday.thursday", defaultValue: "Thursday")
        case .friday: return String(localized: "weekday.friday", defaultValue: "Friday")
        case .saturday: return String(localized: "weekday.saturday", defaultValue: "Saturday")
        }
    }
}
