import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'package:flick/features/spotify/spotify_api.dart';
import 'package:flick/features/spotify/spotify_http.dart';
import 'package:flick/features/spotify/spotify_models.dart';
import 'package:flick/features/spotify/spotify_oauth.dart';
import 'package:flick/features/spotify/spotify_storage.dart';
import 'package:flick/features/spotify/spotify_sync.dart';
import 'package:flick/models/song.dart';

class _MemoryPreferences implements SpotifyPreferenceStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _MemoryTokens implements SpotifyTokenStore {
  SpotifyTokens? value;

  @override
  Future<SpotifyTokens?> readTokens() async => value;

  @override
  Future<void> clearTokens() async => value = null;

  @override
  Future<void> writeTokens(SpotifyTokens tokens) async => value = tokens;
}

class _Browser implements SpotifyOAuthBrowser {
  Uri? opened;
  String? callback;

  @override
  Future<String?> authenticate({
    required Uri authorizationUrl,
    required String redirectUri,
  }) async {
    opened = authorizationUrl;
    callback = '$redirectUri?code=one-use-code&state=${authorizationUrl.queryParameters['state']}';
    return callback;
  }

  @override
  Future<void> cancel() async {}
}

class _Exchange implements SpotifyTokenExchange {
  String? codeVerifier;

  @override
  Future<SpotifyTokens> exchangeCode({
    required String clientId,
    required String code,
    required String codeVerifier,
    required String redirectUri,
  }) async {
    this.codeVerifier = codeVerifier;
    return SpotifyTokens(
      accessToken: 'access',
      refreshToken: 'refresh',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
  }

  @override
  Future<SpotifyTokens> refreshToken({
    required String clientId,
    required String refreshToken,
  }) async {
    return SpotifyTokens(
      accessToken: 'refreshed',
      refreshToken: refreshToken,
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
  }
}

Song _song(String id, String title, String artist, int seconds) => Song(
      id: id,
      title: title,
      artist: artist,
      duration: Duration(seconds: seconds),
      fileType: 'FLAC',
    );

void main() {
  test('PKCE callback is exact, state-bound, and one-use', () async {
    final preferences = _MemoryPreferences();
    final tokens = _MemoryTokens();
    final settings = SpotifySettingsStore(
      preferences: preferences,
      tokenStore: tokens,
    );
    await settings.saveClientId('client-id');
    final browser = _Browser();
    final exchange = _Exchange();
    final oauth = SpotifyOAuthService(
      settings: settings,
      tokenStore: tokens,
      browser: browser,
      exchange: exchange,
      random: Random(2),
    );

    final result = await oauth.signIn();

    expect(result.accessToken, 'access');
    expect(browser.opened?.scheme, 'https');
    expect(browser.opened?.host, 'accounts.spotify.com');
    expect(browser.opened?.queryParameters['code_challenge_method'], 'S256');
    expect(exchange.codeVerifier, isNotEmpty);
    await expectLater(
      oauth.finishAuthorization(browser.callback!),
      throwsA(isA<SpotifyOAuthException>()),
    );
  });

  test('Spotify API follows same-origin pages and parses real metadata', () async {
    final preferences = _MemoryPreferences();
    final tokens = _MemoryTokens()
      ..value = SpotifyTokens(
        accessToken: 'access',
        refreshToken: 'refresh',
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      );
    final settings = SpotifySettingsStore(
      preferences: preferences,
      tokenStore: tokens,
    );
    await settings.saveClientId('client-id');
    final oauth = SpotifyOAuthService(settings: settings, tokenStore: tokens);
    final client = MockClient((request) async {
      expect(request.headers['authorization'], 'Bearer access');
      if (request.url.queryParameters['offset'] == '0') {
        return http.Response(
          '{"items":[{"id":"p1","name":"Road trip","tracks":{"total":2},"owner":{"display_name":"Me"}}],"next":"https://api.spotify.com/v1/me/playlists?limit=50&offset=50"}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        '{"items":[{"id":"p2","name":"Second"}],"next":null}',
        200,
      );
    });
    final api = SpotifyApi(
      tokenStore: tokens,
      oauth: oauth,
      client: client,
    );

    final playlists = await api.getPlaylists();

    expect(playlists.map((playlist) => playlist.id), ['p1', 'p2']);
    expect(playlists.first.tracksTotal, 2);
  });

  test('Spotify liked sync is one-way, strict and idempotent', () async {
    final preferences = _MemoryPreferences();
    final metadata = SpotifyMetadataStore(preferences);
    final local = <Song>[
      _song('local-1', 'Track', 'Artist', 180),
      _song('local-ambiguous', 'Track', 'Artist', 181),
    ];
    final api = _FakeApi([
      SpotifyTrack(
        id: 'spotify-1',
        title: 'Track',
        artist: 'Artist',
        album: null,
        durationMs: 180000,
      ),
      SpotifyTrack(
        id: 'spotify-2',
        title: 'Missing',
        artist: 'Nobody',
        album: null,
        durationMs: 200000,
      ),
    ]);
    final favorites = _FakeFavorites({'existing'});
    final service = SpotifySyncService(
      api: api,
      metadata: metadata,
      library: _FakeLibrary(local),
      favorites: favorites,
    );

    final report = await service.syncLikedSongs();

    expect(report.totalTracks, 2);
    expect(report.matchedTracks, 1);
    expect(report.addedCount, 1);
    expect(report.unmatchedTracks.single.title, 'Missing');
    expect(report.readbackVerified, isTrue);
    expect(favorites.ids, contains('local-1'));
    expect(favorites.ids, contains('existing'));
    expect((await metadata.load()).lastLikedSync, isNotNull);
  });
}

class _FakeApi implements SpotifyLibraryApi {
  _FakeApi(this.liked);

  final List<SpotifyTrack> liked;

  @override
  Future<List<SpotifyPlaylist>> getPlaylists({
    void Function(int loaded)? onProgress,
    SpotifyCancellation? cancellation,
  }) async => const [];

  @override
  Future<List<SpotifyTrack>> getPlaylistTracks(
    String playlistId, {
    void Function(int loaded)? onProgress,
    SpotifyCancellation? cancellation,
  }) async => const [];

  @override
  Future<List<SpotifyTrack>> getLikedSongs({
    void Function(int loaded)? onProgress,
    SpotifyCancellation? cancellation,
  }) async => liked;
}

class _FakeLibrary implements SpotifyLocalLibrary {
  _FakeLibrary(this.songs);
  final List<Song> songs;

  @override
  Future<List<Song>> allSongs() async => songs;
}

class _FakeFavorites implements SpotifyFavoritesSink {
  _FakeFavorites(Iterable<String> ids) : ids = {...ids};
  final Set<String> ids;

  @override
  Future<void> addFavorite(String songId) async => ids.add(songId);

  @override
  Future<List<Song>> readFavorites() async => [
        for (final id in ids)
          _song(id, 'Saved', 'Artist', 1),
      ];

  @override
  Future<bool> isFavorite(String songId) async => ids.contains(songId);
}
