import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sleeping_routine_for_zy/core/config/app_config.dart';
import 'package:sleeping_routine_for_zy/core/services/spotify_service.dart';
import 'package:sleeping_routine_for_zy/core/storage/local_store.dart';
import 'package:sleeping_routine_for_zy/core/storage/secure_store.dart';

class _MemorySecureStore implements SecureStore {
  final Map<String, String> _data = {};

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SpotifyService spotify;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    spotify = SpotifyService(
      config: const AppConfig(
        spotifyClientId: 'test-client',
        spotifyRedirectUri: 'http://127.0.0.1:7357/callback',
        backendBaseUrl: 'http://127.0.0.1:8081',
        androidApkUrl: '',
        iosInstallUrl: '',
      ),
      store: LocalStore(secureStore: _MemorySecureStore()),
    );
    await spotify.connectDemo();
  });

  test('demo searchCatalog returns tracks and albums', () async {
    final result = await spotify.searchCatalog('quiet');
    expect(result.tracks, isNotEmpty);
    expect(result.albums, isNotEmpty);
    expect(result.tracks.first.uri, startsWith('spotify:track:'));
    expect(result.albums.first.uri, startsWith('spotify:album:'));
  });

  test('demo library endpoints return tracks', () async {
    final playlistTracks = await spotify.getPlaylistTracks('demo');
    final liked = await spotify.getLikedTracks();
    final recent = await spotify.getRecentlyPlayed();
    final albumTracks = await spotify.getAlbumTracks('demo-album');

    expect(playlistTracks, isNotEmpty);
    expect(liked, isNotEmpty);
    expect(recent, isNotEmpty);
    expect(albumTracks, isNotEmpty);
  });

  test('authorize URI includes library scopes', () async {
    final uri = await spotify.buildAuthorizeUri();
    final scope = uri.queryParameters['scope'] ?? '';
    expect(scope, contains('user-library-read'));
    expect(scope, contains('user-read-recently-played'));
  });
}
