import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/theme/app_theme.dart';
import '../../ui/widgets.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final pinController = TextEditingController();
  final confirmController = TextEditingController();
  bool unlocked = false;
  bool hasPin = false;
  String? error;
  String? info;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      hasPin = await context.read<AppState>().hasAdminPin();
      setState(() {});
    });
  }

  @override
  void dispose() {
    pinController.dispose();
    confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return NightScaffold(
      title: 'Remote check-in',
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          ZyCard(
            child: const Text(
              'Only opted-in status is uploaded over HTTPS. While sharing is on, a paired guardian can also change alarm, bedtime, routine, and stop app audio when this app is open. Not real-time surveillance.',
              style: TextStyle(color: AppTheme.secondaryText, height: 1.4),
            ),
          ),
          const SizedBox(height: 16),
          if (!hasPin) ...[
            TextField(
              controller: pinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Create 4–8 digit PIN'),
            ),
            TextField(
              controller: confirmController,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Confirm PIN'),
            ),
            const SizedBox(height: 12),
            PrimaryButton(
              label: 'Save PIN',
              onPressed: () async {
                try {
                  if (pinController.text != confirmController.text) {
                    throw Exception('PINs did not match');
                  }
                  await state.setAdminPin(pinController.text);
                  hasPin = true;
                  unlocked = true;
                  info = 'PIN saved.';
                  error = null;
                } catch (e) {
                  error = '$e';
                }
                setState(() {});
              },
            ),
          ] else if (!unlocked) ...[
            TextField(
              controller: pinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Enter PIN'),
            ),
            const SizedBox(height: 12),
            PrimaryButton(
              label: 'Unlock',
              onPressed: () async {
                final ok = await state.verifyAdminPin(pinController.text);
                unlocked = ok;
                error = ok ? null : 'That PIN didn\'t match.';
                setState(() {});
              },
            ),
          ] else ...[
            SwitchListTile(
              title: const Text('Share status for remote check-in'),
              value: state.preferences.remoteMonitoringOptIn,
              onChanged: (v) async {
                try {
                  await state.setRemoteOptIn(v);
                  info = state.infoMessage;
                  error = state.errorMessage;
                } catch (e) {
                  error = state.errorMessage ?? '$e';
                  info = null;
                }
                setState(() {});
              },
            ),
            Text(
              'Backend: ${state.config.backendBaseUrl}',
              style: const TextStyle(color: AppTheme.tertiaryText, fontSize: 12),
            ),
            const SizedBox(height: 12),
            ZyCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Guardian pairing code', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(
                    state.admin.pairingCode ?? 'Turn on sharing to register.',
                    style: const TextStyle(fontSize: 36, color: AppTheme.accent, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Last check-in: ${state.preferences.lastSuccessfulCheckInIso ?? 'Never'}',
                    style: const TextStyle(color: AppTheme.secondaryText),
                  ),
                  const Text(
                    'Status may be delayed when the app is not running.',
                    style: TextStyle(color: AppTheme.secondaryText, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            PrimaryButton(
              label: 'Check in now',
              onPressed: () async {
                try {
                  if (!state.admin.isRegistered) {
                    throw Exception('Turn on sharing first to register.');
                  }
                  await state.pollRemoteAdminAndCheckIn();
                  info = 'Status sent.';
                  error = null;
                } catch (e) {
                  error = '$e';
                  info = null;
                }
                setState(() {});
              },
            ),
            const SizedBox(height: 8),
            SecondaryButton(
              label: 'Lock Admin',
              onPressed: () => setState(() => unlocked = false),
            ),
            if (state.admin.isRegistered) ...[
              const SizedBox(height: 8),
              SecondaryButton(
                label: 'Disconnect remote',
                onPressed: () async {
                  await state.disconnectAdmin();
                  setState(() {
                    info = 'Disconnected.';
                    error = null;
                  });
                },
              ),
            ],
          ],
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: const TextStyle(color: AppTheme.destructive)),
          ],
          if (info != null && error == null) ...[
            const SizedBox(height: 12),
            Text(info!, style: const TextStyle(color: AppTheme.secondaryText)),
          ],
        ],
      ),
    );
  }
}
