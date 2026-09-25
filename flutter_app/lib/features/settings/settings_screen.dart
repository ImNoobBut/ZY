import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/theme/app_theme.dart';
import '../../ui/widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return NightScaffold(
      title: 'Settings',
      child: ListView(
        children: [
          ListTile(
            title: const Text('Bedtime'),
            subtitle: Text(
              '${state.preferences.preferredBedtimeLabel}'
              ' · ${state.preferences.bedtimeReminderEnabled ? 'Reminder on' : 'Reminder off'}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/bedtime'),
          ),
          ListTile(
            title: const Text('Quiet sound'),
            subtitle: Text(state.preferences.selectedQuietSound.displayName),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/quiet-sound'),
          ),
          ListTile(
            title: const Text('Sleep history'),
            subtitle: Text(
              state.currentStreak > 0
                  ? '${state.currentStreak}-night streak'
                  : 'No streak yet',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/history'),
          ),
          ListTile(
            title: const Text('Spotify'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/spotify'),
          ),
          ListTile(
            title: const Text('Alarm permission'),
            subtitle: Text(
              state.alarmsPermissionGranted == true
                  ? 'Granted'
                  : 'Needed for wake alarms — also on Alarms tab',
              style: const TextStyle(color: AppTheme.secondaryText),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => state.requestAlarmPermission(),
          ),
          ListTile(
            title: const Text('Admin'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/admin'),
          ),
          ListTile(
            title: const Text('Privacy'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/privacy'),
          ),
          const ListTile(
            title: Text('About'),
            subtitle: Text('Flutter Android + Web port. Swift iOS app remains separate.'),
          ),
        ],
      ),
    );
  }
}
