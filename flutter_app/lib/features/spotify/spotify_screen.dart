import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/theme/app_theme.dart';
import '../../ui/widgets.dart';

class SpotifyScreen extends StatefulWidget {
  const SpotifyScreen({super.key});

  @override
  State<SpotifyScreen> createState() => _SpotifyScreenState();
}

class _SpotifyScreenState extends State<SpotifyScreen> {
  final searchController = TextEditingController();
  List playlists = [];
  List tracks = [];
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
      error = null;
    } catch (e) {
      error = '$e';
    } finally {
      setState(() => busy = false);
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
              'Sign-in uses Spotify OAuth (PKCE). Playback needs Premium + an active Spotify device.\n\n'
              'Add this exact Redirect URI in the Spotify Developer Dashboard:\n'
              '${state.config.spotifyRedirectUri}\n\n'
              '(Keep the iOS URI too: sleepingroutineforzy://spotify-callback)\n\n'
              'Or use Demo connect for local UI testing without OAuth.',
              style: const TextStyle(color: AppTheme.secondaryText, height: 1.4),
            ),
          ),
          const SizedBox(height: 16),
          if (!state.spotify.isAuthenticated) ...[
            PrimaryButton(
              label: 'Connect Spotify',
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
                ],
              ),
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
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () async {
                    tracks = await state.spotify.search(searchController.text);
                    setState(() {});
                  },
                  child: const Text('Search'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...tracks.map(
              (t) => ListTile(
                title: Text(t.name),
                subtitle: Text(t.artistName),
                onTap: () => state.selectSpotify(uri: t.uri, title: '${t.name} — ${t.artistName}'),
              ),
            ),
            const SizedBox(height: 8),
            const Text('Your playlists', style: TextStyle(color: AppTheme.tertiaryText)),
            if (busy) const LinearProgressIndicator(),
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
            SecondaryButton(
              label: 'Disconnect',
              onPressed: () async {
                await state.spotify.logout();
                playlists = [];
                tracks = [];
                setState(() {});
              },
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
