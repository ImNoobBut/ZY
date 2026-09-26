import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'core/theme/app_theme.dart';
import 'features/admin/admin_screen.dart';
import 'features/alarms/alarms_screen.dart';
import 'features/home/home_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/privacy/privacy_screen.dart';
import 'features/settings/bedtime_settings_screen.dart';
import 'features/settings/quiet_sound_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/settings/sleep_history_screen.dart';
import 'features/settings/sync_settings_screen.dart';
import 'features/spotify/spotify_screen.dart';

class ZyApp extends StatelessWidget {
  const ZyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sleeping Routine for Zy',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const _RootGate(),
      routes: {
        '/spotify': (_) => const SpotifyScreen(),
        '/admin': (_) => const AdminScreen(),
        '/privacy': (_) => const PrivacyScreen(),
        '/bedtime': (_) => const BedtimeSettingsScreen(),
        '/quiet-sound': (_) => const QuietSoundScreen(),
        '/history': (_) => const SleepHistoryScreen(),
        '/sync': (_) => const SyncSettingsScreen(),
      },
    );
  }
}

class _RootGate extends StatelessWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!state.preferences.hasCompletedOnboarding) {
      return const OnboardingScreen();
    }
    return const MainShell();
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const HomeScreen(),
      const AlarmsScreen(),
      const SettingsScreen(),
    ];
    return Scaffold(
      body: Container(
        decoration: AppTheme.nightBackground(),
        child: pages[index],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.nightlight_round), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.alarm), label: 'Alarms'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
