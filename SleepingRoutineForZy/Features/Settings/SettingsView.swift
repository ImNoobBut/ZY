import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                NightSkyBackground()
                List {
                    Section {
                        settingsLabel(
                            String(localized: "settings.sleep_routine", defaultValue: "Sleep routine")
                        )
                        NavigationLink {
                            SpotifyView()
                        } label: {
                            Text(String(localized: "settings.spotify", defaultValue: "Spotify"))
                                .foregroundStyle(AppTheme.primaryText)
                                .frame(minHeight: AppTheme.minTouchTarget, alignment: .leading)
                        }
                        settingsLabel(
                            String(localized: "settings.alarms", defaultValue: "Alarms")
                        )
                        settingsLabel(
                            String(localized: "settings.notifications", defaultValue: "Notifications")
                        )
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

    private func settingsLabel(_ title: String) -> some View {
        Text(title)
            .foregroundStyle(AppTheme.primaryText)
            .frame(minHeight: AppTheme.minTouchTarget, alignment: .leading)
    }
}
