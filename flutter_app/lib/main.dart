import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'app_state.dart';
import 'core/config/app_config.dart';
import 'core/services/admin_service.dart';
import 'core/services/alarm_scheduler_factory.dart';
import 'core/services/quiet_audio_service.dart';
import 'core/services/spotify_service.dart';
import 'core/services/sync_service.dart';
import 'core/storage/local_store.dart';
import 'core/web/web_oauth.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    usePathUrlStrategy();
    // Spotify redirect + PKCE storage are tied to 127.0.0.1 — not localhost.
    if (canonicalizeWebHostToLoopback()) return;
  }

  final config = AppConfig.fromEnvironment();
  final store = LocalStore();
  final spotify = SpotifyService(config: config, store: store);
  final admin = AdminService(config: config, store: store);
  final sync = SyncService(config: config, store: store, admin: admin);
  final audio = QuietAudioService();
  final alarmScheduler = createPlatformAlarmScheduler();
  final state = AppState(
    config: config,
    store: store,
    spotify: spotify,
    admin: admin,
    audio: audio,
    alarmScheduler: alarmScheduler,
    sync: sync,
  );
  await state.bootstrap();

  runApp(
    ChangeNotifierProvider.value(
      value: state,
      child: const ZyApp(),
    ),
  );
}
