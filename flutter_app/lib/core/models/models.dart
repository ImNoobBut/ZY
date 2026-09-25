class UserPreferences {
  UserPreferences({
    this.hasCompletedOnboarding = false,
    this.defaultSleepTimerSeconds = 30 * 60,
    this.preferredBedtimeHour = 22,
    this.preferredBedtimeMinute = 0,
    this.preferredWakeHour = 7,
    this.preferredWakeMinute = 0,
    this.defaultAlarmEnabled = true,
    this.selectedSpotifyUri,
    this.selectedSpotifyTitle,
    this.remoteMonitoringOptIn = false,
    this.lastSuccessfulCheckInIso,
  });

  bool hasCompletedOnboarding;
  int defaultSleepTimerSeconds;
  int preferredBedtimeHour;
  int preferredBedtimeMinute;
  int preferredWakeHour;
  int preferredWakeMinute;
  bool defaultAlarmEnabled;
  String? selectedSpotifyUri;
  String? selectedSpotifyTitle;
  bool remoteMonitoringOptIn;
  String? lastSuccessfulCheckInIso;

  Map<String, dynamic> toJson() => {
        'hasCompletedOnboarding': hasCompletedOnboarding,
        'defaultSleepTimerSeconds': defaultSleepTimerSeconds,
        'preferredBedtimeHour': preferredBedtimeHour,
        'preferredBedtimeMinute': preferredBedtimeMinute,
        'preferredWakeHour': preferredWakeHour,
        'preferredWakeMinute': preferredWakeMinute,
        'defaultAlarmEnabled': defaultAlarmEnabled,
        'selectedSpotifyUri': selectedSpotifyUri,
        'selectedSpotifyTitle': selectedSpotifyTitle,
        'remoteMonitoringOptIn': remoteMonitoringOptIn,
        'lastSuccessfulCheckInIso': lastSuccessfulCheckInIso,
      };

  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    return UserPreferences(
      hasCompletedOnboarding: json['hasCompletedOnboarding'] as bool? ?? false,
      defaultSleepTimerSeconds: json['defaultSleepTimerSeconds'] as int? ?? 30 * 60,
      preferredBedtimeHour: json['preferredBedtimeHour'] as int? ?? 22,
      preferredBedtimeMinute: json['preferredBedtimeMinute'] as int? ?? 0,
      preferredWakeHour: json['preferredWakeHour'] as int? ?? 7,
      preferredWakeMinute: json['preferredWakeMinute'] as int? ?? 0,
      defaultAlarmEnabled: json['defaultAlarmEnabled'] as bool? ?? true,
      selectedSpotifyUri: json['selectedSpotifyUri'] as String?,
      selectedSpotifyTitle: json['selectedSpotifyTitle'] as String?,
      remoteMonitoringOptIn: json['remoteMonitoringOptIn'] as bool? ?? false,
      lastSuccessfulCheckInIso: json['lastSuccessfulCheckInIso'] as String?,
    );
  }
}

enum MusicSource { spotify, local, none }

enum RoutineState {
  idle,
  starting,
  playing,
  timerRunning,
  stopping,
  completed,
  interrupted,
  failed,
}

class SleepRoutine {
  SleepRoutine({
    required this.id,
    required this.sleepTimerDurationSeconds,
    this.isEnabled = true,
    this.musicSource = MusicSource.none,
    this.startedAt,
    this.endsAt,
    this.alarmId,
  });

  final String id;
  bool isEnabled;
  MusicSource musicSource;
  int sleepTimerDurationSeconds;
  DateTime? startedAt;
  DateTime? endsAt;
  String? alarmId;

  Map<String, dynamic> toJson() => {
        'id': id,
        'isEnabled': isEnabled,
        'musicSource': musicSource.name,
        'sleepTimerDurationSeconds': sleepTimerDurationSeconds,
        'startedAt': startedAt?.toIso8601String(),
        'endsAt': endsAt?.toIso8601String(),
        'alarmId': alarmId,
      };

  factory SleepRoutine.fromJson(Map<String, dynamic> json) {
    return SleepRoutine(
      id: json['id'] as String,
      isEnabled: json['isEnabled'] as bool? ?? true,
      musicSource: MusicSource.values.firstWhere(
        (e) => e.name == json['musicSource'],
        orElse: () => MusicSource.none,
      ),
      sleepTimerDurationSeconds: json['sleepTimerDurationSeconds'] as int? ?? 1800,
      startedAt: json['startedAt'] != null ? DateTime.parse(json['startedAt'] as String) : null,
      endsAt: json['endsAt'] != null ? DateTime.parse(json['endsAt'] as String) : null,
      alarmId: json['alarmId'] as String?,
    );
  }
}

class SleepAlarm {
  SleepAlarm({
    required this.id,
    required this.hour,
    required this.minute,
    this.label = 'Wake up',
    this.isEnabled = true,
    /// Dart [DateTime.weekday]: Mon=1 … Sun=7. Empty = once (next matching time).
    Set<int>? repeatDays,
  }) : repeatDays = repeatDays ?? <int>{};

  final String id;
  int hour;
  int minute;
  String label;
  bool isEnabled;
  Set<int> repeatDays;

  static const weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String get repeatSummary {
    if (repeatDays.isEmpty) return 'Once';
    final sorted = repeatDays.toList()..sort();
    if (sorted.length == 7) return 'Every day';
    if (sorted.length == 5 && sorted.join() == '12345') return 'Weekdays';
    if (sorted.length == 2 && sorted.join() == '67') return 'Weekends';
    return sorted.map((d) => weekdayLabels[d - 1]).join(' ');
  }

  /// Next local DateTime this alarm should fire (null if disabled).
  DateTime? nextFireAfter([DateTime? from]) {
    if (!isEnabled) return null;
    final now = from ?? DateTime.now();
    var candidate = DateTime(now.year, now.month, now.day, hour, minute);
    if (!candidate.isAfter(now)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    if (repeatDays.isEmpty) return candidate;
    while (!repeatDays.contains(candidate.weekday)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'hour': hour,
        'minute': minute,
        'label': label,
        'isEnabled': isEnabled,
        'repeatDays': repeatDays.toList(),
      };

  factory SleepAlarm.fromJson(Map<String, dynamic> json) {
    final days = (json['repeatDays'] as List?)?.cast<int>() ?? const <int>[];
    return SleepAlarm(
      id: json['id'] as String,
      hour: json['hour'] as int,
      minute: json['minute'] as int,
      label: json['label'] as String? ?? 'Wake up',
      isEnabled: json['isEnabled'] as bool? ?? true,
      repeatDays: days.toSet(),
    );
  }

  SleepAlarm copyWith({
    int? hour,
    int? minute,
    String? label,
    bool? isEnabled,
    Set<int>? repeatDays,
  }) {
    return SleepAlarm(
      id: id,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      label: label ?? this.label,
      isEnabled: isEnabled ?? this.isEnabled,
      repeatDays: repeatDays ?? Set<int>.from(this.repeatDays),
    );
  }
}

class DeviceStatus {
  DeviceStatus({
    required this.routineActive,
    required this.spotifyConnected,
    required this.alarmEnabled,
    required this.isPlayingOwnAudio,
    required this.lastCheckIn,
    this.batteryLevel,
    this.isCharging,
    this.routineStartedAt,
    this.sleepTimerEndsAt,
    this.nextAlarm,
  });

  final double? batteryLevel;
  final bool? isCharging;
  final bool routineActive;
  final DateTime? routineStartedAt;
  final DateTime? sleepTimerEndsAt;
  final bool spotifyConnected;
  final bool alarmEnabled;
  final DateTime? nextAlarm;
  final bool isPlayingOwnAudio;
  final DateTime lastCheckIn;

  Map<String, dynamic> toJson() => {
        'batteryLevel': batteryLevel,
        'isCharging': isCharging,
        'routineActive': routineActive,
        'routineStartedAt': routineStartedAt?.toUtc().toIso8601String(),
        'sleepTimerEndsAt': sleepTimerEndsAt?.toUtc().toIso8601String(),
        'spotifyConnected': spotifyConnected,
        'alarmEnabled': alarmEnabled,
        'nextAlarm': nextAlarm?.toUtc().toIso8601String(),
        'isPlayingOwnAudio': isPlayingOwnAudio,
        'lastCheckIn': lastCheckIn.toUtc().toIso8601String(),
      };
}

class SpotifyPlaylist {
  SpotifyPlaylist({
    required this.id,
    required this.name,
    required this.uri,
    required this.trackCount,
  });

  final String id;
  final String name;
  final String uri;
  final int trackCount;
}

class SpotifyTrack {
  SpotifyTrack({
    required this.id,
    required this.name,
    required this.artistName,
    required this.uri,
  });

  final String id;
  final String name;
  final String artistName;
  final String uri;
}
