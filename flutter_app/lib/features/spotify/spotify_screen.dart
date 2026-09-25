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
              'Use http://127.0.0.1:7357 (not localhost). After login you return to /callback; '
              'the app exchanges the code and then clears it from the address bar.\n\n'
              'A play 404 means no Spotify Connect device — open Spotify, play a track once, then Refresh devices.\n\n'
              'Console noise from MetaMask / Notta / Sentry is from browser extensions, not this app.',
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
              onPressed: _refresh,
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
                devices = [];
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
