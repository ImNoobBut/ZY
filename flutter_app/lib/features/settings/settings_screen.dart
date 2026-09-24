import 'package:flutter/material.dart';

import '../../ui/widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return NightScaffold(
      title: 'Settings',
      child: ListView(
        children: [
          ListTile(
            title: const Text('Spotify'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/spotify'),
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
