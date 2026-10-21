import 'package:flutter/services.dart';

import 'spotify_storage.dart';

const spotifyRedirectUri = 'konnekted://oauth/spotify';

class SpotifyOAuthException implements Exception {
  const SpotifyOAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The Android implementation follows BitChord's mobile flow: Spotify's real
/// account page is displayed in one in-app WebView and the resulting web
/// session is exchanged for a short-lived bearer token inside the app.
abstract interface class SpotifyOAuthBrowser {
  Future<String?> authenticate();

  Future<SpotifyTokens?> mintTokens(String sessionCookie);

  Future<void> cancel();

  Future<void> clearSession();
}

class MethodChannelSpotifyOAuthBrowser implements SpotifyOAuthBrowser {
  const MethodChannelSpotifyOAuthBrowser({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('konnekted/spotify_auth');

  final MethodChannel _channel;

  @override
  Future<String?> authenticate() => _channel.invokeMethod<String>('authenticate');

  @override
  Future<SpotifyTokens?> mintTokens(String sessionCookie) async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'mintTokens',
      {'sessionCookie': sessionCookie},
    );
    if (raw == null) return null;
    final accessToken = raw['accessToken'];
    final expiresAtMs = raw['expiresAtMs'];
    if (accessToken is! String || accessToken.isEmpty ||
        expiresAtMs is! num || expiresAtMs <= 0) {
      throw const SpotifyOAuthException('Spotify returned an invalid session token.');
    }
    final clientToken = raw['clientToken'];
    return SpotifyTokens(
      accessToken: accessToken,
      refreshToken: null,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        expiresAtMs.toInt(),
        isUtc: true,
      ),
      sessionCookie: sessionCookie,
      clientToken: clientToken is String && clientToken.isNotEmpty
          ? clientToken
          : null,
    );
  }

  @override
  Future<void> cancel() => _channel.invokeMethod<void>('cancel');

  @override
  Future<void> clearSession() => _channel.invokeMethod<void>('clearSession');
}

/// Coordinates the in-app web login and the short-lived token minted from its
/// Spotify session. The session cookie is kept in encrypted storage and is
/// never placed in ordinary preferences or sent to a non-Spotify host.
class SpotifyOAuthService {
  SpotifyOAuthService({
    required SpotifyTokenStore tokenStore,
    SpotifyOAuthBrowser? browser,
  }) : _tokenStore = tokenStore,
       _browser = browser ?? const MethodChannelSpotifyOAuthBrowser();

  final SpotifyTokenStore _tokenStore;
  final SpotifyOAuthBrowser _browser;
  int _epoch = 0;
  Future<SpotifyTokens?>? _refreshing;
  Future<void> _writes = Future.value();

  Future<bool> get isConnected async =>
      (await _tokenStore.readTokens())?.sessionCookie?.isNotEmpty == true;

  Future<void> _persist(int epoch, SpotifyTokens? tokens) {
    final next = _writes.then((_) async {
      if (epoch != _epoch) return;
      if (tokens == null) {
        await _tokenStore.clearTokens();
      } else {
        await _tokenStore.writeTokens(tokens);
      }
    });
    _writes = next.catchError((Object _) {});
    return next;
  }

  Future<SpotifyTokens> signIn() async {
    final epoch = _epoch;
    final sessionCookie = await _browser.authenticate();
    if (sessionCookie == null || sessionCookie.trim().isEmpty) {
      throw const SpotifyOAuthException('Spotify sign-in was cancelled.');
    }
    final minted = await _browser.mintTokens(sessionCookie);
    if (minted == null) {
      throw const SpotifyOAuthException(
        'Spotify sign-in completed, but its web session could not be verified.',
      );
    }
    if (epoch != _epoch) {
      throw const SpotifyOAuthException('Spotify sign-in was cancelled.');
    }
    await _persist(epoch, minted.copyWith(sessionCookie: sessionCookie));
    return minted;
  }

  /// Imports a manually copied Spotify session cookie from Discovery.
  /// Only the sp_dc value is saved; the token store encrypts it at rest.
  Future<SpotifyTokens> signInWithCookie(String input) async {
    final sessionCookie = _extractSpDc(input);
    if (sessionCookie.isEmpty) {
      throw const SpotifyOAuthException('Enter a Spotify sp_dc cookie.');
    }
    final epoch = _epoch;
    final minted = await _browser.mintTokens(sessionCookie);
    if (minted == null) {
      throw const SpotifyOAuthException(
        'Spotify could not verify that session cookie. Check it and try again.',
      );
    }
    if (epoch != _epoch) {
      throw const SpotifyOAuthException('Spotify sign-in was cancelled.');
    }
    final saved = minted.copyWith(sessionCookie: sessionCookie);
    await _persist(epoch, saved);
    return saved;
  }

  static String _extractSpDc(String input) {
    final value = input.trim();
    if (value.isEmpty) return '';
    final named = RegExp(r'(?:^|[;\s])sp_dc=([^;\s]+)').firstMatch(value);
    if (named != null) return named.group(1)?.trim() ?? '';
    if (value.toLowerCase().startsWith('sp_dc=')) {
      return value.substring('sp_dc='.length).split(';').first.trim();
    }
    return value;
  }

  Future<SpotifyTokens?> refresh() async {
    final active = _refreshing;
    if (active != null) return active;
    final future = _refresh();
    _refreshing = future;
    try {
      return await future;
    } finally {
      _refreshing = null;
    }
  }

  Future<SpotifyTokens?> _refresh() async {
    final epoch = _epoch;
    final current = await _tokenStore.readTokens();
    final cookie = current?.sessionCookie;
    if (cookie == null || cookie.isEmpty) return null;
    final fresh = await _browser.mintTokens(cookie);
    if (fresh == null || epoch != _epoch) return null;
    final saved = fresh.copyWith(sessionCookie: cookie);
    await _persist(epoch, saved);
    return saved;
  }

  Future<void> cancel() async {
    _epoch++;
    await _browser.cancel();
  }

  Future<void> logout() async {
    _epoch++;
    await _browser.cancel();
    await _browser.clearSession();
    await _persist(_epoch, null);
  }
}
