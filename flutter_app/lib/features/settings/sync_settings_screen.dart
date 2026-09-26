import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/theme/app_theme.dart';
import '../../ui/widgets.dart';

class SyncSettingsScreen extends StatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  final _joinController = TextEditingController();
  bool _joining = false;

  @override
  void dispose() {
    _joinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final sync = state.sync;
    final lastSync = sync.lastSyncIso == null
        ? 'Never'
        : DateFormat('MMM d, HH:mm').format(DateTime.parse(sync.lastSyncIso!).toLocal());

    return NightScaffold(
      title: 'Sync & install',
      child: ListView(
        children: [
          ListTile(
            title: const Text('Status'),
            subtitle: Text(
              sync.online
                  ? (sync.syncing
                      ? 'Syncing…'
                      : 'Online · last sync $lastSync'
                          '${sync.pendingCount > 0 ? ' · ${sync.pendingCount} pending' : ''}')
                  : 'Offline · changes saved on this device',
              style: const TextStyle(color: AppTheme.secondaryText),
            ),
            trailing: sync.syncing
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    icon: const Icon(Icons.sync),
                    tooltip: 'Sync now',
                    onPressed: () async {
                      await state.syncNow();
                      if (!context.mounted) return;
                      final err = state.sync.lastError;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(err ?? 'Synced.'),
                        ),
                      );
                    },
                  ),
          ),
          if (sync.lastError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                sync.lastError!,
                style: const TextStyle(color: AppTheme.destructive, fontSize: 13),
              ),
            ),
          const Divider(),
          ListTile(
            title: const Text('This device pairing code'),
            subtitle: Text(
              state.admin.pairingCode ?? 'Sync once to get a code',
              style: const TextStyle(color: AppTheme.secondaryText),
            ),
            trailing: state.admin.pairingCode == null
                ? null
                : IconButton(
                    icon: const Icon(Icons.copy),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: state.admin.pairingCode!));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Pairing code copied')),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _joinController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Join another device',
                hintText: 'Enter their 6-digit pairing code',
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: _joining
                  ? null
                  : () async {
                      setState(() => _joining = true);
                      try {
                        await state.joinSyncAccount(_joinController.text.trim());
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Joined sync account')),
                        );
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('$e')),
                        );
                      } finally {
                        if (mounted) setState(() => _joining = false);
                      }
                    },
              child: Text(_joining ? 'Joining…' : 'Join account'),
            ),
          ),
          const Divider(),
          if (kIsWeb) ...[
            const ListTile(
              title: Text('Install on this phone'),
              subtitle: Text(
                'Android Chrome: menu → Install app / Add to Home screen.\n'
                'iPhone Safari: Share → Add to Home Screen.\n'
                'Wake alarms on iOS home-screen apps are best-effort only.',
                style: TextStyle(color: AppTheme.secondaryText),
              ),
            ),
          ] else
            const ListTile(
              title: Text('Install'),
              subtitle: Text(
                'Use the hosted PWA URL in Chrome/Safari for Add to Home Screen, '
                'or keep this native Android build.',
                style: TextStyle(color: AppTheme.secondaryText),
              ),
            ),
          ListTile(
            title: const Text('Backend'),
            subtitle: Text(
              state.config.backendBaseUrl,
              style: const TextStyle(color: AppTheme.tertiaryText, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
