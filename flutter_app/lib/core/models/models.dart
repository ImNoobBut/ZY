/// App-owned quiet sound catalog (shared IDs with Swift).
enum QuietSound {
  softTone,
  rain,
  whiteNoise,
  deepHum;

  String get displayName => switch (this) {
        QuietSound.softTone => 'Soft tone',
        QuietSound.rain => 'Rain',
        QuietSound.whiteNoise => 'White noise',
        QuietSound.deepHum => 'Deep hum',
      };

  static QuietSound fromId(String? id) {
    return QuietSound.values.firstWhere(
      (e) => e.name == id,
      orElse: () => QuietSound.softTone,
    );
  }
}

/// Fade-out window for app-owned audio at end of sleep timer.
const int kFadeOutSeconds = 300;

class UserPreferences {
  UserPreferences({
    this.hasCompletedOnboarding = false,
    this.displayName = '',
    this.defaultSleepTimerSeconds = 30 * 60,
    this.preferredBedtimeHour = 22,
    this.preferredBedtimeMinute = 0,
    this.preferredWakeHour = 7,
    this.preferredWakeMinute = 0,
    this.defaultAlarmEnabled = true,
    this.bedtimeReminderEnabled = true,
    this.selectedQuietSound = QuietSound.softTone,
    this.selectedSpotifyUri,
    this.selectedSpotifyTitle,
    this.remoteMonitoringOptIn = false,
    this.lastSuccessfulCheckInIso,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  bool hasCompletedOnboarding;
  /// Greeting name; synced across devices via preferences.
  String displayName;
  int defaultSleepTimerSeconds;
  int preferredBedtimeHour;
  int preferredBedtimeMinute;
  int preferredWakeHour;
  int preferredWakeMinute;
  bool defaultAlarmEnabled;
  bool bedtimeReminderEnabled;
  QuietSound selectedQuietSound;
  String? selectedSpotifyUri;
  String? selectedSpotifyTitle;
  bool remoteMonitoringOptIn;
  String? lastSuccessfulCheckInIso;
  DateTime updatedAt;

  void touch() => updatedAt = DateTime.now().toUtc();

  String get preferredBedtimeLabel {
    final h = preferredBedtimeHour.toString().padLeft(2, '0');
    final m = preferredBedtimeMinute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Map<String, dynamic> toJson() => {
        'hasCompletedOnboarding': hasCompletedOnboarding,
        'displayName': displayName,
        'defaultSleepTimerSeconds': defaultSleepTimerSeconds,
        'preferredBedtimeHour': preferredBedtimeHour,
        'preferredBedtimeMinute': preferredBedtimeMinute,
        'preferredWakeHour': preferredWakeHour,
        'preferredWakeMinute': preferredWakeMinute,
        'defaultAlarmEnabled': defaultAlarmEnabled,
        'bedtimeReminderEnabled': bedtimeReminderEnabled,
        'selectedQuietSound': selectedQuietSound.name,
        'selectedSpotifyUri': selectedSpotifyUri,
        'selectedSpotifyTitle': selectedSpotifyTitle,
        'remoteMonitoringOptIn': remoteMonitoringOptIn,
        'lastSuccessfulCheckInIso': lastSuccessfulCheckInIso,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    return UserPreferences(
      hasCompletedOnboarding: json['hasCompletedOnboarding'] as bool? ?? false,
      displayName: (json['displayName'] as String?)?.trim() ?? '',
      defaultSleepTimerSeconds: json['defaultSleepTimerSeconds'] as int? ?? 30 * 60,
      preferredBedtimeHour: json['preferredBedtimeHour'] as int? ?? 22,
      preferredBedtimeMinute: json['preferredBedtimeMinute'] as int? ?? 0,
      preferredWakeHour: json['preferredWakeHour'] as int? ?? 7,
      preferredWakeMinute: json['preferredWakeMinute'] as int? ?? 0,
      defaultAlarmEnabled: json['defaultAlarmEnabled'] as bool? ?? true,
      bedtimeReminderEnabled: json['bedtimeReminderEnabled'] as bool? ?? true,
      selectedQuietSound: QuietSound.fromId(json['selectedQuietSound'] as String?),
      selectedSpotifyUri: json['selectedSpotifyUri'] as String?,
      selectedSpotifyTitle: json['selectedSpotifyTitle'] as String?,
      remoteMonitoringOptIn: json['remoteMonitoringOptIn'] as bool? ?? false,
      lastSuccessfulCheckInIso: json['lastSuccessfulCheckInIso'] as String?,
      updatedAt: _parseDate(json['updatedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}

DateTime? _parseDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toUtc();
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
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now().toUtc();

  final String id;
  bool isEnabled;
  MusicSource musicSource;
  int sleepTimerDurationSeconds;
  DateTime? startedAt;
  DateTime? endsAt;
  String? alarmId;
  DateTime updatedAt;

  void touch() => updatedAt = DateTime.now().toUtc();

  Map<String, dynamic> toJson() => {
        'id': id,
        'isEnabled': isEnabled,
        'musicSource': musicSource.name,
        'sleepTimerDurationSeconds': sleepTimerDurationSeconds,
        'startedAt': startedAt?.toIso8601String(),
        'endsAt': endsAt?.toIso8601String(),
        'alarmId': alarmId,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
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
      updatedAt: _parseDate(json['updatedAt']) ?? DateTime.now().toUtc(),
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
    DateTime? updatedAt,
  })  : repeatDays = repeatDays ?? <int>{},
        updatedAt = updatedAt ?? DateTime.now().toUtc();

  final String id;
  int hour;
  int minute;
  String label;
  bool isEnabled;
  Set<int> repeatDays;
  DateTime updatedAt;

  void touch() => updatedAt = DateTime.now().toUtc();

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
        'updatedAt': updatedAt.toUtc().toIso8601String(),
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
      updatedAt: _parseDate(json['updatedAt']) ?? DateTime.now().toUtc(),
    );
  }

  SleepAlarm copyWith({
    int? hour,
    int? minute,
    String? label,
    bool? isEnabled,
    Set<int>? repeatDays,
    DateTime? updatedAt,
  }) {
    return SleepAlarm(
      id: id,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      label: label ?? this.label,
      isEnabled: isEnabled ?? this.isEnabled,
      repeatDays: repeatDays ?? Set<int>.from(this.repeatDays),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class SleepSessionRecord {
  SleepSessionRecord({
    required this.id,
    required this.startedAt,
    this.musicStoppedAt,
    this.alarmTime,
    this.completedAt,
    this.notes,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now().toUtc();

  final String id;
  final DateTime startedAt;
  final DateTime? musicStoppedAt;
  final DateTime? alarmTime;
  final DateTime? completedAt;
  final String? notes;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'startedAt': startedAt.toIso8601String(),
        'musicStoppedAt': musicStoppedAt?.toIso8601String(),
        'alarmTime': alarmTime?.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'notes': notes,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  factory SleepSessionRecord.fromJson(Map<String, dynamic> json) {
    return SleepSessionRecord(
      id: json['id'] as String,
      startedAt: DateTime.parse(json['startedAt'] as String),
      musicStoppedAt: json['musicStoppedAt'] != null
          ? DateTime.parse(json['musicStoppedAt'] as String)
          : null,
      alarmTime:
          json['alarmTime'] != null ? DateTime.parse(json['alarmTime'] as String) : null,
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'] as String)
          : null,
      notes: json['notes'] as String?,
      updatedAt: _parseDate(json['updatedAt']) ?? DateTime.now().toUtc(),
    );
  }
}

/// Pending sync mutation stored in the local outbox.
class SyncMutation {
  SyncMutation({
    required this.entityType,
    required this.entityId,
    required this.payload,
    required this.updatedAt,
    this.deleted = false,
  });

  final String entityType;
  final String entityId;
  final Map<String, dynamic> payload;
  final DateTime updatedAt;
  final bool deleted;

  Map<String, dynamic> toJson() => {
        'entityType': entityType,
        'entityId': entityId,
        'payload': payload,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'deleted': deleted,
      };

  factory SyncMutation.fromJson(Map<String, dynamic> json) {
    return SyncMutation(
      entityType: json['entityType'] as String,
      entityId: json['entityId'] as String,
      payload: Map<String, dynamic>.from(json['payload'] as Map? ?? const {}),
      updatedAt: _parseDate(json['updatedAt']) ?? DateTime.now().toUtc(),
      deleted: json['deleted'] as bool? ?? false,
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
    this.preferredBedtime,
    this.currentStreak,
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
  final String? preferredBedtime;
  final int? currentStreak;

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
        'preferredBedtime': preferredBedtime,
        'currentStreak': currentStreak,
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
