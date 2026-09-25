import SwiftUI

struct SleepHistoryView: View {
    @Environment(\.appEnvironment) private var environment
    @State private var sessions: [SleepSessionRecord] = []
    @State private var streak = 0

    var body: some View {
        ZStack {
            NightSkyBackground()
            List {
                Section {
                    Text(
                        streak > 0
                            ? String(
                                localized: "history.streak \(streak)",
                                defaultValue: "Current streak: \(streak) night\(streak == 1 ? "" : "s")"
                              )
                            : String(
                                localized: "history.streak.empty",
                                defaultValue: "No streak yet — start a routine tonight."
                              )
                    )
                    .foregroundStyle(AppTheme.primaryText)
                }

                Section {
                    if sessions.isEmpty {
                        Text(
                            String(
                                localized: "history.empty",
                                defaultValue: "Completed routines will appear here."
                            )
                        )
                        .foregroundStyle(AppTheme.secondaryText)
                    } else {
                        ForEach(sessions.prefix(14)) { session in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                                    .foregroundStyle(AppTheme.primaryText)
                                Text(durationLabel(session))
                                    .font(AppTheme.Typography.caption)
                                    .foregroundStyle(AppTheme.secondaryText)
                                if let notes = session.notes, !notes.isEmpty {
                                    Text(notes)
                                        .font(AppTheme.Typography.caption)
                                        .foregroundStyle(AppTheme.tertiaryText)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(String(localized: "history.title", defaultValue: "Sleep history"))
        .onAppear(perform: reload)
    }

    private func reload() {
        sessions = environment.historyRepository.fetchRecent(limit: 60)
        let prefs = environment.preferencesRepository.load()
        streak = StreakCalculator.currentStreak(
            sessions: sessions,
            bedtimeHour: prefs.preferredBedtime?.hour ?? 22,
            bedtimeMinute: prefs.preferredBedtime?.minute ?? 0
        )
    }

    private func durationLabel(_ session: SleepSessionRecord) -> String {
        guard let end = session.completedAt ?? session.musicStoppedAt else {
            return String(localized: "history.incomplete", defaultValue: "Incomplete")
        }
        let mins = Int(end.timeIntervalSince(session.startedAt) / 60)
        if mins < 1 {
            return String(localized: "history.under_one", defaultValue: "Under 1 min")
        }
        return String(localized: "history.minutes \(mins)", defaultValue: "\(mins) min")
    }
}
