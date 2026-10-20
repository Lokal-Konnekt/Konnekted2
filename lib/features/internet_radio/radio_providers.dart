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
  final prefs = await SharedPreferences.getInstance();
  RadioCatalog? saved;
  try {
    final raw = prefs.getString(_catalogKey);
    if (raw != null) saved = parseRadioCatalog(jsonDecode(raw));
  } catch (_) {
    saved = null;
  }
  final client = http.Client();
  try {
    final data = await DiscoveryHttp(client).json(Uri.parse(url));
    final catalog = parseRadioCatalog(data);
    await prefs.setString(_catalogKey, jsonEncode(catalog.toJson()));
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
      if (state.station == null) return;
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

  Future<void> play(RadioStation station) async {
    if (!ref.read(internetRadioEnabledProvider)) return;
    if (ref.read(isPlayingProvider)) {
      await ref.read(playerProvider.notifier).pause();
    }
    // Radio requests audio focus through the app's own session, so set it
    // up (music, interruptions, ducking) as the library player would.
    await PlayerService().prepareAudioSessionForExternalPlayer();
    final player = _ensurePlayer();
    state = RadioPlayback(station: station, loading: true);
    _syncNotification();
    try {
      await player.setUrl(station.url);
      unawaited(player.play());
    } catch (_) {
      state = RadioPlayback(
        station: station,
        error: 'This station isn’t playing right now.',
      );
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
    final wasOn = state.station != null;
    state = const RadioPlayback();
    await _player?.stop();
    if (wasOn) await _releaseNotification();
  }
}

final radioPlayerProvider =
    NotifierProvider<RadioPlayerNotifier, RadioPlayback>(
      RadioPlayerNotifier.new,
    );
