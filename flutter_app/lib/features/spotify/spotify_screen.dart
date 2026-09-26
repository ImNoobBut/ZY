import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../ui/widgets.dart';

class SpotifyScreen extends StatefulWidget {
  const SpotifyScreen({super.key});

  @override
  State<SpotifyScreen> createState() => _SpotifyScreenState();
}

class _SpotifyScreenState extends State<SpotifyScreen> {
  final searchController = TextEditingController();
  List<SpotifyPlaylist> playlists = [];
  List<SpotifyTrack> tracks = [];
  List<String> devices = [];
  String? error;
  bool busy = false;

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final state = context.read<AppState>();
    if (!state.spotify.isAuthenticated) return;
    setState(() => busy = true);
    try {
      playlists = await state.spotify.getPlaylists();
      devices = await state.spotify.listDeviceNames();
      error = null;
    } catch (e) {
      error = '$e';
      if (!state.spotify.isAuthenticated) {
        playlists = [];
        tracks = [];
        devices = [];
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _search() async {
    final query = searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        tracks = [];
        error = null;
      });
      return;
    }
    final state = context.read<AppState>();
    setState(() => busy = true);
    try {
      tracks = await state.spotify.search(query);
      error = null;
    } catch (e) {
      error = '$e';
      tracks = [];
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _disconnect() async {
    final state = context.read<AppState>();
    setState(() => busy = true);
    try {
      await state.disconnectSpotify();
      playlists = [];
      tracks = [];
      devices = [];
      error = null;
    } catch (e) {
      error = '$e';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return NightScaffold(
      title: 'Spotify',
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          ZyCard(
            child: Text(
              kIsWeb
                  ? 'Redirect URI for this site: ${state.config.spotifyRedirectUri}\n'
                      'Add that exact URL in the Spotify Developer Dashboard → Redirect URIs.\n\n'
                      'After login you return to /callback; the app exchanges the code and clears it from the address bar.\n\n'
                      'A play 404 means no Spotify Connect device — open Spotify, play a track once, then Refresh devices.'
                  : 'Android uses sleepingroutineforzy://spotify-callback — register that in Spotify Dashboard.\n\n'
                      'A play 404 means no Spotify Connect device — open Spotify, play a track once, then Refresh devices.',
              style: const TextStyle(color: AppTheme.secondaryText, height: 1.4),
            ),
          ),
          const SizedBox(height: 16),
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
            const SizedBox(height: 8),
            SecondaryButton(
              label: 'Demo connect',
              onPressed: () async {
                await state.spotify.connectDemo();
                await _refresh();
                setState(() {});
              },
            ),
          ] else ...[
            ZyCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Connected ✓', style: TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    state.preferences.selectedSpotifyTitle ?? 'Nothing selected yet',
                    style: const TextStyle(color: AppTheme.secondaryText),
                  ),
                  const SizedBox(height: 12),
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
              label: 'Refresh devices',
              onPressed: busy ? null : _refresh,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: searchController,
                    decoration: const InputDecoration(
                      hintText: 'Search',
                      filled: true,
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: busy ? null : _search,
                  child: const Text('Search'),
                ),
              ],
            ),
            if (busy) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
            if (tracks.isEmpty && searchController.text.trim().isNotEmpty && !busy)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'No tracks found.',
                  style: TextStyle(color: AppTheme.tertiaryText),
                ),
              ),
            const SizedBox(height: 12),
            ...tracks.map(
              (t) => ListTile(
                title: Text(t.name),
                subtitle: Text(t.artistName),
                onTap: () => state.selectSpotify(
                  uri: t.uri,
                  title: '${t.name} — ${t.artistName}',
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text('Your playlists', style: TextStyle(color: AppTheme.tertiaryText)),
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
                title: Text(p.name),
                subtitle: Text('${p.trackCount} tracks'),
                trailing: TextButton(
                  onPressed: () => state.selectSpotify(uri: p.uri, title: p.name),
                  child: const Text('Select'),
                ),
              ),
            ),
            const SizedBox(height: 8),
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
            Text(state.infoMessage!, style: const TextStyle(color: AppTheme.secondaryText)),
          ],
        ],
      ),
    );
  }
}
