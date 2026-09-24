import SwiftUI

struct SpotifyView: View {
    @Environment(\.appEnvironment) private var environment
    @State private var viewModel: SpotifyViewModel?
    @State private var didConfigure = false

    var body: some View {
        ZStack {
            NightSkyBackground(showMoonAndStars: true)
            if let viewModel {
                content(viewModel: viewModel)
            }
        }
        .navigationTitle(String(localized: "spotify.title", defaultValue: "Spotify"))
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            if !didConfigure {
                viewModel = SpotifyViewModel(
                    spotifyService: environment.spotifyService,
                    preferencesRepository: environment.preferencesRepository,
                    configuration: environment.configuration
                )
                didConfigure = true
            }
            Task { await viewModel?.refresh() }
        }
    }

    @ViewBuilder
    private func content(viewModel: SpotifyViewModel) -> some View {
        @Bindable var viewModel = viewModel
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                limitationCard

                if viewModel.isAuthenticated {
                    connectedHeader(viewModel: viewModel)
                    selectionCard(viewModel: viewModel)
                    searchSection(viewModel: viewModel)
                    playlistsSection(viewModel: viewModel)
                } else {
                    disconnectedCard(viewModel: viewModel)
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
                Text(String(localized: "spotify.limitation.title", defaultValue: "How Spotify works here"))
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.primaryText)
                Text(
                    String(
                        localized: "spotify.limitation.body",
                        defaultValue: "Sign-in uses Spotify’s OAuth (PKCE). Playback uses Spotify’s Web API on an active Spotify device and typically requires Premium. This app does not stream Spotify audio itself or stop other apps arbitrarily."
                    )
                )
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }

    private func disconnectedCard(viewModel: SpotifyViewModel) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 16) {
                Text(String(localized: "spotify.not_connected", defaultValue: "Spotify isn’t connected."))
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.primaryText)

                Button {
                    Task { await viewModel.connect() }
                } label: {
                    if viewModel.isBusy {
                        ProgressView().tint(AppTheme.primaryText)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: AppTheme.minTouchTarget)
                    } else {
                        Text(String(localized: "spotify.connect", defaultValue: "Connect Spotify"))
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(viewModel.isBusy)
            }
        }
    }

    private func connectedHeader(viewModel: SpotifyViewModel) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(String(localized: "spotify.connected_check", defaultValue: "Connected ✓"))
                        .font(AppTheme.Typography.headline)
                        .foregroundStyle(AppTheme.primaryText)
                    Spacer()
                }
                if let name = viewModel.userDisplayName {
                    Text(name)
                        .font(AppTheme.Typography.body)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Button(String(localized: "spotify.disconnect", defaultValue: "Disconnect")) {
                    Task { await viewModel.disconnect() }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private func selectionCard(viewModel: SpotifyViewModel) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "spotify.tonight", defaultValue: "For bedtime"))
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.tertiaryText)
                    .textCase(.uppercase)
                Text(viewModel.selectedTitle
                     ?? String(localized: "spotify.none_selected", defaultValue: "Nothing selected yet"))
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.primaryText)

                Button {
                    Task { await viewModel.playSelected() }
                } label: {
                    Text(String(localized: "spotify.play", defaultValue: "Play"))
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(viewModel.isBusy)
            }
        }
    }

    private func searchSection(viewModel: SpotifyViewModel) -> some View {
        @Bindable var viewModel = viewModel
        return VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "spotify.search", defaultValue: "Search music"))
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.tertiaryText)
                .textCase(.uppercase)

            HStack {
                TextField(
                    String(localized: "spotify.search.placeholder", defaultValue: "Search"),
                    text: $viewModel.searchQuery
                )
                .textFieldStyle(.plain)
                .padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(AppTheme.cardBackground))
                .foregroundStyle(AppTheme.primaryText)

                Button(String(localized: "spotify.search.action", defaultValue: "Search")) {
                    Task { await viewModel.search() }
                }
                .buttonStyle(SecondaryButtonStyle())
                .frame(width: 100)
            }

            ForEach(viewModel.searchResults) { track in
                Button {
                    viewModel.select(track: track)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.name)
                            .font(AppTheme.Typography.body)
                            .foregroundStyle(AppTheme.primaryText)
                        Text(track.artistName)
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func playlistsSection(viewModel: SpotifyViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "spotify.playlists", defaultValue: "Your playlists"))
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.tertiaryText)
                .textCase(.uppercase)

            ForEach(viewModel.playlists) { playlist in
                HStack(alignment: .center, spacing: 12) {
                    NavigationLink {
                        SpotifyPlaylistDetailView(playlist: playlist)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(playlist.name)
                                .font(AppTheme.Typography.headline)
                                .foregroundStyle(AppTheme.primaryText)
                            Text("\(playlist.trackCount) tracks")
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(String(localized: "spotify.select", defaultValue: "Select")) {
                        viewModel.select(playlist: playlist)
                    }
                    .buttonStyle(.bordered)
                    .tint(AppTheme.accent)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 16).fill(AppTheme.cardBackground))
            }
        }
    }
}

struct SpotifyPlaylistDetailView: View {
    @Environment(\.appEnvironment) private var environment
    let playlist: SpotifyPlaylist
    @State private var tracks: [SpotifyTrack] = []
    @State private var errorMessage: String?
    @State private var infoMessage: String?

    var body: some View {
        ZStack {
            NightSkyBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(playlist.name)
                        .font(AppTheme.Typography.title)
                        .foregroundStyle(AppTheme.primaryText)
                    Text("\(playlist.trackCount) tracks")
                        .font(AppTheme.Typography.body)
                        .foregroundStyle(AppTheme.secondaryText)

                    Button(String(localized: "spotify.play", defaultValue: "Play")) {
                        Task { await playPlaylist() }
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    ForEach(tracks) { track in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(track.name)
                                .font(AppTheme.Typography.body)
                                .foregroundStyle(AppTheme.primaryText)
                            Text(track.artistName)
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.destructive)
                    }
                    if let infoMessage {
                        Text(infoMessage)
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
                .padding(AppTheme.horizontalPadding)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                tracks = try await environment.spotifyService.getPlaylistTracks(playlistID: playlist.id)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription
            }
        }
    }

    private func playPlaylist() async {
        do {
            var preferences = environment.preferencesRepository.load()
            preferences.selectedSpotifyURI = playlist.uri
            preferences.selectedSpotifyTitle = playlist.name
            try? environment.preferencesRepository.save(preferences)
            try await environment.spotifyService.play(uri: playlist.uri)
            infoMessage = String(
                localized: "spotify.playback.started",
                defaultValue: "Playback requested on your active Spotify device."
            )
            errorMessage = nil
        } catch {
            errorMessage = SleepRoutineError.spotifyPlaybackUnavailable.errorDescription
            infoMessage = String(
                localized: "spotify.playback.open_app",
                defaultValue: "If nothing plays, open Spotify on this iPhone so an active device is available. Premium is required for remote playback."
            )
        }
    }
}

#Preview {
    NavigationStack {
        SpotifyView()
            .environment(\.appEnvironment, AppEnvironment.preview())
    }
}
