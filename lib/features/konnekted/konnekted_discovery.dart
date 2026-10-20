import 'dart:async';

import 'package:flick/features/discovery/discovery_artwork.dart'
    show discoveryImageUrl;
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
import 'package:flick/features/spotiflac/spotiflac_packages.dart';
import 'package:flick/features/spotiflac/spotiflac_runtime.dart';
import 'package:flick/features/spotiflac/spotiflac_service.dart';
import 'package:flick/models/song.dart';
import 'package:flick/providers/lastfm_provider.dart';
import 'package:flick/services/player_service.dart';
import 'package:flick/services/queue_pre_resolver.dart';
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

class KonnektedYoutubeMusicNotifier
    extends AsyncNotifier<YoutubeMusicSession?> {
  @override
  Future<YoutubeMusicSession?> build() =>
      ref.read(konnektedYoutubeMusicStoreProvider).read();

  Future<void> save(YoutubeMusicSession session) async {
    await ref.read(konnektedYoutubeMusicStoreProvider).write(session);
    forgetYoutubeMusicAccount();
    state = AsyncData(session);
  }

  Future<void> rotated(YoutubeMusicSession session) async {
    // Keep the account provider stable while its own client is in flight.
    // The account object has already accepted these rotated cookies; persist
    // them without publishing a new AsyncData value that would dispose it.
    if (state.value == null) return;
    await ref.read(konnektedYoutubeMusicStoreProvider).write(session);
  }

  Future<void> signOut() async {
    await ref.read(konnektedYoutubeMusicStoreProvider).clear();
    forgetYoutubeMusicAccount();
    state = const AsyncData(null);
    ref.read(konnektedDiscoveryProvider.notifier).clearYoutubeMusicAccount();
  }
}

final konnektedYoutubeMusicAccountProvider = Provider<YoutubeMusicAccount?>((
  ref,
) {
  final session = ref.watch(konnektedYoutubeMusicSessionProvider).value;
  if (session == null || !session.signedIn) return null;
  final client = http.Client();
  ref.onDispose(client.close);
  return YoutubeMusicAccount(
    client,
    session,
    onSessionChanged: (updated) {
      unawaited(
        ref
            .read(konnektedYoutubeMusicSessionProvider.notifier)
            .rotated(updated),
      );
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
  Future<void>? _sourceRestore;
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

  Future<void> _restoreSource() {
    if (_sourceLoaded) return Future<void>.value();
    return _sourceRestore ??= _restoreSavedSource();
  }

  Future<void> _restoreSavedSource() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final value = preferences.getString(_sourceKey);
      final saved = KonnektedDiscoverySource.values
          .where((source) => source.name == value)
          .firstOrNull;
      // A manual source change may have happened while preferences loaded.
      if (!_sourceLoaded && saved != null) {
        state = KonnektedDiscoveryState(source: saved);
      }
    } catch (_) {
      // Last.fm remains the default.
    } finally {
      _sourceLoaded = true;
    }
  }

  /// Clears displayed account data immediately when the user signs out.
  void clearYoutubeMusicAccount() {
    if (state.source != KonnektedDiscoverySource.youtube) return;
    ++_generation;
    _page = 0;
    _account = null;
    state = const KonnektedDiscoveryState(
      connected: false,
      source: KonnektedDiscoverySource.youtube,
    );
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
          error: error is LokalDiscoveryFailure ? error.message : 'YouTube Music couldn’t be reached. Check your connection and try again.',
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
        error: error is LokalDiscoveryFailure ? error.message : 'Last.fm couldn’t be reached. Check your connection and try again.',
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
/// A song a source found, with its cover when the source has one.
class OnlineResult {
  const OnlineResult(this.track, {String? artwork}) : _artwork = artwork;

  final DiscoveryTrack track;
  final String? _artwork;

  String? get artwork => _artwork ?? track.artwork;
}

/// A place to find songs you don't have: YouTube Music or one of your
/// add-ons, as desktop's Search page offers them.
class OnlineSource {
  const OnlineSource({
    required this.id,
    required this.name,
    required this.results,
    required this.play,
    this.addon = false,
  });

  final String id;
  final String name;
  final bool addon;

  /// Songs matching a query, with covers.
  final Future<List<OnlineResult>> Function(String query) results;

  /// Gets a track ready to play (downloaded and checked).
  final Future<Song> Function(DiscoveryTrack track) play;

  Future<List<DiscoveryTrack>> search(String query) async => [
    for (final result in await results(query)) result.track,
  ];
}

typedef _PlaybackSource = OnlineSource;

/// Your SpotiFLAC add-ons that can play songs right now, as playback sources.
Future<List<_PlaybackSource>> _spotiflacSources(
  SpotiflacService service,
  DiscoveryPlaybackCache Function() cache,
  void Function(String status)? onStatus, {
  Future<void>? cancel,
}) async {
  final List<SpotiflacAddon> addons;
  final SpotiflacPackages packages;
  try {
    packages = await service.packages;
    addons = await service.playable();
  } catch (_) {
    return const []; // Add-ons unavailable: the other sources still play.
  }
  return [
    for (final addon in addons)
      OnlineSource(
        id: 'a-${addon.key}',
        name: addon.displayName,
        addon: true,
        results: (query) async => [
          for (final song in await packages.search(addon.key, query))
            OnlineResult(
              DiscoveryTrack(
                id: song.id,
                title: song.title,
                artist: song.artist,
                album: song.album,
                duration: song.duration,
                source: DiscoverySource.spotiflac,
                addonId: addon.key,
                sourceName: addon.displayName,
                artwork: song.thumbnail,
              ),
            ),
        ],
        play: (found) async {
          final progress = SpotiflacProgressText(
            found.title,
            addon.displayName,
          );
          var finished = false;
          final SpotiflacDownload download;
          try {
            download = await packages.download(
              addon.key,
              found.id,
              onProgress: ({percent, message}) {
                // A runtime winding down after a failure or a cancel says
                // nothing more: no stale "downloading" after the error.
                if (finished) return;
                final text = progress.update(
                  percent: percent,
                  message: message,
                );
                if (text != null) onStatus?.call(text);
              },
              cancel: cancel,
            );
          } on SpotiflacPackageError catch (error) {
            throw DiscoveryException(error.message);
          } on SpotiflacRuntimeError catch (error) {
            throw DiscoveryException(error.message);
          } on DiscoveryException {
            rethrow;
          } catch (_) {
            // Network drops, stalls and file errors: this source failed, so
            // the next one can be tried.
            throw DiscoveryException(
              '${addon.displayName} couldn’t download ${found.title}. '
              'Check your connection and try again.',
            );
          } finally {
            finished = true;
          }
          try {
            return await cache().adopt(found, download.file);
          } finally {
            await download.cleanup();
          }
        },
      ),
  ];
}

/// One line of an add-on's download progress, "Getting Song from Qobuz…
/// 42%", said only when it changes: percentages come several times a
/// second, and the add-on's own status words ("Qobuz loading…") replace
/// the percentage instead of being repeated after it.
class SpotiflacProgressText {
  SpotiflacProgressText(this.title, this.source);

  final String title;
  final String source;
  String? _said;
  int? _percent;

  /// The line to show now, or null when it says what was said already.
  String? update({double? percent, String? message}) {
    if (percent != null && percent.isFinite && percent > 0) {
      _percent = percent.clamp(0, 100).round();
    }
    final words = message?.trim() ?? '';
    final prefix = 'Getting $title from $source…';
    final percentText = _percent == null ? '' : ' $_percent%';
    final RegExp numbered = RegExp(r'\d+(\.\d+)?\s*%');
    final text = words.isEmpty
        ? (_percent == null ? prefix : '$prefix$percentText')
        : numbered.hasMatch(words)
        ? '$prefix ${words.replaceAll(RegExp(r'\s+'), ' ')}'
        : '$prefix ${words.replaceAll(RegExp(r'\s+'), ' ')}$percentText';
    if (text == _said) return null;
    _said = text;
    return text;
  }
}

/// Where found songs are kept while they play; never deletes what's queued.
DiscoveryPlaybackCache _playbackCache(
  DiscoveryHttp web,
  Set<String> Function()? additionalProtectedPaths,
) => DiscoveryPlaybackCache(
  http: web,
  protectedPaths: () {
    final player = PlayerService();
    return {
      if (player.currentSongNotifier.value?.filePath case final String path)
        path,
      ...player.queue.map((s) => s.filePath).whereType<String>(),
      ...player.upNext.map((s) => s.filePath).whereType<String>(),
      ...(additionalProtectedPaths?.call() ?? const <String>{}),
    };
  },
);

/// YouTube Music, then your web add-ons, then your SpotiFLAC add-ons:
/// desktop's order.
Future<List<OnlineSource>> _playbackSources(
  DiscoveryHttp web,
  DiscoverySettings settings,
  DiscoveryPlaybackCache Function() cache,
  void Function(String status)? onStatus,
  SpotiflacService spotiflac, {
  Future<void>? cancel,
}) async {
  final registry = DiscoverySourceRegistry(web, settings);
  final youtube = YoutubeAudio(web);
  return [
    OnlineSource(
      id: 'yt',
      name: 'YouTube Music',
      results: (query) async => [
        for (final track in await YoutubeMusicCatalog(web).search(query))
          OnlineResult(track),
      ],
      play: (found) async => cache().prepare(
        found,
        await youtube.resolve(found.id),
        cancel: cancel,
      ),
    ),
    for (final addon in registry.addons)
      OnlineSource(
        id: 'w-${addon.displayName}',
        name: addon.displayName,
        addon: true,
        results: (query) async => [
          for (final track in await addon.search(query)) OnlineResult(track),
        ],
        play: (found) async => cache().prepare(
          found,
          await registry.resolve(found),
          cancel: cancel,
        ),
      ),
    ...await _spotiflacSources(spotiflac, cache, onStatus, cancel: cancel),
  ];
}

/// The sources Search offers for songs you don't have. [onStatus] hears
/// download progress; [client] stays open until the caller closes it.
Future<List<OnlineSource>> onlineSources(
  http.Client client, {
  void Function(String status)? onStatus,
  DiscoverySettingsStore? store,
  SpotiflacService? spotiflac,
}) async {
  var settings = const DiscoverySettings();
  try {
    settings = await (store ?? DiscoverySettingsStore()).load();
  } catch (_) {
    // Unreadable add-on settings still leave YouTube Music.
  }
  final web = DiscoveryHttp(client);
  return _playbackSources(
    web,
    settings,
    () => _playbackCache(web, null),
    onStatus,
    spotiflac ?? SpotiflacService.instance,
  );
}

/// Finds [track] somewhere to play it and downloads it, as desktop does for
/// songs you don't own: YouTube Music first (desktop's default order), then
/// your add-ons. Null when none has it. [onStatus] hears what's happening;
/// once [cancel] completes the search stops and an add-on's download with it.
Future<Song?> findDiscoverySong(
  LokalDiscoveryTrack track, {
  void Function(String status)? onStatus,
  DiscoverySettingsStore? store,
  http.Client? client,
  Set<String> Function()? additionalProtectedPaths,
  SpotiflacService? spotiflac,
  Future<void>? cancel,
}) async {
  var cancelled = false;
  if (cancel != null) unawaited(cancel.then((_) => cancelled = true));
  void check() {
    if (cancelled) throw const DiscoveryException('Request cancelled.');
  }

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
    final youtube = YoutubeAudio(web);
    if (track.videoId case final videoId?) {
      onStatus?.call('Getting ${track.title} directly from YouTube Music…');
      final audio = await youtube.resolve(videoId);
      check();
      final direct = DiscoveryTrack(
        id: videoId,
        title: track.title,
        artist: track.artist,
        album: track.album,
        duration: track.duration,
        source: DiscoverySource.youtubeMusic,
        sourceUrl: Uri.tryParse(track.url),
        artwork: _artworkOf(track),
      );
      return await _playbackCache(
        web,
        additionalProtectedPaths,
      ).prepare(direct, audio, cancel: cancel);
    }
    DiscoveryPlaybackCache cache() =>
        _playbackCache(web, additionalProtectedPaths);
    final sources = await _playbackSources(
      web,
      settings,
      cache,
      onStatus,
      spotiflac ?? SpotiflacService.instance,
      cancel: cancel,
    );
    final candidate = discoveryCandidate(track);
    final queries = recommendationQueries(candidate).take(3).toList();
    DiscoveryException? failure;
    for (final source in sources) {
      for (final query in queries) {
        check();
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
        check();
        onStatus?.call('Getting ${track.title} from ${source.name}…');
        try {
          return await source.play(found.withArtwork(_artworkOf(track)));
        } catch (error) {
          check();
          // This source found it but couldn't play it: try the next one.
          failure = error is DiscoveryException
              ? error
              : DiscoveryException(
                  '${source.name} couldn’t get ${track.title} ready.',
                );
          onStatus?.call(
            'Couldn’t get ${track.title} from ${source.name}. '
            'Trying elsewhere…',
          );
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

/// [track]'s cover address, or null when it has none worth fetching.
String? _artworkOf(LokalDiscoveryTrack track) {
  final url = discoveryImageUrl(track.artworkUrl);
  return url.isEmpty ? null : url;
}

/// A queue placeholder for [track], a song you don't own: found on YouTube
/// Music or your add-ons and downloaded once it's coming up (QueuePreResolver).
Song discoveryPendingSong(LokalDiscoveryTrack track) {
  final resolver = QueuePreResolver.shared;
  return resolver.pending(
    key: track.key,
    title: track.title,
    artist: track.artist,
    album: track.album,
    duration: track.duration,
    artwork: _artworkOf(track),
    resolve: ({onStatus, cancel}) => findDiscoverySong(
      track,
      onStatus: onStatus,
      cancel: cancel,
      additionalProtectedPaths: () => resolver.resolvedPaths,
    ),
  );
}
