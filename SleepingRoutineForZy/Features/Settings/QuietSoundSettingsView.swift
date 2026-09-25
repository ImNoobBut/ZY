import SwiftUI

struct QuietSoundSettingsView: View {
    @Environment(\.appEnvironment) private var environment
    @State private var selected: QuietSound = .softTone
    @State private var previewing = false

    var body: some View {
        ZStack {
            NightSkyBackground()
            List {
                Section {
                    ForEach(QuietSound.allCases, id: \.self) { sound in
                        Button {
                            selected = sound
                            save()
                        } label: {
                            HStack {
                                Text(sound.displayName)
                                    .foregroundStyle(AppTheme.primaryText)
                                Spacer()
                                if selected == sound {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(AppTheme.accent)
                                } else {
                                    Text(String(localized: "quiet_sound.preview", defaultValue: "Preview"))
                                        .font(AppTheme.Typography.caption)
                                        .foregroundStyle(AppTheme.secondaryText)
                                        .onTapGesture {
                                            preview(sound)
                                        }
                                }
                            }
                            .frame(minHeight: AppTheme.minTouchTarget)
                        }
                    }
                } footer: {
                    Text(
                        String(
                            localized: "quiet_sound.footer",
                            defaultValue: "Used when Spotify is not selected. Soft looping tones stay on-device."
                        )
                    )
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(String(localized: "quiet_sound.title", defaultValue: "Quiet sound"))
        .onAppear {
            selected = environment.preferencesRepository.load().selectedQuietSound
        }
    }

    private func save() {
        var prefs = environment.preferencesRepository.load()
        prefs.selectedQuietSound = selected
        try? environment.preferencesRepository.save(prefs)
        environment.routineController.refreshMusicLabel()
    }

    private func preview(_ sound: QuietSound) {
        previewing = true
        do {
            try environment.audioService.prepare(sound: sound)
            try environment.audioService.play()
            Task {
                try? await Task.sleep(for: .seconds(3))
                environment.audioService.stop()
                previewing = false
            }
        } catch {
            previewing = false
        }
    }
}
