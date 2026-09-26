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
    final profile = state.auth.profile;
    final name = state.preferences.displayName.trim().isNotEmpty
        ? state.preferences.displayName.trim()
        : (profile?.displayName ?? '—');

    return NightScaffold(
      title: 'Settings',
      child: ListView(
        children: [
          ListTile(
            title: const Text('Account'),
            subtitle: Text(
              profile == null
                  ? 'Not signed in'
                  : '$name · ${profile.email}',
              style: const TextStyle(color: AppTheme.secondaryText),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openAccountSheet(context, state),
          ),
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
                  : (state.alarmScheduler.isBestEffortOnly
                      ? (state.alarmScheduler.permissionNeedsSystemSettings
                          ? 'Blocked in browser site settings'
                          : 'Optional on web — helps background banners')
                      : 'Needed for wake alarms — also on Alarms tab'),
              style: const TextStyle(color: AppTheme.secondaryText),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => state.requestAlarmPermission(),
          ),
          ListTile(
            title: const Text('Remote check-in'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/admin'),
          ),
          ListTile(
            title: const Text('Help'),
            subtitle: const Text(
              'New-user guide',
              style: TextStyle(color: AppTheme.secondaryText),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/help'),
          ),
          ListTile(
            title: const Text('Privacy'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/privacy'),
          ),
          const ListTile(
            title: Text('About'),
            subtitle: Text(
              'A simple bedtime routine — music, timer, and wake alarm.',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openAccountSheet(BuildContext context, AppState state) async {
    final profile = state.auth.profile;
    if (profile == null) return;

    final nameController = TextEditingController(
      text: state.preferences.displayName.trim().isNotEmpty
          ? state.preferences.displayName
          : profile.displayName,
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.sheet,
      barrierColor: AppTheme.sheetBarrier,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return ListenableBuilder(
          listenable: state,
          builder: (ctx, _) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.viewInsetsOf(ctx).bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Account',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    profile.email,
                    style: const TextStyle(color: AppTheme.secondaryText),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Display name'),
                  ),
                  const SizedBox(height: 16),
                  PrimaryButton(
                    label: 'Save name',
                    busy: state.busy,
                    onPressed: () async {
                      try {
                        await state.updateDisplayName(nameController.text);
                        if (ctx.mounted) Navigator.of(ctx).pop();
                      } catch (_) {}
                    },
                  ),
                  const SizedBox(height: 8),
                  SecondaryButton(
                    label: 'Sign out',
                    onPressed: () async {
                      await state.signOut();
                      if (ctx.mounted) Navigator.of(ctx).pop();
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    nameController.dispose();
  }
}
