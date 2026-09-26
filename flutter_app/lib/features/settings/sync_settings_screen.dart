import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_state.dart';
import '../../core/config/app_config.dart';
import '../../core/install/install_target.dart';
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
            _InstallDownloadsCard(config: state.config),
            const ListTile(
              title: Text('Or use as a web app'),
              subtitle: Text(
                'Android Chrome: menu → Install app / Add to Home screen.\n'
                'iPhone Safari: Share → Add to Home Screen.\n'
                'Native APK/IPA installs are better for real wake alarms.',
                style: TextStyle(color: AppTheme.secondaryText),
              ),
            ),
          ] else
            ListTile(
              title: const Text('Install'),
              subtitle: Text(
                defaultTargetPlatform == TargetPlatform.iOS
                    ? 'Get updates from ${state.config.iosInstallUrl}'
                    : 'Get the Android APK from ${state.config.androidApkUrl}',
                style: const TextStyle(color: AppTheme.secondaryText),
              ),
              onTap: () => _openInstallLink(
                context,
                defaultTargetPlatform == TargetPlatform.iOS
                    ? state.config.iosInstallUrl
                    : state.config.androidApkUrl,
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

  Future<void> _openInstallLink(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $url')),
      );
    }
  }
}

class _InstallDownloadsCard extends StatelessWidget {
  const _InstallDownloadsCard({required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    final target = detectInstallTarget();
    final showAndroid =
        target == InstallTarget.androidApk || target == InstallTarget.other;
    final showIos =
        target == InstallTarget.iosIpa || target == InstallTarget.other;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: ZyCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              target == InstallTarget.androidApk
                  ? 'Download for Android'
                  : (target == InstallTarget.iosIpa
                      ? 'Download for iPhone'
                      : 'Download the app'),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              target == InstallTarget.androidApk
                  ? 'Install the Zy Sleep APK for real wake alarms (exact notifications).'
                  : (target == InstallTarget.iosIpa
                      ? 'Install the iOS build (TestFlight or IPA). AlarmKit needs the native app.'
                      : 'Pick Android APK or iOS IPA for your phone.'),
              style: const TextStyle(color: AppTheme.secondaryText, fontSize: 13),
            ),
            const SizedBox(height: 12),
            if (showAndroid) ...[
              PrimaryButton(
                label: 'Download Android APK',
                onPressed: () => _launch(context, config.androidApkUrl),
              ),
              const SizedBox(height: 6),
              SelectableText(
                config.androidApkUrl,
                style: const TextStyle(color: AppTheme.tertiaryText, fontSize: 11),
              ),
            ],
            if (showAndroid && showIos) const SizedBox(height: 12),
            if (showIos) ...[
              PrimaryButton(
                label: 'Download iOS IPA / TestFlight',
                onPressed: () => _launch(context, config.iosInstallUrl),
              ),
              const SizedBox(height: 6),
              SelectableText(
                config.iosInstallUrl,
                style: const TextStyle(color: AppTheme.tertiaryText, fontSize: 11),
              ),
              const SizedBox(height: 6),
              const Text(
                'IPA requires a Mac build (Xcode) and Apple signing. Prefer TestFlight for TestFlight links.',
                style: TextStyle(color: AppTheme.tertiaryText, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _launch(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $url')),
      );
    }
  }
}
