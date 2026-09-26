import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../ui/widgets.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return NightScaffold(
      title: 'Privacy',
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: const [
          ZyCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('What we collect', style: TextStyle(fontWeight: FontWeight.w600)),
                SizedBox(height: 8),
                Text(
                  'Account email and display name when you sign up (password is sent only to create a server-side hash — never kept in the app). Sleep routine and alarm settings, Spotify connection state, app-generated sleep session activity, and device status fields you enable for remote Admin.',
                  style: TextStyle(color: AppTheme.secondaryText, height: 1.4),
                ),
              ],
            ),
          ),
          SizedBox(height: 12),
          ZyCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('What we never collect', style: TextStyle(fontWeight: FontWeight.w600)),
                SizedBox(height: 8),
                Text(
                  'Messages, browsing history, keystrokes, other apps’ private content, microphone, camera, location, or screen contents. We never store your account password in plaintext.',
                  style: TextStyle(color: AppTheme.secondaryText, height: 1.4),
                ),
              ],
            ),
          ),
          SizedBox(height: 12),
          ZyCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Remote Admin', style: TextStyle(fontWeight: FontWeight.w600)),
                SizedBox(height: 8),
                Text(
                  'Remote monitoring is off by default. When you opt in, status goes only to your configured backend over HTTPS. On Android/iOS, device and Spotify tokens use the platform secure store. You can disconnect anytime.',
                  style: TextStyle(color: AppTheme.secondaryText, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
