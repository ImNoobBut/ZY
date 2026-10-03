import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../ui/widgets.dart';
import 'spotify_browse_screen.dart';

class SpotifyScreen extends StatefulWidget {
  const SpotifyScreen({super.key});

  @override
  State<SpotifyScreen> createState() => _SpotifyScreenState();
}

class _SpotifyScreenState extends State<SpotifyScreen> {
  final searchController = TextEditingController();
  List<SpotifyPlaylist> playlists = [];
  List<SpotifyTrack> recentTracks = [];
  List<SpotifyTrack> searchTracks = [];
  List<SpotifyAlbum> searchAlbums = [];
  List<String> devices = [];
  String? error;
  String? libraryHint;
  bool busy = false;
  bool searching = false;

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final state = context.read<AppState>();
    if (!state.spotify.isAuthenticated) return;
    setState(() {
      busy = true;
      error = null;
      libraryHint = null;
    });
    try {
      final loadedPlaylists = await state.spotify.getPlaylists();
      final loadedDevices = await state.spotify.listDeviceNames();
      List<SpotifyTrack> recent = [];
      String? hint;
      try {
        recent = await state.spotify.getRecentlyPlayed();
      } catch (e) {
        hint = '$e';
      }
      if (!mounted) return;
      setState(() {
        playlists = loadedPlaylists;
        devices = loadedDevices;
        recentTracks = recent;
        libraryHint = hint;
        busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = '$e';
        if (!state.spotify.isAuthenticated) {
          playlists = [];
          recentTracks = [];
          searchTracks = [];
          searchAlbums = [];
          devices = [];
        }
        busy = false;
      });
    }
  }

  Future<void> _search() async {
    final query = searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        searchTracks = [];
        searchAlbums = [];
        error = null;
      });
      return;
    }
    final state = context.read<AppState>();
    setState(() {
      searching = true;
      error = null;
    });
    try {
      final result = await state.spotify.searchCatalog(query);
      if (!mounted) return;
      setState(() {
        searchTracks = result.tracks;
        searchAlbums = result.albums;
        searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = '$e';
        searchTracks = [];
        searchAlbums = [];
        searching = false;
      });
    }
  }

  Future<void> _disconnect() async {
    final state = context.read<AppState>();
    setState(() => busy = true);
    try {
      await state.disconnectSpotify();
      playlists = [];
      recentTracks = [];
      searchTracks = [];
      searchAlbums = [];
      devices = [];
      error = null;
      libraryHint = null;
    } catch (e) {
      error = '$e';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _toggleTrack(SpotifyTrack track) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final title = track.artistName.isEmpty
        ? track.name
        : '${track.name} — ${track.artistName}';
    final added = await state.toggleSpotifyTrack(uri: track.uri, title: title);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          added ? 'Added "$title" to the queue' : 'Removed "$title" from the queue',
        ),
      ),
    );
  }

  Future<void> _openBrowse(SpotifyBrowseScreen screen) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => screen),
    );
    if (changed == true && mounted) setState(() {});
  }

  Future<void> _openPlaylist(SpotifyPlaylist playlist) {
    return _openBrowse(
      SpotifyBrowseScreen(
        kind: SpotifyBrowseKind.playlist,
        title: playlist.name,
        contextUri: playlist.uri,
        playlistId: playlist.id,
      ),
    );
  }

  Future<void> _openAlbum(SpotifyAlbum album) {
    return _openBrowse(
      SpotifyBrowseScreen(
        kind: SpotifyBrowseKind.album,
        title: album.name,
        contextUri: album.uri,
        albumId: album.id,
      ),
    );
  }

  Future<void> _openLiked() {
    return _openBrowse(
      const SpotifyBrowseScreen(
        kind: SpotifyBrowseKind.liked,
        title: 'Liked Songs',
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final selectedItems = state.preferences.selectedSpotifyItems;
    final hasSelection = state.preferences.hasSpotifySelection;
    final query = searchController.text.trim();
    final showSearchResults = query.isNotEmpty;

    return NightScaffold(
      title: 'Spotify',
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text(
              'Setup help',
              style: TextStyle(color: AppTheme.secondaryText),
            ),
            children: [
              ZyCard(
                child: Text(
                  [
                    'Redirect URI: ${state.config.spotifyRedirectUri}',
                    'Add that exact URL in the Spotify Developer Dashboard → Redirect URIs.',
                    '',
                    kIsWeb
                        ? 'After login you return to /callback; the app exchanges the code and clears it from the address bar.'
                        : 'After login, Android App Links / iOS Universal Links return into this app to finish OAuth.',
                    '',
                    'A play 404 means no Spotify Connect device — open Spotify, play a track once, then Refresh devices.',
                    '',
                    'After app updates that add library access, Disconnect and Connect again once.',
                  ].join('\n'),
                  style: const TextStyle(color: AppTheme.secondaryText, height: 1.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!state.spotify.isAuthenticated) ...[
            PrimaryButton(
              label: 'Connect Spotify',
              busy: busy,
              onPressed: () async {
                try {
                  await state.spotify.openAuthorizeInBrowser();
                } catch (e) {
                  setState(() => error = '$e');
                }
              },
            ),
            if (kDebugMode) ...[
              const SizedBox(height: 8),
              SecondaryButton(
                label: 'Demo connect',
                onPressed: () async {
                  await state.spotify.connectDemo();
                  await _refresh();
                  setState(() {});
                },
              ),
            ],
          ] else ...[
            ZyCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Now selected',
                    style: TextStyle(
                      color: AppTheme.tertiaryText,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (!hasSelection)
                    const Text(
                      'Nothing selected yet',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.secondaryText,
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 180),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: selectedItems.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 4),
                        itemBuilder: (context, index) {
                          final item = selectedItems[index];
                          return Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.title.isEmpty ? item.uri : item.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.primaryText,
                                  ),
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: 'Remove',
                                onPressed: () =>
                                    state.removeSpotifySelection(item.uri),
                                icon: const Icon(
                                  Icons.close,
                                  size: 18,
                                  color: AppTheme.secondaryText,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  if (hasSelection) ...[
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        await state.clearSpotifySelection();
                        if (!mounted) return;
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Selection cleared')),
                        );
                      },
                      child: const Text('Clear all'),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    devices.isEmpty
                        ? 'Devices: none — open Spotify and play a track once.'
                        : 'Devices:\n${devices.map((d) => '• $d').join('\n')}',
                    style: const TextStyle(color: AppTheme.secondaryText, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            PrimaryButton(
              label: 'Open Spotify',
              onPressed: () => state.spotify.openSpotifyApp(),
            ),
            const SizedBox(height: 8),
            SecondaryButton(
              label: 'Refresh',
              onPressed: busy ? null : _refresh,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: searchController,
                    decoration: const InputDecoration(
                      hintText: 'Search tracks & albums',
                      filled: true,
                    ),
                    onSubmitted: (_) => _search(),
                    onChanged: (value) {
                      if (value.trim().isEmpty) {
                        setState(() {
                          searchTracks = [];
                          searchAlbums = [];
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: (busy || searching) ? null : _search,
                  child: const Text('Search'),
                ),
              ],
            ),
            if (busy || searching) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
            if (showSearchResults) ...[
              if (searchTracks.isEmpty &&
                  searchAlbums.isEmpty &&
                  !searching &&
                  !busy)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'No results.',
                    style: TextStyle(color: AppTheme.tertiaryText),
                  ),
                ),
              if (searchAlbums.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Albums',
                  style: TextStyle(color: AppTheme.tertiaryText),
                ),
                ...searchAlbums.map(
                  (a) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: _SpotifyArtThumb(
                      imageUrl: a.imageUrl,
                      icon: Icons.album,
                    ),
                    title: Text(a.name),
                    subtitle: Text(
                      a.artistName.isEmpty
                          ? '${a.trackCount} tracks'
                          : '${a.artistName} · ${a.trackCount} tracks',
                      style: const TextStyle(color: AppTheme.secondaryText),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openAlbum(a),
                  ),
                ),
              ],
              if (searchTracks.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Tracks',
                  style: TextStyle(color: AppTheme.tertiaryText),
                ),
                ...searchTracks.map(
                  (t) {
                    final selected =
                        state.preferences.isSpotifyUriSelected(t.uri);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: _SpotifyArtThumb(
                        imageUrl: t.imageUrl,
                        icon: Icons.music_note,
                      ),
                      title: Text(t.name),
                      subtitle: Text(
                        t.artistName,
                        style: const TextStyle(color: AppTheme.secondaryText),
                      ),
                      trailing: selected
                          ? const Icon(Icons.check_circle, color: AppTheme.accent)
                          : const Icon(Icons.circle_outlined,
                              color: AppTheme.tertiaryText),
                      onTap: () => _toggleTrack(t),
                    );
                  },
                ),
              ],
            ] else ...[
              const SizedBox(height: 20),
              const Text(
                'Library',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              if (libraryHint != null) ...[
                const SizedBox(height: 8),
                Text(
                  libraryHint!,
                  style: const TextStyle(color: AppTheme.secondaryText, height: 1.35),
                ),
                const SizedBox(height: 8),
                SecondaryButton(
                  label: 'Reconnect for library access',
                  onPressed: busy
                      ? null
                      : () async {
                          final state = context.read<AppState>();
                          setState(() => busy = true);
                          try {
                            await state.disconnectSpotify();
                            await state.spotify.openAuthorizeInBrowser();
                          } catch (e) {
                            if (mounted) setState(() => error = '$e');
                          } finally {
                            if (mounted) setState(() => busy = false);
                          }
                        },
                ),
              ],
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const _SpotifyArtThumb(icon: Icons.favorite),
                title: const Text('Liked Songs'),
                subtitle: const Text(
                  'Browse your saved tracks',
                  style: TextStyle(color: AppTheme.secondaryText),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openLiked,
              ),
              if (recentTracks.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'Recently played',
                  style: TextStyle(color: AppTheme.tertiaryText),
                ),
                ...recentTracks.take(15).map(
                      (t) {
                        final selected =
                            state.preferences.isSpotifyUriSelected(t.uri);
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: _SpotifyArtThumb(
                            imageUrl: t.imageUrl,
                            icon: Icons.history,
                          ),
                          title: Text(t.name),
                          subtitle: Text(
                            t.artistName,
                            style: const TextStyle(color: AppTheme.secondaryText),
                          ),
                          trailing: selected
                              ? const Icon(Icons.check_circle,
                                  color: AppTheme.accent)
                              : const Icon(Icons.circle_outlined,
                                  color: AppTheme.tertiaryText),
                          onTap: () => _toggleTrack(t),
                        );
                      },
                    ),
              ],
              const SizedBox(height: 12),
              const Text(
                'Your playlists',
                style: TextStyle(color: AppTheme.tertiaryText),
              ),
              if (playlists.isEmpty && !busy)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'No playlists yet.',
                    style: TextStyle(color: AppTheme.tertiaryText),
                  ),
                ),
              ...playlists.map(
                (p) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _SpotifyArtThumb(
                    imageUrl: p.imageUrl,
                    icon: Icons.queue_music,
                  ),
                  title: Text(p.name),
                  subtitle: Text(
                    '${p.trackCount} tracks',
                    style: const TextStyle(color: AppTheme.secondaryText),
                  ),
                  trailing: TextButton(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final name = p.name;
                      await state.selectSpotifyContext(
                        uri: p.uri,
                        title: name,
                      );
                      if (!mounted) return;
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text('Selected "$name" for the timer'),
                        ),
                      );
                    },
                    child: Text(
                      state.preferences.isSpotifyUriSelected(p.uri)
                          ? 'Selected'
                          : 'Select',
                    ),
                  ),
                  onTap: () => _openPlaylist(p),
                ),
              ),
            ],
            const SizedBox(height: 16),
            SecondaryButton(
              label: 'Disconnect',
              onPressed: busy ? null : _disconnect,
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: const TextStyle(color: AppTheme.destructive)),
          ],
          if (state.infoMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              state.infoMessage!,
              style: const TextStyle(color: AppTheme.secondaryText),
            ),
          ],
        ],
      ),
    );
  }
}

class _SpotifyArtThumb extends StatelessWidget {
  const _SpotifyArtThumb({this.imageUrl, required this.icon});

  final String? imageUrl;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url != null && url.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          url,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallback(),
        ),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, color: AppTheme.tertiaryText, size: 22),
    );
  }
}
