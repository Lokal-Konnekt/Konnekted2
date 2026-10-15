import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'spotify_storage.dart';
import 'spotify_http.dart';

const spotifyRedirectUri = 'konnekted://oauth/spotify';

class SpotifyOAuthException implements Exception {
  const SpotifyOAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class SpotifyOAuthBrowser {
  Future<String?> authenticate({
    required Uri authorizationUrl,
    required String redirectUri,
  });

  Future<void> cancel();
}

/// Flutter-side bridge for the Android browser/callback helper. The helper
/// opens the system browser; it does not inspect cookies or embed Spotify.
class MethodChannelSpotifyOAuthBrowser implements SpotifyOAuthBrowser {
  const MethodChannelSpotifyOAuthBrowser({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('konnekted/spotify_auth');

  final MethodChannel _channel;

  @override
  Future<String?> authenticate({
    required Uri authorizationUrl,
    required String redirectUri,
  }) async {
    return _channel.invokeMethod<String>('authenticate', {
      'url': authorizationUrl.toString(),
      'redirectUri': redirectUri,
    });
  }

  @override
  Future<void> cancel() async {
    await _channel.invokeMethod<void>('cancel');
  }
}

abstract interface class SpotifyTokenExchange {
  Future<SpotifyTokens> exchangeCode({
    required String clientId,
    required String code,
    required String codeVerifier,
    required String redirectUri,
  });

  Future<SpotifyTokens> refreshToken({
    required String clientId,
    required String refreshToken,
  });
}

class HttpSpotifyTokenExchange implements SpotifyTokenExchange {
  HttpSpotifyTokenExchange({http.Client? client})
    : _client = client ?? http.Client();

  static final _tokenEndpoint = Uri.parse(
    'https://accounts.spotify.com/api/token',
  );
  final http.Client _client;

  @override
  Future<SpotifyTokens> exchangeCode({
    required String clientId,
    required String code,
    required String codeVerifier,
    required String redirectUri,
  }) async {
    return _post({
      'grant_type': 'authorization_code',
      'client_id': clientId,
      'code': code,
      'redirect_uri': redirectUri,
      'code_verifier': codeVerifier,
    });
  }

  @override
  Future<SpotifyTokens> refreshToken({
    required String clientId,
    required String refreshToken,
  }) async {
    return _post({
      'grant_type': 'refresh_token',
      'client_id': clientId,
      'refresh_token': refreshToken,
    });
  }

  Future<SpotifyTokens> _post(Map<String, String> fields) async {
    final response = await SpotifyHttp(_client)
        .send(_tokenEndpoint, form: fields);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SpotifyOAuthException(
        'Spotify authorization failed (HTTP ${response.statusCode}).',
      );
    }
    try {
      final json = SpotifyHttp.decode(response);
      final accessToken = json['access_token'];
      final expiresIn = json['expires_in'];
      if (accessToken is! String ||
          accessToken.isEmpty ||
          expiresIn is! num ||
          expiresIn <= 0 ||
          (json['token_type'] as String?)?.toLowerCase() != 'bearer') {
        throw const FormatException();
      }
      return SpotifyTokens(
        accessToken: accessToken,
        refreshToken: json['refresh_token'] as String?,
        expiresAt: DateTime.now().toUtc().add(
          Duration(seconds: expiresIn.toInt()),
        ),
      );
    } catch (_) {
      throw const SpotifyOAuthException('Spotify returned an invalid token.');
    }
  }
}

class SpotifyAuthorizationRequest {
  const SpotifyAuthorizationRequest({
    required this.url,
    required this.state,
    required this.codeVerifier,
    required this.createdAt,
  });

  final Uri url;
  final String state;
  final String codeVerifier;
  final DateTime createdAt;
}

class _PendingAuthorization {
  const _PendingAuthorization({
    required this.clientId,
    required this.state,
    required this.codeVerifier,
    required this.createdAt,
  });

  final String clientId;
  final String state;
  final String codeVerifier;
  final DateTime createdAt;
}

/// Authorization Code + PKCE coordinator. The pending verifier and state are
/// held in memory and consumed before exchanging a callback, making callbacks
/// one-use even when the browser replays a URI.
class SpotifyOAuthService {
  SpotifyOAuthService({
    required this._settings,
    required this._tokenStore,
    SpotifyOAuthBrowser? browser,
    SpotifyTokenExchange? exchange,
    DateTime Function()? now,
    Random? random,
  }) : _browser = browser ?? const MethodChannelSpotifyOAuthBrowser(),
       _exchange = exchange ?? HttpSpotifyTokenExchange(),
       _now = now ?? (() => DateTime.now().toUtc()),
       _random = random ?? Random.secure();

  static final _authorizationEndpoint = Uri.parse(
    'https://accounts.spotify.com/authorize',
  );
  static const scopes = <String>{
    'playlist-read-private',
    'playlist-read-collaborative',
    'user-library-read',
  };

  final SpotifySettingsStore _settings;
  final SpotifyTokenStore _tokenStore;
  final SpotifyOAuthBrowser _browser;
  final SpotifyTokenExchange _exchange;
  final DateTime Function() _now;
  final Random _random;
  _PendingAuthorization? _pending;
  int _epoch = 0;
  Future<SpotifyTokens?>? _refreshing;
  Future<void> _writes = Future.value();

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

  Future<bool> get isConnected async =>
      (await _tokenStore.readTokens()) != null;

  Future<SpotifyAuthorizationRequest> beginAuthorization() async {
    final clientId = await _settings.loadClientId();
    if (clientId.isEmpty) {
      throw const SpotifyOAuthException(
        'Enter your Spotify developer app client ID before connecting.',
      );
    }
    if (_pending != null) {
      throw const SpotifyOAuthException(
        'A Spotify sign-in is already in progress.',
      );
    }

    final state = _randomString(32);
    final verifier = _randomString(64);
    final createdAt = _now();
    _pending = _PendingAuthorization(
      clientId: clientId,
      state: state,
      codeVerifier: verifier,
      createdAt: createdAt,
    );
    final challenge = base64Url
        .encode(sha256.convert(utf8.encode(verifier)).bytes)
        .replaceAll('=', '');
    final url = _authorizationEndpoint.replace(
      queryParameters: {
        'client_id': clientId,
        'response_type': 'code',
        'redirect_uri': spotifyRedirectUri,
        'state': state,
        'code_challenge_method': 'S256',
        'code_challenge': challenge,
        'scope': scopes.join(' '),
        'show_dialog': 'true',
      },
    );
    return SpotifyAuthorizationRequest(
      url: url,
      state: state,
      codeVerifier: verifier,
      createdAt: createdAt,
    );
  }

  Future<SpotifyTokens> signIn() async {
    final request = await beginAuthorization();
    try {
      final callback = await _browser.authenticate(
        authorizationUrl: request.url,
        redirectUri: spotifyRedirectUri,
      );
      if (callback == null || callback.isEmpty) {
        throw const SpotifyOAuthException('Spotify sign-in was cancelled.');
      }
      return await finishAuthorization(callback);
    } catch (_) {
      _pending = null;
      rethrow;
    }
  }

  /// Completes a callback from a browser or a test. It consumes the pending
  /// state before validation and token exchange, so the same callback cannot be
  /// accepted twice.
  Future<SpotifyTokens> finishAuthorization(String callback) async {
    final epoch = _epoch;
    final pending = _pending;
    _pending = null;
    if (pending == null) {
      throw const SpotifyOAuthException('Spotify callback is no longer valid.');
    }
    if (_now().difference(pending.createdAt) > const Duration(minutes: 5)) {
      throw const SpotifyOAuthException('Spotify sign-in expired. Try again.');
    }
    final uri = Uri.tryParse(callback);
    if (uri == null || !_isExactRedirect(uri)) {
      throw const SpotifyOAuthException(
        'Spotify returned to an unexpected redirect URI.',
      );
    }
    if (uri.queryParametersAll['state']?.length != 1 ||
        uri.queryParameters['state'] != pending.state) {
      throw const SpotifyOAuthException('Spotify sign-in state did not match.');
    }
    final error = uri.queryParameters['error'];
    if (error != null && error.isNotEmpty) {
      throw const SpotifyOAuthException(
        'Spotify sign-in was denied or cancelled.',
      );
    }
    final code = uri.queryParameters['code'];
    if (code == null ||
        code.isEmpty ||
        uri.queryParametersAll['code']?.length != 1) {
      throw const SpotifyOAuthException(
        'Spotify did not return an authorization code.',
      );
    }

    final tokens = await _exchange.exchangeCode(
      clientId: pending.clientId,
      code: code,
      codeVerifier: pending.codeVerifier,
      redirectUri: spotifyRedirectUri,
    );
    if (epoch != _epoch) {
      throw const SpotifyOAuthException('Spotify sign-in was cancelled.');
    }
    await _persist(epoch, tokens);
    return tokens;
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
    if (current == null ||
        current.refreshToken == null ||
        current.refreshToken!.isEmpty) {
      return null;
    }
    final clientId = await _settings.loadClientId();
    if (clientId.isEmpty) return null;
    final fresh = await _exchange.refreshToken(
      clientId: clientId,
      refreshToken: current.refreshToken!,
    );
    final saved = fresh.refreshToken == null || fresh.refreshToken!.isEmpty
        ? fresh.copyWith(refreshToken: current.refreshToken)
        : fresh;
    if (epoch != _epoch) return null;
    await _persist(epoch, saved);
    return saved;
  }

  Future<void> cancel() async {
    _epoch++;
    _pending = null;
    await _browser.cancel();
  }

  Future<void> logout() async {
    _epoch++;
    _pending = null;
    await _persist(_epoch, null);
  }

  bool _isExactRedirect(Uri uri) {
    return uri.toString().split('?').first == spotifyRedirectUri &&
        !uri.hasFragment &&
        uri.userInfo.isEmpty;
  }

  String _randomString(int length) {
    const alphabet =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~';
    return List.generate(
      length,
      (_) => alphabet[_random.nextInt(alphabet.length)],
    ).join();
  }
}
