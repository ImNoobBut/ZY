import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../ui/widgets.dart';

enum SpotifyBrowseKind { playlist, album, liked }

/// Browse tracks inside a playlist, album, or Liked Songs and multi-select tracks (or the whole context).
class SpotifyBrowseScreen extends StatefulWidget {
  const SpotifyBrowseScreen({
    super.key,
    required this.kind,
    required this.title,
    this.contextUri,
    this.playlistId,
    this.albumId,
  });

  final SpotifyBrowseKind kind;
  final String title;

  /// Playlist or album URI for "select whole context". Null for Liked Songs.
  final String? contextUri;
  final String? playlistId;
  final String? albumId;

  @override
  State<SpotifyBrowseScreen> createState() => _SpotifyBrowseScreenState();
}

class _SpotifyBrowseScreenState extends State<SpotifyBrowseScreen> {
  List<SpotifyTrack> tracks = [];
  String? error;
  bool busy = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final loaded = switch (widget.kind) {
        SpotifyBrowseKind.playlist =>
          await state.spotify.getPlaylistTracks(widget.playlistId!),
        SpotifyBrowseKind.album =>
          await state.spotify.getAlbumTracks(widget.albumId!),
        SpotifyBrowseKind.liked => await state.spotify.getLikedTracks(),
      };
      if (!mounted) return;
      setState(() {
        tracks = loaded;
        busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = '$e';
        tracks = [];
        busy = false;
      });
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

  Future<void> _selectContext() async {
    final uri = widget.contextUri;
    if (uri == null || uri.isEmpty) return;
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    await state.selectSpotifyContext(uri: uri, title: widget.title);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('Selected "${widget.title}" for the timer')),
    );
    navigator.pop(true);
  }

  bool _looksLikeScopeError(String message) {
    final lower = message.toLowerCase();
    return lower.contains('library access') ||
        lower.contains('insufficient') ||
        lower.contains('connect spotify again');
  }

  Future<void> _reconnectForScopes() async {
    final state = context.read<AppState>();
    setState(() => busy = true);
    try {
      await state.disconnectSpotify();
      await state.spotify.openAuthorizeInBrowser();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = '$e';
        busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final canSelectContext = widget.contextUri != null && widget.contextUri!.isNotEmpty;
    final contextSelected = canSelectContext &&
        state.preferences.isSpotifyUriSelected(widget.contextUri!);
    return NightScaffold(
      title: widget.title,
      child: Column(
        children: [
          if (canSelectContext)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: PrimaryButton(
                label: widget.kind == SpotifyBrowseKind.album
                    ? (contextSelected ? 'Album selected' : 'Select this album')
                    : (contextSelected
                        ? 'Playlist selected'
                        : 'Select this playlist'),
                onPressed: busy ? null : _selectContext,
              ),
            ),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(24),
              child: LinearProgressIndicator(),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(error!, style: const TextStyle(color: AppTheme.destructive)),
                  if (_looksLikeScopeError(error!)) ...[
                    const SizedBox(height: 12),
                    PrimaryButton(
                      label: 'Reconnect Spotify',
                      busy: busy,
                      onPressed: _reconnectForScopes,
                    ),
                  ],
                ],
              ),
            ),
          Expanded(
            child: tracks.isEmpty && !busy && error == null
                ? const Center(
                    child: Text(
                      'No tracks here.',
                      style: TextStyle(color: AppTheme.tertiaryText),
                    ),
                  )
                : tracks.isEmpty
                    ? const SizedBox.shrink()
                    : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                    itemCount: tracks.length,
                    itemBuilder: (context, index) {
                      final t = tracks[index];
                      final selected =
                          state.preferences.isSpotifyUriSelected(t.uri);
                      return ListTile(
                        leading: _ArtThumb(imageUrl: t.imageUrl, icon: Icons.music_note),
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
          ),
        ],
      ),
    );
  }
}

class _ArtThumb extends StatelessWidget {
  const _ArtThumb({this.imageUrl, required this.icon});

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
