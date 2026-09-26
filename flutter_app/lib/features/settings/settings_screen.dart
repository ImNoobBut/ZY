import 'package:flutter/foundation.dart';
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
    final syncSubtitle = !state.sync.online
        ? 'Offline · pending ${state.sync.pendingCount}'
        : state.sync.syncing
            ? 'Syncing…'
            : (state.sync.lastSyncIso == null
                ? 'Not synced yet'
                : 'Last sync ok'
                    '${state.sync.pendingCount > 0 ? ' · ${state.sync.pendingCount} pending' : ''}');

    return NightScaffold(
      title: 'Settings',
      child: ListView(
        children: [
          ListTile(
            title: const Text('Sync & install'),
            subtitle: Text(
              syncSubtitle,
              style: const TextStyle(color: AppTheme.secondaryText),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/sync'),
          ),
          if (kIsWeb)
            const ListTile(
              title: Text('Add to Home Screen'),
              subtitle: Text(
                'Safari: Share → Add to Home Screen. Chrome: Install app.',
                style: TextStyle(color: AppTheme.secondaryText),
              ),
            ),
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
            subtitle: Text(
              'PWA-ready Flutter web + Android. Offline-first sync when the backend is reachable.',
            ),
          ),
        ],
      ),
    );
  }
}
