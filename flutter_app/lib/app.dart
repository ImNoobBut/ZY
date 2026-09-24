import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'core/theme/app_theme.dart';
import 'features/admin/admin_screen.dart';
import 'features/alarms/alarms_screen.dart';
import 'features/home/home_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/privacy/privacy_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/sleep_timer/sleep_timer_screen.dart';
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
      const SleepTimerScreen(),
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
          NavigationDestination(icon: Icon(Icons.timer_outlined), label: 'Sleep'),
          NavigationDestination(icon: Icon(Icons.alarm), label: 'Alarms'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
