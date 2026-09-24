import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'app_state.dart';
import 'core/config/app_config.dart';
import 'core/services/admin_service.dart';
import 'core/services/quiet_audio_service.dart';
import 'core/services/spotify_service.dart';
import 'core/storage/local_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();
  final store = LocalStore();
  final spotify = SpotifyService(config: config, store: store);
  final admin = AdminService(config: config, store: store);
  final audio = QuietAudioService();
  final state = AppState(
    config: config,
    store: store,
    spotify: spotify,
    admin: admin,
    audio: audio,
  );
  await state.bootstrap();

  runApp(
    ChangeNotifierProvider.value(
      value: state,
      child: const ZyApp(),
    ),
  );
}
