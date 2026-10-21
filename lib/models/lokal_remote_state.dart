import 'dart:math' as math;

/// The commands the Lokal desktop remote endpoint currently accepts.
enum LokalRemoteAction {
  togglePlay,
  play,
  pause,
  next,
  prev,
  volume,
  seek,
  toggleLike,
}

extension LokalRemoteActionJson on LokalRemoteAction {
  String get wireName => switch (this) {
    LokalRemoteAction.togglePlay => 'togglePlay',
    LokalRemoteAction.play => 'play',
    LokalRemoteAction.pause => 'pause',
    LokalRemoteAction.next => 'next',
    LokalRemoteAction.prev => 'prev',
    LokalRemoteAction.volume => 'volume',
    LokalRemoteAction.seek => 'seek',
    LokalRemoteAction.toggleLike => 'toggleLike',
  };

  bool get requiresValue => switch (this) {
    LokalRemoteAction.volume || LokalRemoteAction.seek => true,
    _ => false,
  };
}

/// Credentials for one Lokal desktop instance. The origin is safe to keep in
/// ordinary preferences; the bearer values are persisted separately in secure
/// storage by [LokalRemoteCredentialsStore].
class LokalRemoteCredentials {
  const LokalRemoteCredentials({
    required this.origin,
    this.remoteToken = '',
    this.apiKey = '',
    this.desktopId,
    this.desktopUserId,
  });

  final Uri origin;
  final String remoteToken;
  final String apiKey;
  final String? desktopId;
  final String? desktopUserId;

  bool get hasRemoteToken => remoteToken.isNotEmpty;
  bool get hasApiKey => apiKey.isNotEmpty;
}

/// Non-secret connection details exposed to widgets.
class LokalRemoteConfig {
  const LokalRemoteConfig({
    required this.origin,
    required this.hasRemoteToken,
    required this.hasApiKey,
  });

  final Uri origin;
  final bool hasRemoteToken;
  final bool hasApiKey;

  factory LokalRemoteConfig.fromCredentials(LokalRemoteCredentials value) =>
      LokalRemoteConfig(
        origin: value.origin,
        hasRemoteToken: value.hasRemoteToken,
        hasApiKey: value.hasApiKey,
      );
}

class LokalRemoteTrack {
  const LokalRemoteTrack({
    this.id,
    required this.title,
    required this.artist,
    this.album = '',
    this.artworkPath,
    this.duration = 0,
    this.fileHash,
    this.fileType = 'bin',
    this.hasArtwork = false,
    this.liked = false,
  });

  final String? id;
  final String title;
  final String artist;
  final String album;

  /// Desktop filesystem paths are intentionally not loaded by Android. The
  /// field is retained only for a future authenticated artwork endpoint.
  final String? artworkPath;
  final double duration;
  final String? fileHash;
  final String fileType;
  final bool hasArtwork;
  final bool liked;
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'album': album,
    'duration': duration,
    'file_hash': fileHash,
    'fileType': fileType,
    'hasArtwork': hasArtwork,
    'liked': liked,
  };

  factory LokalRemoteTrack.fromJson(Map<Object?, Object?> json) {
    String text(String key) => json[key] is String ? json[key] as String : '';
    final id = text('id');
    return LokalRemoteTrack(
      id: id.isEmpty ? null : id,
      title: text('title'),
      artist: text('artist'),
      album: text('album'),
      artworkPath: text('artwork_path').isEmpty ? null : text('artwork_path'),
      duration: json['duration'] is num
          ? (json['duration'] as num).toDouble()
          : 0,
      fileHash: json['file_hash'] as String?,
      fileType: json['fileType'] as String? ?? 'bin',
      hasArtwork: json['hasArtwork'] == true,
      liked: json['liked'] == true,
    );
  }
}

class LokalRemoteSnapshot {
  const LokalRemoteSnapshot({
    required this.connected,
    required this.isPlaying,
    required this.progress,
    required this.duration,
    required this.volume,
    required this.repeat,
    required this.shuffle,
    required this.currentTrack,
    required this.updatedAt,
    this.queue = const [],
    this.currentIndex = -1,
  });

  final bool connected;
  final bool isPlaying;
  final double progress;
  final double duration;
  final double volume;
  final String repeat;
  final bool shuffle;
  final LokalRemoteTrack? currentTrack;

  /// Epoch milliseconds assigned by the desktop renderer. Zero means an old
  /// server response that did not include a revision timestamp.
  final int updatedAt;
  final List<LokalRemoteTrack> queue;
  final int currentIndex;

  factory LokalRemoteSnapshot.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('Remote state is not an object.');
    }
    final json = Map<Object?, Object?>.from(raw);

    bool boolean(String key, {bool fallback = false}) {
      final value = json[key];
      return value is bool ? value : fallback;
    }

    double number(String key, {double fallback = 0}) {
      final value = json[key];
      if (value == null) return fallback;
      if (value is! num || !value.isFinite) {
        throw FormatException('Remote state field "$key" is invalid.');
      }
      return value.toDouble();
    }

    final duration = math.max(0, number('duration'));
    final progress = math.max(0, number('progress')).clamp(0, duration);
    final volume = number('volume', fallback: 1).clamp(0, 1);
    final repeatValue = json['repeat'];
    final repeat =
        repeatValue is String &&
            const {'none', 'all', 'one'}.contains(repeatValue)
        ? repeatValue
        : 'none';
    final updatedValue = json['updatedAt'];
    final updatedAt = updatedValue is num && updatedValue.isFinite
        ? math.max(0, updatedValue.toInt())
        : 0;
    final trackValue = json['currentTrack'];

    return LokalRemoteSnapshot(
      connected: boolean('connected'),
      isPlaying: boolean('isPlaying'),
      progress: progress.toDouble(),
      duration: duration.toDouble(),
      volume: volume.toDouble(),
      repeat: repeat,
      shuffle: boolean('shuffle'),
      currentTrack: trackValue is Map
          ? LokalRemoteTrack.fromJson(Map<Object?, Object?>.from(trackValue))
          : null,
      updatedAt: updatedAt,
      queue: [
        for (final value
            in json['queue'] is List ? json['queue'] as List : const [])
          if (value is Map)
            LokalRemoteTrack.fromJson(Map<Object?, Object?>.from(value)),
      ],
      currentIndex: json['currentIndex'] is int
          ? json['currentIndex'] as int
          : -1,
    );
  }
}

enum LokalRemoteConnectionStatus {
  unconfigured,
  disconnected,
  connecting,
  connected,
  offline,
  unauthorized,
}

class LokalRemoteControllerState {
  const LokalRemoteControllerState({
    this.config,
    this.status = LokalRemoteConnectionStatus.unconfigured,
    this.snapshot,
    this.error,
    this.lastSeenAt,
    this.commandInFlight = false,
    this.socketConnected = false,
    this.controlsDesktop = false,
    this.desktopName = 'Lokal desktop',
    this.mergeApproved = false,
    this.syncPreview,
  });

  final LokalRemoteConfig? config;
  final LokalRemoteConnectionStatus status;
  final LokalRemoteSnapshot? snapshot;
  final String? error;
  final DateTime? lastSeenAt;
  final bool commandInFlight;
  final bool socketConnected;
  final bool controlsDesktop;
  final String desktopName;
  final bool mergeApproved;
  final Map<String, dynamic>? syncPreview;

  bool get configured => config != null;
  bool get reachable => status == LokalRemoteConnectionStatus.connected;

  LokalRemoteControllerState copyWith({
    LokalRemoteConfig? config,
    bool clearConfig = false,
    LokalRemoteConnectionStatus? status,
    LokalRemoteSnapshot? snapshot,
    bool clearSnapshot = false,
    String? error,
    bool clearError = false,
    DateTime? lastSeenAt,
    bool? commandInFlight,
    bool? socketConnected,
    bool? controlsDesktop,
    String? desktopName,
    bool? mergeApproved,
    Map<String, dynamic>? syncPreview,
  }) => LokalRemoteControllerState(
    config: clearConfig ? null : config ?? this.config,
    status: status ?? this.status,
    snapshot: clearSnapshot ? null : snapshot ?? this.snapshot,
    error: clearError ? null : error ?? this.error,
    lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    commandInFlight: commandInFlight ?? this.commandInFlight,
    socketConnected: socketConnected ?? this.socketConnected,
    controlsDesktop: controlsDesktop ?? this.controlsDesktop,
    desktopName: desktopName ?? this.desktopName,
    mergeApproved: mergeApproved ?? this.mergeApproved,
    syncPreview: syncPreview ?? this.syncPreview,
  );
}
