import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flick/services/player_service.dart';

/// Opt-in Listening activity using Mornye's official Discord Social SDK bridge.
/// Android uses the installed Discord app's session; no Discord tokens enter Dart.
class DiscordPresenceService extends ChangeNotifier {
  DiscordPresenceService._();
  static final instance = DiscordPresenceService._();
  static const applicationId = String.fromEnvironment(
    'LOKAL_DISCORD_APPLICATION_ID',
    defaultValue: '1562522741817479302',
  );
  static const _channel = MethodChannel('com.zarz.mornye/discord');
  static const _preference = 'lokal_discord_presence_enabled';
  static const _interval = Duration(seconds: 15);

  PlayerService? _player;
  Future<void>? _starting;
  Future<void> _tail = Future.value();
  Timer? _pending;
  DateTime? _lastSent;
  Duration _lastPosition = Duration.zero;
  bool _running = false;
  bool _sdkAvailable = false;
  bool _enabled = false;
  String _status = 'Checking availability…';
  bool get enabled => _enabled;
  bool get configured =>
      Platform.isAndroid &&
      (int.tryParse(applicationId) ?? 0) > 0 &&
      _sdkAvailable;
  String get status => _status;

  Future<void> start(PlayerService player) => _starting ??= _start(player);

  Future<void> _start(PlayerService player) async {
    _player = player;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'status' && _enabled && _running) {
        _setStatus(switch (call.arguments) {
          'active' => 'Sharing your music on Discord',
          'unavailable' => 'Could not reach Discord. Check Discord’s activity privacy settings.',
          _ => 'Connecting to Discord…',
        });
      }
    });
    try {
      if (Platform.isAndroid) {
        _sdkAvailable = await _channel.invokeMethod<bool>('available') ?? false;
      }
      _enabled =
          (await SharedPreferences.getInstance()).getBool(_preference) ?? false;
    } on PlatformException {
      _sdkAvailable = false;
    } on MissingPluginException {
      _sdkAvailable = false;
    }
    if (!configured) {
      _setStatus(
        (int.tryParse(applicationId) ?? 0) <= 0
            ? 'This build needs Lokal’s Discord application configuration.'
            : 'Discord Social SDK is not included in this build.',
      );
      return;
    }
    player.currentSongNotifier.addListener(_schedule);
    player.isPlayingNotifier.addListener(_schedule);
    player.isNetworkLoadingNotifier.addListener(_schedule);
    player.durationNotifier.addListener(_schedule);
    player.playbackSpeedNotifier.addListener(_schedule);
    player.positionNotifier.addListener(_positionChanged);
    _setStatus(_enabled ? 'Ready when you play music' : 'Off');
    _schedule();
  }

  void _setStatus(String value) {
    _status = value;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    if (!configured) return;
    _enabled = value;
    await (await SharedPreferences.getInstance()).setBool(_preference, value);
    _setStatus(value ? 'Ready when you play music' : 'Off');
    _schedule();
  }

  void _positionChanged() {
    final position = _player!.positionNotifier.value;
    // Normal playback ticks need no request: Discord advances the timestamp.
    if ((position - _lastPosition).abs() > const Duration(seconds: 3)) {
      _schedule();
    }
    _lastPosition = position;
  }

  bool get _canPublish =>
      _enabled &&
      configured &&
      _player != null &&
      _player!.isPlayingNotifier.value &&
      !_player!.isNetworkLoadingNotifier.value &&
      _player!.currentSongNotifier.value != null;

  void _schedule() {
    _pending?.cancel();
    if (!_canPublish) {
      _enqueue(
        _stop,
      ); // Pause/stop/disable clear immediately, without rate limiting.
      return;
    }
    final elapsed = _lastSent == null
        ? _interval
        : DateTime.now().difference(_lastSent!);
    final delay = elapsed >= _interval ? Duration.zero : _interval - elapsed;
    _pending = Timer(delay, () => _enqueue(_publish));
  }

  void _enqueue(Future<void> Function() action) {
    _tail = _tail.then((_) async {
      try {
        await action();
      } on PlatformException {
        await _failed();
      } on MissingPluginException {
        await _failed();
      }
    });
  }

  Future<void> _failed() async {
    _running = false;
    try {
      await _channel.invokeMethod<void>('shutdown');
    } catch (_) {
      /* SDK already unavailable. */
    }
    if (_enabled) {
      _setStatus(
        'Discord is unavailable. Open Discord, then toggle sharing to retry.',
      );
    }
  }

  Future<void> _publish() async {
    if (!_canPublish) return;
    if (!_running) {
      _setStatus('Connecting to Discord…');
      _running =
          await _channel.invokeMethod<bool>('initialize', {
            'applicationId': applicationId,
          }) ??
          false;
      if (!_running) {
        _setStatus(
          'Could not connect. Install Discord and sign in, then toggle sharing to retry.',
        );
        return;
      }
    }
    if (!_canPublish) return;
    final player = _player!;
    final song = player.currentSongNotifier.value!;
    final speed = player.playbackSpeedNotifier.value;
    final rate = speed > 0 ? speed : 1.0;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final duration = player.durationNotifier.value > Duration.zero
        ? player.durationNotifier.value
        : song.duration;
    final position = player.positionNotifier.value.inMilliseconds.clamp(
      0,
      duration.inMilliseconds > 0 ? duration.inMilliseconds : 1 << 53,
    );
    final start = now - (position / 1000 / rate).round();
    final end = duration > Duration.zero
        ? now + ((duration.inMilliseconds - position) / 1000 / rate).round()
        : 0;
    await _channel.invokeMethod<void>('update', {
      'title': String.fromCharCodes(song.title.runes.take(128)),
      'state': String.fromCharCodes(song.artist.runes.take(128)),
      'artwork': publicArtwork(song.albumArt),
      'start': start,
      'end': end,
    });
    _lastSent = DateTime.now();
  }

  /// Send only recognized public image URLs. Never upload local covers or expose
  /// desktop LAN addresses, auth parameters, signed URLs or private server paths.
  @visibleForTesting
  static String publicArtwork(String? value) {
    final uri = Uri.tryParse(value ?? '');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.hasPort && uri.port != 443)) {
      return '';
    }
    const hosts = {
      'i.scdn.co',
      'i.ytimg.com',
      'lh3.googleusercontent.com',
      'coverartarchive.org',
      'is1-ssl.mzstatic.com',
      'is2-ssl.mzstatic.com',
      'is3-ssl.mzstatic.com',
      'is4-ssl.mzstatic.com',
      'is5-ssl.mzstatic.com',
    };
    return hosts.contains(uri.host.toLowerCase()) ? uri.toString() : '';
  }

  Future<void> _stop() async {
    if (_running) {
      await _channel.invokeMethod<void>('shutdown');
    }
    _running = false;
    _lastSent = null;
    if (configured) _setStatus(_enabled ? 'Ready when you play music' : 'Off');
  }

  Future<void> stop() async {
    _pending?.cancel();
    final player = _player;
    if (configured && player != null) {
      player.currentSongNotifier.removeListener(_schedule);
      player.isPlayingNotifier.removeListener(_schedule);
      player.isNetworkLoadingNotifier.removeListener(_schedule);
      player.durationNotifier.removeListener(_schedule);
      player.playbackSpeedNotifier.removeListener(_schedule);
      player.positionNotifier.removeListener(_positionChanged);
    }
    _player = null;
    await _tail;
    await _stop();
    _starting = null;
  }
}
