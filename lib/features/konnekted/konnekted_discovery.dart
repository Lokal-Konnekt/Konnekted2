import 'dart:async';

import 'package:flick/features/discovery/discovery_http.dart';
import 'package:flick/features/discovery/discovery_models.dart';
import 'package:flick/features/discovery/discovery_playback.dart';
import 'package:flick/features/discovery/discovery_registry.dart';
import 'package:flick/features/discovery/discovery_settings.dart';
import 'package:flick/features/discovery/lastfm_discovery.dart';
import 'package:flick/features/discovery/recommendation_match.dart';
import 'package:flick/models/song.dart';
import 'package:flick/providers/lastfm_provider.dart';
import 'package:flick/services/player_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// Home's Discovery tab: Last.fm's shelves for your account, played from your
/// library when you have the song, otherwise from your add-ons.

/// The Last.fm account Discovery is for; null when Last.fm isn't connected.
final konnektedLastfmAccountProvider = FutureProvider.autoDispose<String?>((
  ref,
) async {
  final session = await ref.watch(lastFmSessionProvider.future);
  final name = session?.username.trim() ?? '';
  return name.isEmpty ? null : name;
});

/// How Discovery asks Last.fm; overridden in tests.
final konnektedLastfmCallProvider = Provider<LastfmCall>((ref) {
  final client = ref.watch(lastFmApiClientProvider);
  return (method, params) => client.get({'method': method, ...params});
});

class KonnektedDiscoveryState {
  const KonnektedDiscoveryState({
    this.data,
    this.loading = false,
    this.error,
    this.connected = true,
  });

  /// The shelves, kept while a refresh loads and when one fails.
  final LokalDiscovery? data;
  final bool loading;
  final String? error;

  /// False when there is no Last.fm account to ask about.
  final bool connected;
}

class KonnektedDiscoveryNotifier extends Notifier<KonnektedDiscoveryState> {
  var _page = 0;
  var _generation = 0;
  String? _account;

  @override
  KonnektedDiscoveryState build() => const KonnektedDiscoveryState();

  /// Loads the shelves the first time; [refresh] asks for new picks, as
  /// desktop's Refresh does.
  Future<void> load({bool refresh = false}) async {
    if (!refresh && (state.data != null || state.loading)) return;
    final generation = ++_generation;
    state = KonnektedDiscoveryState(
      data: state.data,
      loading: true,
      connected: state.connected,
    );
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
      state = const KonnektedDiscoveryState(connected: false);
      return;
    }
    // Another account's shelves never mix with these.
    final previous = account == _account ? state.data : null;
    if (account != _account) _page = 0;
    _account = account;
    if (refresh && previous != null) _page++;
    try {
      final result = await loadLastfmDiscovery(
        username: account,
        call: ref.read(konnektedLastfmCallProvider),
        page: _page,
      );
      if (generation != _generation) return;
      state = KonnektedDiscoveryState(data: result.keeping(previous));
    } catch (error) {
      if (generation != _generation) return;
      state = KonnektedDiscoveryState(
        data: previous,
        error: error is LokalDiscoveryFailure ? error.message : 'Last.fm couldn’t be reached. Check your connection and try again.',
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

/// Finds [track] on your add-ons and downloads it to play, like desktop's
/// fallback to its other sources. Null when no add-on has it (or none is
/// set up). [onStatus] hears what's happening.
Future<Song?> findDiscoverySongOnAddons(
  LokalDiscoveryTrack track, {
  void Function(String status)? onStatus,
  DiscoverySettingsStore? store,
  http.Client? client,
}) async {
  final settings = await (store ?? DiscoverySettingsStore()).load();
  final owned = client == null;
  final transport = client ?? http.Client();
  try {
    final web = DiscoveryHttp(transport);
    final registry = DiscoverySourceRegistry(web, settings);
    if (registry.addons.isEmpty) return null;
    final candidate = discoveryCandidate(track);
    for (final query in recommendationQueries(candidate).take(3)) {
      for (final addon in registry.addons) {
        List<DiscoveryTrack> results;
        try {
          results = await addon.search(query);
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
        onStatus?.call('Getting ${track.title} from ${addon.displayName}…');
        final audio = await registry.resolve(found);
        final cache = DiscoveryPlaybackCache(
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
        );
        return await cache.prepare(found, audio);
      }
    }
    return null;
  } finally {
    if (owned) transport.close();
  }
}
