/// Shared Help / user-guide sections. Keep [USER_GUIDE.md] in sync with these titles and bodies.
class HelpSection {
  const HelpSection({required this.title, required this.body});

  final String title;
  final String body;
}

const List<HelpSection> kHelpSections = [
  HelpSection(
    title: 'Welcome',
    body:
        'Sleeping Routine for Zy (launcher name: Zy Sleep) helps you keep a simple bedtime '
        'routine in one place: quiet music or Spotify, a sleep timer, and a wake alarm.\n\n'
        'Use Home for tonight’s routine, Alarms for wake times, and Settings for preferences.',
  ),
  HelpSection(
    title: 'Account',
    body:
        'Create an account with your display name, email, and a password of at least 8 characters, '
        'or sign in if you already have one.\n\n'
        'Your name appears in greetings. Change it later under Settings → Account. '
        'Sign out from the same place.',
  ),
  HelpSection(
    title: 'First setup',
    body:
        'After you sign in the first time, a short setup walks you through:\n\n'
        '1. Welcome — what the app does\n'
        '2. Allow alarms — so wake reminders can ring (on web, alarms only work while this tab stays open)\n'
        '3. Music — connect Spotify, or skip and use quiet in-app sounds\n'
        '4. Your routine — sleep timer length, preferred bedtime, wake time, and an optional default weekday alarm\n\n'
        'Tap Start my routine when you are done. You can change everything later in Settings.',
  ),
  HelpSection(
    title: 'Tonight’s routine',
    body:
        'On Home:\n\n'
        '1. Choose how long the sleep timer should run (presets or the slider)\n'
        '2. Tap the music row to pick Spotify music or a quiet sound\n'
        '3. Tap Start Sleep Routine\n\n'
        'While the routine is active you will see a countdown. Near the end, local quiet audio fades out. '
        'Tap End Routine anytime to stop early.\n\n'
        'Completing routines builds a streak shown on Home. Start and end times are saved so the timer '
        'stays accurate if you leave the screen.',
  ),
  HelpSection(
    title: 'Music',
    body:
        'Quiet sounds stay on this device: Soft tone, Rain, White noise, and Deep hum. '
        'Open them from Settings → Quiet sound, or from the Home music row when Spotify is not selected.\n\n'
        'For Spotify: Settings → Spotify (or Connect during setup). Connect in the browser, refresh devices, '
        'then search for a track or select a playlist.\n\n'
        'Spotify playback needs a Premium account and an active Spotify device (open Spotify and play once '
        'if no devices appear). If Spotify cannot play, the routine falls back to your quiet sound.',
  ),
  HelpSection(
    title: 'Wake alarms',
    body:
        'Open the Alarms tab and tap + to add a wake time, label, weekdays, and sound. '
        'Choose Default, Gentle, or Chime (preview plays at full volume). '
        'On Android you can also pick a device ringtone. '
        'Leave days empty for a one-time alarm. Toggle alarms on or off in the list.\n\n'
        'On Android and iOS, allow notifications (and Alarms & reminders on Android) so wakes can ring '
        'when the phone is locked.\n\n'
        'On web, alarms are best-effort browser reminders while this tab stays open — not a full phone '
        'alarm clock. For reliable lock-screen wakes, use the Android or iOS app.',
  ),
  HelpSection(
    title: 'Bedtime',
    body:
        'Settings → Bedtime lets you set your preferred bedtime and wake time, and turn the bedtime '
        'reminder on or off.\n\n'
        'On the phone app, the reminder uses a system notification. On web, keep the tab open so the '
        'reminder can fire.',
  ),
  HelpSection(
    title: 'History',
    body:
        'Settings → Sleep history lists recent completed routines and how long they lasted. '
        'Incomplete sessions are labeled Incomplete.\n\n'
        'Your current streak also appears on Home.',
  ),
  HelpSection(
    title: 'Sync & install',
    body:
        'Settings → Sync & install shows whether you are online and when you last synced. '
        'Changes are saved on this device offline and sync when you are online again.\n\n'
        'To use another device on the same account: sync once to get a pairing code, then enter that '
        'code on the other device under Join account.\n\n'
        'On web you can Add to Home Screen (Chrome: Install app; Safari: Share → Add to Home Screen) '
        'or install the native app for more reliable wake alarms.',
  ),
  HelpSection(
    title: 'Tips & troubleshooting',
    body:
        '• Alarm permission denied — open the Alarms tab or Settings → Alarm permission, or enable '
        'notifications in system / browser site settings.\n'
        '• Web alarm did not ring — keep this tab open; browser limits mean native apps are more reliable.\n'
        '• Spotify shows no devices — open Spotify, start playing any track once, then tap Refresh devices.\n'
        '• Spotify play failed — Premium and an active Connect device are required; otherwise quiet sound is used.\n'
        '• Offline / pending sync — your changes stay on this device; sync resumes when you are online.',
  ),
  HelpSection(
    title: 'Privacy',
    body:
        'For what the app collects and what it never collects, open Settings → Privacy. '
        'Remote check-in is optional and off by default; see that screen if you ever enable it.',
  ),
];
