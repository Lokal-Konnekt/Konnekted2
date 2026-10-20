import 'dart:async';

import 'package:flick/features/discovery/discovery_http.dart';
import 'package:flick/features/discovery/discovery_models.dart';
import 'package:flick/features/discovery/discovery_playback.dart';
import 'package:flick/features/discovery/discovery_registry.dart';
import 'package:flick/features/discovery/discovery_settings.dart';
import 'package:flick/features/discovery/discovery_sources.dart';
import 'package:flick/features/discovery/lastfm_discovery.dart';
import 'package:flick/features/discovery/recommendation_match.dart';
import 'package:flick/features/discovery/youtube_audio.dart';
import 'package:flick/features/discovery/youtube_music_account.dart';
import 'package:flick/features/discovery/youtube_music_store.dart';
import 'package:flick/models/song.dart';
import 'package:flick/providers/lastfm_provider.dart';
import 'package:flick/services/player_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Home's Discovery tab, with opt-in provider-native YouTube Music shelves.

enum KonnektedDiscoverySource { lastfm, youtube, spotify }

final konnektedLastfmAccountProvider = FutureProvider.autoDispose<String?>((
  ref,
) async {
  final session = await ref.watch(lastFmSessionProvider.future);
  final name = session?.username.trim() ?? '';
  return name.isEmpty ? null : name;
});

final konnektedLastfmCallProvider = Provider<LastfmCall>((ref) {
  final client = ref.watch(lastFmApiClientProvider);
  return (method, params) => client.get({'method': method, ...params});
});

final konnektedYoutubeMusicStoreProvider = Provider<YoutubeMusicSessionStore>(
  (ref) => YoutubeMusicSessionStore(),
);

final konnektedYoutubeMusicSessionProvider =
    AsyncNotifierProvider<KonnektedYoutubeMusicNotifier, YoutubeMusicSession?>(
      KonnektedYoutubeMusicNotifier.new,
    );

class KonnektedYoutubeMusicNotifier extends AsyncNotifier<YoutubeMusicSession?> {
  @override
  Future<YoutubeMusicSession?> build() =>
      ref.read(konnektedYoutubeMusicStoreProvider).read();

  Future<void> save(YoutubeMusicSession session) async {
    await ref.read(konnektedYoutubeMusicStoreProvider).write(session);
    forgetYoutubeMusicAccount();
    state = AsyncData(session);
  }

  Future<void> rotated(YoutubeMusicSession session) async {
    // Do not let an in-flight request resurrect a session after sign-out.
    if (state.valueOrNull == null) return;
    state = AsyncData(session);
    await ref.read(konnektedYoutubeMusicStoreProvider).write(session);
  }

  Future<void> signOut() async {
    await ref.read(konnektedYoutubeMusicStoreProvider).clear();
    forgetYoutubeMusicAccount();
    state = const AsyncData(null);
  }
}

final konnektedYoutubeMusicAccountProvider = Provider<YoutubeMusicAccount?>((ref) {
  final session = ref.watch(konnektedYoutubeMusicSessionProvider).valueOrNull;
  if (session == null || !session.signedIn) return null;
  final client = http.Client();
  ref.onDispose(client.close);
  return YoutubeMusicAccount(
    client,
    session,
    onSessionChanged: (updated) {
      unawaited(ref.read(konnektedYoutubeMusicSessionProvider.notifier).rotated(updated));
    },
  );
});

class KonnektedDiscoveryState {
  const KonnektedDiscoveryState({
    this.data,
    this.loading = false,
    this.error,
    this.connected = true,
    this.source = KonnektedDiscoverySource.lastfm,
  });

  /// Shelves remain visible when a refresh fails.
  final LokalDiscovery? data;
  final bool loading;
  final String? error;
  final bool connected;
  final KonnektedDiscoverySource source;
}

class KonnektedDiscoveryNotifier extends Notifier<KonnektedDiscoveryState> {
  var _page = 0;
  var _generation = 0;
  var _sourceLoaded = false;
  String? _account;

  static const _sourceKey = 'lokal_discovery_source';

  @override
  KonnektedDiscoveryState build() => const KonnektedDiscoveryState();

  Future<void> setSource(KonnektedDiscoverySource source) async {
    if (state.source == source && _sourceLoaded) return;
    ++_generation;
    _page = 0;
    _account = null;
    _sourceLoaded = true;
    state = KonnektedDiscoveryState(source: source, connected: true);
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_sourceKey, source.name);
    } catch (_) {
      // The in-memory selection remains usable if persistence fails.
    }
    await load();
  }

  Future<void> _restoreSource() async {
    if (_sourceLoaded) return;
    _sourceLoaded = true;
    try {
      final preferences = await SharedPreferences.getInstance();
      final value = preferences.getString(_sourceKey);
      final saved = KonnektedDiscoverySource.values
          .where((source) => source.name == value)
          .firstOrNull;
      if (saved != null) {
        state = KonnektedDiscoveryState(source: saved);
      }
    } catch (_) {
      // Last.fm remains the default.
    }
  }

  /// Loads the selected provider. A refresh rotates between provider picks.
  Future<void> load({bool refresh = false}) async {
    if (!refresh && (state.data != null || state.loading)) return;
    await _restoreSource();
    final source = state.source;
    if (!refresh && (state.data != null || state.loading)) return;
    final generation = ++_generation;
    state = KonnektedDiscoveryState(
      data: state.data,
      loading: true,
      connected: state.connected,
      source: source,
    );

    if (source == KonnektedDiscoverySource.spotify) {
      state = const KonnektedDiscoveryState(
        connected: false,
        error: 'Spotify Discovery is coming soon.',
        source: KonnektedDiscoverySource.spotify,
      );
      return;
    }

    if (source == KonnektedDiscoverySource.youtube) {
      YoutubeMusicSession? session;
      try {
        session = await ref.read(konnektedYoutubeMusicSessionProvider.future);
      } catch (_) {
        session = null;
      }
      if (generation != _generation) return;
      if (session == null || !session.signedIn) {
        _account = null;
        _page = 0;
        state = const KonnektedDiscoveryState(
          connected: false,
          source: KonnektedDiscoverySource.youtube,
        );
        return;
      }
      final account = ref.read(konnektedYoutubeMusicAccountProvider);
      if (account == null) {
        state = const KonnektedDiscoveryState(
          connected: false,
          source: KonnektedDiscoverySource.youtube,
        );
        return;
      }
      final accountKey = 'youtube:' + session.accountKey;
      final previous = accountKey == _account ? state.data : null;
      if (accountKey != _account) _page = 0;
      _account = accountKey;
      if (refresh && previous != null) _page++;
      try {
        final result = await loadYoutubeMusicDiscovery(
          account,
          page: _page,
          force: refresh,
        );
        if (generation != _generation) return;
        state = KonnektedDiscoveryState(
          data: result.keeping(previous),
          source: source,
        );
      } on YoutubeMusicSignedOut catch (error) {
        if (generation != _generation) return;
        await ref.read(konnektedYoutubeMusicSessionProvider.notifier).signOut();
        state = KonnektedDiscoveryState(
          data: previous,
          error: error.message,
          connected: false,
          source: source,
        );
      } catch (error) {
        if (generation != _generation) return;
        state = KonnektedDiscoveryState(
          data: previous,
          error: error is LokalDiscoveryFailure
              ? error.message
              : 'YouTube Music couldn’t be reached. Check your connection and try again.',
          source: source,
        );
      }
      return;
    }

    String? account;
    try {
      account = await ref.read(konnektedLastfmAccountProvider.future);
    } catch (_) {
      account = null;
    }
    if (generation != _generation) return;
    if (account == null) {
      _account = null;
      _page = 0;
      state = const KonnektedDiscoveryState(
        connected: false,
        source: KonnektedDiscoverySource.lastfm,
      );
      return;
    }
    final accountKey = 'lastfm:' + account;
    final previous = accountKey == _account ? state.data : null;
    if (accountKey != _account) _page = 0;
    _account = accountKey;
    if (refresh && previous != null) _page++;
    try {
      final result = await loadLastfmDiscovery(
        username: account,
        call: ref.read(konnektedLastfmCallProvider),
        page: _page,
      );
      if (generation != _generation) return;
      state = KonnektedDiscoveryState(
        data: result.keeping(previous),
        source: KonnektedDiscoverySource.lastfm,
      );
    } catch (error) {
      if (generation != _generation) return;
      state = KonnektedDiscoveryState(
        data: previous,
        error: error is LokalDiscoveryFailure
            ? error.message
            : 'Last.fm couldn’t be reached. Check your connection and try again.',
        source: KonnektedDiscoverySource.lastfm,
      );
    }
  }
}

final konnektedDiscoveryProvider =
    NotifierProvider<KonnektedDiscoveryNotifier, KonnektedDiscoveryState>(
      KonnektedDiscoveryNotifier.new,
    );

RecommendationCandidate discoveryCandidate(LokalDiscoveryTrack track) =>
    RecommendationCandidate(
      title: track.title,
      artist: track.artist,
      album: track.album,
      duration: track.duration,
    );

RecommendationCandidate _songCandidate(Song song) => RecommendationCandidate(
  title: song.title,
  artist: song.artist,
  album: song.album,
  duration: song.duration > Duration.zero ? song.duration : null,
);

/// Your library, looked up by title, so matching a shelf of picks doesn't
/// compare each one against every song you own.
class KonnektedLibraryIndex {
  KonnektedLibraryIndex(this.songs) {
    for (final song in songs) {
      final keys = <String>{
        for (final title in recommendationTitles(song.title)) titleKey(title),
      };
      // "Artist - Title" names: the title after the artist, too.
      final parts = song.title.split(RegExp(r'\s+[-–—|]\s+'));
      if (parts.length > 1) {
        keys
          ..add(titleKey(parts.skip(1).join(' - ')))
          ..add(titleKey(parts.last));
      }
      for (final key in keys) {
        if (key.isNotEmpty) _byTitle.putIfAbsent(key, () => []).add(song);
      }
    }
  }

  final List<Song> songs;
  final _byTitle = <String, List<Song>>{};

  static KonnektedLibraryIndex? _last;

  /// The index for [songs], reused while the library is the same list.
  static KonnektedLibraryIndex of(List<Song> songs) {
    final last = _last;
    if (last != null && identical(last.songs, songs)) return last;
    return _last = KonnektedLibraryIndex(songs);
  }

  /// Your copy of [track], if you have it.
  Song? match(LokalDiscoveryTrack track) {
    final candidate = discoveryCandidate(track);
    final nearby = <Song>{
      for (final title in recommendationTitles(track.title))
        ...?_byTitle[titleKey(title)],
    };
    if (nearby.isEmpty) return null;
    return recommendationMatch(candidate, nearby, _songCandidate);
  }

  /// Your copies of [tracks], in order, each once.
  List<Song> matchAll(Iterable<LokalDiscoveryTrack> tracks) {
    final seen = <String>{};
    return [
      for (final track in tracks)
        if (match(track) case final song? when seen.add(song.id)) song,
    ];
  }

  /// Your songs from [album] by [artist], in disc and track order.
  List<Song> album(String album, String artist) {
    final title = recommendationKey(album);
    final by = recommendationKey(mainArtist(artist));
    if (title.isEmpty) return const [];
    final found = songs.where((song) {
      if (recommendationKey(song.album) != title) return false;
      return recommendationKey(mainArtist(song.albumArtist ?? song.artist)) ==
              by ||
          recommendationKey(mainArtist(song.artist)) == by ||
          recommendationKey(leadArtist(song.artist)) == by;
    }).toList();
    found.sort((a, b) {
      final disc = (a.discNumber ?? 1).compareTo(b.discNumber ?? 1);
      return disc != 0
          ? disc
          : (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0);
    });
    return found;
  }

  /// Your songs by [artist].
  List<Song> artist(String artist) {
    final by = recommendationKey(mainArtist(artist));
    if (by.isEmpty) return const [];
    return songs
        .where(
          (song) =>
              recommendationKey(mainArtist(song.artist)) == by ||
              recommendationKey(leadArtist(song.artist)) == by,
        )
        .toList();
  }
}

/// A place a song you don't own can be played from.
class _PlaybackSource {
  const _PlaybackSource(this.name, this.search, this.resolve);

  final String name;
  final Future<List<DiscoveryTrack>> Function(String query) search;
  final Future<ResolvedDiscoveryAudio> Function(DiscoveryTrack track) resolve;
}

/// Finds [track] somewhere to play it and downloads it, as desktop does for
/// songs you don't own: YouTube Music first (desktop's default order), then
/// your add-ons. Null when none has it. [onStatus] hears what's happening.
Future<Song?> findDiscoverySong(
  LokalDiscoveryTrack track, {
  void Function(String status)? onStatus,
  DiscoverySettingsStore? store,
  http.Client? client,
}) async {
  var settings = const DiscoverySettings();
  try {
    settings = await (store ?? DiscoverySettingsStore()).load();
  } catch (_) {
    // Unreadable add-on settings still leave YouTube Music.
  }
  final owned = client == null;
  final transport = client ?? http.Client();
  try {
    final web = DiscoveryHttp(transport);
    final registry = DiscoverySourceRegistry(web, settings);
    final youtube = YoutubeAudio(web);
    if (track.videoId case final videoId?) {
      onStatus?.call('Getting ${track.title} directly from YouTube Music…');
      final audio = await youtube.resolve(videoId);
      final direct = DiscoveryTrack(
        id: videoId,
        title: track.title,
        artist: track.artist,
        album: track.album,
        duration: track.duration,
        source: DiscoverySource.youtubeMusic,
        sourceUrl: Uri.tryParse(track.url),
      );
      return await DiscoveryPlaybackCache(
        http: web,
        protectedPaths: () {
          final player = PlayerService();
          return {
            if (player.currentSongNotifier.value?.filePath case final String path)
              path,
            ...player.queue.map((s) => s.filePath).whereType<String>(),
            ...player.upNext.map((s) => s.filePath).whereType<String>(),
          };
        },
      ).prepare(direct, audio);
    }
    final sources = [
      _PlaybackSource(
        'YouTube Music',
        YoutubeMusicCatalog(web).search,
        (found) => youtube.resolve(found.id),
      ),
      for (final addon in registry.addons)
        _PlaybackSource(addon.displayName, addon.search, registry.resolve),
    ];
    final candidate = discoveryCandidate(track);
    final queries = recommendationQueries(candidate).take(3).toList();
    DiscoveryException? failure;
    for (final source in sources) {
      for (final query in queries) {
        List<DiscoveryTrack> results;
        try {
          results = await source.search(query);
        } catch (_) {
          continue;
        }
        final found = recommendationMatch(
          candidate,
          results,
          (result) => RecommendationCandidate(
            title: result.title,
            artist: result.artist,
            album: result.album,
            duration: result.duration,
          ),
        );
        if (found == null) continue;
        onStatus?.call('Getting ${track.title} from ${source.name}…');
        try {
          final audio = await source.resolve(found);
          return await DiscoveryPlaybackCache(
            http: web,
            protectedPaths: () {
              final player = PlayerService();
              return {
                if (player.currentSongNotifier.value?.filePath
                    case final String path)
                  path,
                ...player.queue.map((s) => s.filePath).whereType<String>(),
                ...player.upNext.map((s) => s.filePath).whereType<String>(),
              };
            },
          ).prepare(found, audio);
        } on DiscoveryException catch (error) {
          // This source found it but couldn't play it: try the next one.
          failure = error;
          break;
        }
      }
    }
    if (failure != null) throw failure;
    return null;
  } finally {
    if (owned) transport.close();
  }
}
