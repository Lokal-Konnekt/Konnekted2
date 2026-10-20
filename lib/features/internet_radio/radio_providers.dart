import 'dart:async';
import 'dart:convert';

import 'package:flick/features/discovery/discovery_http.dart';
import 'package:flick/models/song.dart';
import 'package:flick/services/notification_service.dart';
import 'package:flick/services/player_service.dart';
import 'package:flick/providers/opt_in_source_provider.dart';
import 'package:flick/providers/player_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart' as ja;
import 'package:shared_preferences/shared_preferences.dart';

import 'radio_catalog.dart';

const _urlKey = 'lokal_radio_catalog_url';
const _catalogKey = 'lokal_radio_catalog';
const _favoritesKey = 'lokal_radio_favorites';
const _radioLoadTimeout = Duration(seconds: 20);
const _radioStorageTimeout = Duration(seconds: 8);
const _radioStopTimeout = Duration(seconds: 3);

/// The station list's link: desktop's default until the user sets another.
class RadioCatalogUrlNotifier extends Notifier<String> {
  @override
  String build() {
    unawaited(_load());
    return defaultRadioCatalogUrl;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_urlKey);
    if (ref.mounted && saved != null && saved.isNotEmpty) state = saved;
  }

  /// An empty [url] goes back to the default list.
  Future<void> set(String url) async {
    final value = url.trim().isEmpty ? defaultRadioCatalogUrl : url.trim();
    state = value;
    final prefs = await SharedPreferences.getInstance();
    if (value == defaultRadioCatalogUrl) {
      await prefs.remove(_urlKey);
    } else {
      await prefs.setString(_urlKey, value);
    }
  }
}

final radioCatalogUrlProvider =
    NotifierProvider<RadioCatalogUrlNotifier, String>(
      RadioCatalogUrlNotifier.new,
    );

/// The station list: the saved copy at once, then the link's current one.
/// Nothing is fetched while internet radio is off.
final radioCatalogProvider = FutureProvider<RadioCatalog?>((ref) async {
  if (!ref.watch(internetRadioEnabledProvider)) return null;
  final url = ref.watch(radioCatalogUrlProvider);
  final prefs = await radioWithTimeout(
    SharedPreferences.getInstance(),
    timeout: _radioStorageTimeout,
    timeoutMessage: 'Radio settings took too long to load. Try again.',
  );
  RadioCatalog? saved;
  try {
    final raw = prefs.getString(_catalogKey);
    if (raw != null) saved = parseRadioCatalog(jsonDecode(raw));
  } catch (_) {
    saved = null;
  }
  final client = http.Client();
  try {
    final data = await radioWithTimeout(
      DiscoveryHttp(client).json(Uri.parse(url)),
      timeout: _radioLoadTimeout,
      timeoutMessage: 'The station list timed out. Check your connection or link.',
    );
    final catalog = parseRadioCatalog(data);
    // Caching is best-effort. A slow local preferences write must not prevent
    // the successfully fetched stations from appearing.
    try {
      await radioWithTimeout(
        prefs.setString(_catalogKey, jsonEncode(catalog.toJson())),
        timeout: _radioStorageTimeout,
        timeoutMessage: 'Saving the station list timed out.',
      );
    } catch (_) {
      // The in-memory catalogue is usable even if caching fails.
    }
    return catalog;
  } catch (e) {
    if (saved != null) return saved;
    if (e is RadioCatalogException) rethrow;
    throw const RadioCatalogException(
      'Couldn’t load the station list. Check your connection or the link.',
    );
  } finally {
    client.close();
  }
});

/// Favourite stations, by stream link, kept on this device.
class RadioFavoritesNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    unawaited(_load());
    return const {};
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_favoritesKey);
    if (ref.mounted && saved != null) state = saved.toSet();
  }

  Future<void> toggle(String stationId) async {
    final next = Set<String>.of(state);
    if (!next.remove(stationId)) next.add(stationId);
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favoritesKey, next.toList());
  }
}

final radioFavoritesProvider =
    NotifierProvider<RadioFavoritesNotifier, Set<String>>(
      RadioFavoritesNotifier.new,
    );

@immutable
class RadioPlayback {
  const RadioPlayback({
    this.station,
    this.playing = false,
    this.loading = false,
    this.error,
  });

  final RadioStation? station;
  final bool playing;
  final bool loading;
  final String? error;
}

/// Plays a station's live stream.
///
/// The library player (PlayerService, ExoPlayer or the Rust engine) caches a
/// network song to a local file before or while playing, which a live,
/// endless stream can't do, so stations play on their own just_audio player.
/// Starting a station pauses the library player; playing a song stops the
/// station.
///
/// While a station is on it borrows the app's media notification (and so
/// the lock-screen controls and the foreground service that keeps playback
/// going in the background), and hands it back to the library when it stops.
class RadioPlayerNotifier extends Notifier<RadioPlayback> {
  ja.AudioPlayer? _player;
  int _playRequest = 0;
  StreamSubscription<ja.PlayerState>? _states;
  String? _notified;
  final Map<String, String> _iconFiles = {};

  late final MediaNotificationOwner _notificationOwner = MediaNotificationOwner(
    onTogglePlayPause: () => unawaited(toggle()),
    onPlay: () {
      if (!state.playing) unawaited(toggle());
    },
    onPause: () => unawaited(_player?.pause()),
    onStop: () => unawaited(stop()),
  );

  @override
  RadioPlayback build() {
    ref.listen<bool>(isPlayingProvider, (_, playing) {
      if (playing && state.station != null) unawaited(stop());
    });
    ref.onDispose(() {
      NotificationService().release(_notificationOwner);
      unawaited(_states?.cancel());
      unawaited(_player?.dispose());
    });
    return const RadioPlayback();
  }

  ja.AudioPlayer _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;
    final player = ja.AudioPlayer();
    _states = player.playerStateStream.listen((s) {
      // Once a failed request is reported, late buffering/loading events from
      // that same request must not put the spinner back on screen.
      if (state.station == null || state.error != null) return;
      final loading =
          s.processingState == ja.ProcessingState.loading ||
          s.processingState == ja.ProcessingState.buffering;
      state = RadioPlayback(
        station: state.station,
        playing: s.playing && s.processingState != ja.ProcessingState.completed,
        loading: loading,
        error: state.error,
      );
      _syncNotification();
    });
    return _player = player;
  }

  /// Mirrors the station into the media notification when what it shows
  /// (station, playing, icon) changed.
  void _syncNotification() {
    final station = state.station;
    if (station == null) return;
    final icon = _iconFiles[station.icon ?? ''];
    final key = '${station.id}|${state.playing}|$icon';
    if (key == _notified) return;
    _notified = key;
    final song = Song(
      id: 'radio:${station.id}',
      title: station.title,
      artist: station.genre ?? station.description ?? 'Internet radio',
      albumArt: icon,
      duration: Duration.zero,
      fileType: 'Stream',
    );
    unawaited(
      NotificationService().showFor(
        _notificationOwner,
        song: song,
        isPlaying: state.playing,
      ),
    );
    if (icon == null) unawaited(_fetchIcon(station));
  }

  /// The notification reads its picture from a file: cache the station's
  /// icon and show it once it is there.
  Future<void> _fetchIcon(RadioStation station) async {
    final url = station.icon;
    if (url == null || _iconFiles.containsKey(url)) return;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return;
    try {
      final file = await DefaultCacheManager().getSingleFile(url);
      _iconFiles[url] = file.path;
      if (ref.mounted && state.station?.id == station.id) _syncNotification();
    } catch (_) {
      // No icon: the notification shows the station without a picture.
    }
  }

  Future<void> _releaseNotification() async {
    _notified = null;
    final notifications = NotificationService();
    if (!notifications.isClaimed) return;
    notifications.release(_notificationOwner);
    final player = PlayerService();
    if (player.currentSongNotifier.value != null) {
      await player.refreshNotificationState();
    } else {
      await notifications.hideNotification();
    }
  }

  bool _isCurrentPlay(int request, RadioStation station) =>
      ref.mounted &&
      request == _playRequest &&
      state.station?.id == station.id;

  Future<void> _failPlay(int request, RadioStation station) async {
    if (!_isCurrentPlay(request, station)) return;
    try {
      await _player?.stop().timeout(_radioStopTimeout);
    } catch (_) {
      // The UI still needs to leave its loading state if the engine stalls.
    }
    if (!_isCurrentPlay(request, station)) return;
    state = RadioPlayback(
      station: station,
      error: 'This station could not start. Check the stream or try another.',
    );
    _syncNotification();
  }

  Future<void> play(RadioStation station) async {
    if (!ref.read(internetRadioEnabledProvider)) return;
    final request = ++_playRequest;
    // Set loading before awaiting session/player setup so every failure path
    // is visible and can also be cleared by stop().
    state = RadioPlayback(station: station, loading: true);
    _syncNotification();
    try {
      final player = _ensurePlayer();
      if (ref.read(isPlayingProvider)) {
        await radioWithTimeout(
          ref.read(playerProvider.notifier).pause(),
          timeout: _radioStopTimeout,
          timeoutMessage: 'The current player did not pause in time.',
        );
      }
      if (!_isCurrentPlay(request, station)) return;

      // Share the app's audio focus/session with just_audio, but don't let
      // platform setup keep the station spinner alive forever.
      await radioWithTimeout(
        PlayerService().prepareAudioSessionForExternalPlayer(),
        timeout: _radioStopTimeout,
        timeoutMessage: 'Audio setup took too long. Try again.',
      );
      if (!_isCurrentPlay(request, station)) return;

      await radioWithTimeout(
        player.setUrl(station.url),
        timeout: _radioLoadTimeout,
        timeoutMessage: 'The station stream did not respond in time.',
      );
      if (!_isCurrentPlay(request, station)) return;

      // setUrl can finish while a live stream still never supplies playable
      // audio. Wait for the first ready/playing state as well, with a deadline.
      final started = Completer<void>();
      final readySubscription = player.playerStateStream.listen(
        (value) {
          if (!started.isCompleted &&
              value.playing &&
              value.processingState == ja.ProcessingState.ready) {
            started.complete();
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!started.isCompleted) started.completeError(error, stackTrace);
        },
      );
      unawaited(
        player.play().catchError((Object error) {
          if (!started.isCompleted) {
            started.completeError(error);
          } else if (_isCurrentPlay(request, station)) {
            unawaited(_failPlay(request, station));
          }
        }),
      );
      try {
        await radioWithTimeout(
          started.future,
          timeout: _radioLoadTimeout,
          timeoutMessage: 'The station did not begin playing in time.',
        );
      } finally {
        await readySubscription.cancel();
      }
      if (!_isCurrentPlay(request, station)) return;
      // The state stream usually delivered this already; set it explicitly so
      // the initial load cannot remain visible if that event was missed.
      state = RadioPlayback(station: station, playing: true);
      _syncNotification();
    } catch (_) {
      await _failPlay(request, station);
    }
  }

  Future<void> toggle() async {
    final player = _player;
    final station = state.station;
    if (player == null || station == null) return;
    if (player.playing) {
      await player.pause();
    } else {
      if (ref.read(isPlayingProvider)) {
        await ref.read(playerProvider.notifier).pause();
      }
      // A live stream resumes at "now", not where it was paused.
      await play(station);
    }
  }

  Future<void> stop() async {
    // Ignore completions from an earlier setUrl/play request.
    _playRequest++;
    final wasOn = state.station != null;
    state = const RadioPlayback();
    try {
      await _player?.stop().timeout(_radioStopTimeout);
    } catch (_) {
      // Reset the UI even if the platform player doesn't acknowledge stop.
    }
    if (wasOn) await _releaseNotification();
  }
}

final radioPlayerProvider =
    NotifierProvider<RadioPlayerNotifier, RadioPlayback>(
      RadioPlayerNotifier.new,
    );
