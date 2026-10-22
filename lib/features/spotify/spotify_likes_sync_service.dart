import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'spotify_http.dart';
import 'spotify_oauth.dart';
import 'spotify_storage.dart';
import 'spotify_sync.dart';
import 'spotify_web_api.dart';

/// Explicit, additive local-favorites sync. No streamed library placeholders.
class SpotifyLikesSyncService {
  SpotifyLikesSyncService._();
  static final instance = SpotifyLikesSyncService._();
  static const enabledKey = 'lokal.spotify.sync_likes';
  static const cursorKey = 'lokal.spotify.sync_likes_since';
  final status = ValueNotifier<String?>(null);
  Timer? _timer;
  SpotifyCancellation? _cancel;
  bool _running = false;
  Future<bool> get enabled async =>
      (await SharedPreferences.getInstance()).getBool(enabledKey) ?? false;
  void resume() {
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => unawaited(sync()),
    );
    unawaited(sync());
  }

  void pause() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> setEnabled(bool value) async {
    await (await SharedPreferences.getInstance()).setBool(enabledKey, value);
    if (!value) {
      _cancel?.cancel();
      status.value = null;
    } else {
      unawaited(sync());
    }
  }

  Future<void> resetCursor() async {
    _cancel?.cancel();
    await (await SharedPreferences.getInstance()).remove(cursorKey);
  }

  Future<void> sync() async {
    if (_running) return;
    _running = true;
    final cancellation = SpotifyCancellation();
    _cancel = cancellation;
    SpotifyWebApi? api;
    try {
      if (!await enabled) return;
      final prefs = await SharedPreferences.getInstance();
      final store = SecureSpotifyTokenStore();
      if ((await store.readTokens())?.sessionCookie?.isNotEmpty != true) return;
      cancellation.check();
      final started = DateTime.now().toUtc();
      status.value = 'Syncing Spotify liked songs…';
      final cursor = prefs.getInt(cursorKey);
      api = SpotifyWebApi(
        store: store,
        oauth: SpotifyOAuthService(tokenStore: store),
        likesSince: cursor == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(cursor, isUtc: true),
      );
      final sync = SpotifySyncService(
        api: api,
        metadata: SpotifyMetadataStore(
          SharedPreferencesSpotifyPreferenceStore(),
        ),
      );
      final report = await sync.syncLikedSongs(
        cancellation: cancellation,
        onProgress: (n) => status.value = 'Syncing Spotify liked songs: $n…',
      );
      cancellation.check();
      await prefs.setInt(cursorKey, started.millisecondsSinceEpoch);
      status.value =
          'Spotify likes synced: ${report.addedCount} added to Favorites.';
    } catch (error) {
      status.value = cancellation.isCancelled
          ? null
          : 'Spotify likes could not sync. Check your cookie and try again.';
    } finally {
      api?.close();
      _running = false;
      _cancel = null;
    }
  }
}
