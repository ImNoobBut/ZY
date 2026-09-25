import SwiftUI

struct SettingsView: View {
    @Environment(\.appEnvironment) private var environment

    var body: some View {
        NavigationStack {
            ZStack {
                NightSkyBackground()
                List {
                    Section {
                        NavigationLink {
                            BedtimeSettingsView()
                        } label: {
                            settingsRow(
                                String(localized: "settings.bedtime", defaultValue: "Bedtime"),
                                subtitle: bedtimeSubtitle
                            )
                        }
                        NavigationLink {
                            QuietSoundSettingsView()
                        } label: {
                            settingsRow(
                                String(localized: "settings.quiet_sound", defaultValue: "Quiet sound"),
                                subtitle: environment.preferencesRepository.load().selectedQuietSound.displayName
                            )
                        }
                        NavigationLink {
                            SleepHistoryView()
                        } label: {
                            settingsRow(
                                String(localized: "settings.history", defaultValue: "Sleep history"),
                                subtitle: streakSubtitle
                            )
                        }
                        NavigationLink {
                            SpotifyView()
                        } label: {
                            Text(String(localized: "settings.spotify", defaultValue: "Spotify"))
                                .foregroundStyle(AppTheme.primaryText)
                                .frame(minHeight: AppTheme.minTouchTarget, alignment: .leading)
                        }
                    }

                    Section {
                        NavigationLink {
                            AdminView()
                        } label: {
                            Text(String(localized: "settings.admin", defaultValue: "Admin"))
                                .foregroundStyle(AppTheme.primaryText)
                                .frame(minHeight: AppTheme.minTouchTarget, alignment: .leading)
                        }
                        NavigationLink {
                            PrivacyView()
                        } label: {
                            Text(String(localized: "settings.privacy", defaultValue: "Privacy"))
                                .foregroundStyle(AppTheme.primaryText)
                                .frame(minHeight: AppTheme.minTouchTarget, alignment: .leading)
                        }
                        settingsLabel(
                            String(localized: "settings.about", defaultValue: "About")
                        )
                    }

                    Section {
                        Text(String(localized: "settings.reset", defaultValue: "Reset app data"))
                            .foregroundStyle(AppTheme.destructive)
                    } footer: {
                        Text(
                            String(
                                localized: "settings.reset.footer",
                                defaultValue: "Reset requires confirmation in a later phase. Destructive actions are never one tap away."
                            )
                        )
                    }
                }
                .scrollContentBackground(.hidden)
                .navigationTitle(String(localized: "settings.title", defaultValue: "Settings"))
            }
        }
    }

    private var bedtimeSubtitle: String {
        let prefs = environment.preferencesRepository.load()
        let reminder = prefs.bedtimeReminderEnabled
            ? String(localized: "home.reminder.on", defaultValue: "Reminder on")
            : String(localized: "home.reminder.off", defaultValue: "Reminder off")
        return "\(prefs.preferredBedtimeLabel) · \(reminder)"
    }

    private var streakSubtitle: String {
        let streak = environment.routineController.currentStreak
        if streak > 0 {
            return String(localized: "home.streak.count \(streak)", defaultValue: "\(streak)-night streak")
        }
        return String(localized: "home.streak.empty", defaultValue: "Start tonight’s streak")
    }

    private func settingsLabel(_ title: String) -> some View {
        Text(title)
            .foregroundStyle(AppTheme.primaryText)
            .frame(minHeight: AppTheme.minTouchTarget, alignment: .leading)
    }

    private func settingsRow(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .foregroundStyle(AppTheme.primaryText)
            Text(subtitle)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(minHeight: AppTheme.minTouchTarget, alignment: .leading)
    }
}
