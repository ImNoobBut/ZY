import SwiftUI

struct BedtimeSettingsView: View {
    @Environment(\.appEnvironment) private var environment
    @State private var bedtime = Date()
    @State private var wake = Date()
    @State private var reminderEnabled = true

    var body: some View {
        ZStack {
            NightSkyBackground()
            Form {
                Section {
                    DatePicker(
                        String(localized: "settings.bedtime.time", defaultValue: "Preferred bedtime"),
                        selection: $bedtime,
                        displayedComponents: .hourAndMinute
                    )
                    Toggle(
                        String(localized: "settings.bedtime.reminder", defaultValue: "Bedtime reminder"),
                        isOn: $reminderEnabled
                    )
                    DatePicker(
                        String(localized: "settings.bedtime.wake", defaultValue: "Preferred wake"),
                        selection: $wake,
                        displayedComponents: .hourAndMinute
                    )
                } footer: {
                    Text(
                        String(
                            localized: "settings.bedtime.footer",
                            defaultValue: "Daily notification: “Time for your sleep routine”."
                        )
                    )
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(String(localized: "settings.bedtime.title", defaultValue: "Bedtime"))
        .onAppear(perform: load)
        .onChange(of: bedtime) { _, _ in save() }
        .onChange(of: wake) { _, _ in save() }
        .onChange(of: reminderEnabled) { _, _ in save() }
    }

    private func load() {
        let prefs = environment.preferencesRepository.load()
        let calendar = Calendar.current
        let now = Date()
        bedtime = Self.date(from: prefs.preferredBedtime, fallbackHour: 22, fallbackMinute: 0, calendar: calendar, now: now)
        wake = Self.date(from: prefs.preferredWakeTime, fallbackHour: 7, fallbackMinute: 0, calendar: calendar, now: now)
        reminderEnabled = prefs.bedtimeReminderEnabled
    }

    private func save() {
        var prefs = environment.preferencesRepository.load()
        let calendar = Calendar.current
        prefs.preferredBedtime = calendar.dateComponents([.hour, .minute], from: bedtime)
        prefs.preferredWakeTime = calendar.dateComponents([.hour, .minute], from: wake)
        prefs.bedtimeReminderEnabled = reminderEnabled
        try? environment.preferencesRepository.save(prefs)
        Task {
            await BedtimeReminderScheduler.sync(from: prefs)
        }
    }

    private static func date(
        from components: DateComponents?,
        fallbackHour: Int,
        fallbackMinute: Int,
        calendar: Calendar,
        now: Date
    ) -> Date {
        var parts = DateComponents()
        parts.year = calendar.component(.year, from: now)
        parts.month = calendar.component(.month, from: now)
        parts.day = calendar.component(.day, from: now)
        parts.hour = components?.hour ?? fallbackHour
        parts.minute = components?.minute ?? fallbackMinute
        return calendar.date(from: parts) ?? now
    }
}
