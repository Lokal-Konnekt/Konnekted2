import 'package:flick/services/link/library_song_identity.dart';

import 'dart:async';

import 'package:flick/data/repositories/recently_played_repository.dart';
import 'package:flick/data/repositories/song_repository.dart';
import 'package:flick/features/konnekted/lokal_home_greeting.dart';
import 'package:flick/features/konnekted/lokal_mixes.dart';
import 'package:flick/models/song.dart';
import 'package:flick/providers/favorites_provider.dart';
import 'package:flick/providers/songs_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Repository boundaries are overridable; rendering the home never requires a
/// platform player in a widget test.
final konnektedHistoryRepositoryProvider = Provider<RecentlyPlayedRepository>(
  (ref) => RecentlyPlayedRepository(),
);

// Home's providers are kept for the session (no autoDispose): the shell
// rebuilds each tab on switch, and Home's shelves should be there at once
// when you come back rather than pop in empty.

// History merge writes arrive in bursts. Keep the first update responsive,
// then coalesce the rest instead of queuing a DB read for every imported play.
Stream<void> _homeHistoryChanges(Ref ref, RecentlyPlayedRepository repository) {
  final changes = StreamController<void>();
  Timer? timer;
  var pending = false;
  void settle() {
    timer = null;
    if (!pending || changes.isClosed) return;
    pending = false;
    changes.add(null);
    timer = Timer(const Duration(milliseconds: 500), settle);
  }

  final subscription = repository.watchHistory().listen((_) {
    if (timer != null) {
      pending = true;
    } else {
      changes.add(null);
      timer = Timer(const Duration(milliseconds: 500), settle);
    }
  }, onError: changes.addError);
  changes.add(null);
  ref.onDispose(() {
    timer?.cancel();
    unawaited(subscription.cancel());
    unawaited(changes.close());
  });
  return changes.stream;
}

final konnektedRecentSongsProvider = StreamProvider<List<Song>>((ref) {
  final repository = ref.watch(konnektedHistoryRepositoryProvider);
  return _homeHistoryChanges(ref, repository).asyncMap((_) async {
    final entries = await repository.getRecentHistory(limit: 40);
    final seen = <String>{};
    return entries
        .map((entry) => entry.song)
        .where((song) => seen.add(song.id))
        .take(12)
        .toList(growable: false);
  });
});

/// Home's personal greeting line, from the latest plays (desktop's rules).
final konnektedGreetingProvider = StreamProvider<LokalHomeMessages>((ref) {
  final repository = ref.watch(konnektedHistoryRepositoryProvider);
  return _homeHistoryChanges(ref, repository).asyncMap(
    (_) async =>
        lokalHomeMessages(await repository.getRecentHistory(limit: 40)),
  );
});

// Riverpod's whenData drops retained data when its input is AsyncLoading.
// A live library refresh must not turn established shelves into placeholders.
AsyncValue<R> _homeData<T, R>(AsyncValue<T> source, R Function(T) map) {
  if (source.hasValue) return AsyncData(map(source.requireValue));
  return source.when(
    data: (value) => AsyncData(map(value)),
    loading: () => const AsyncLoading(),
    error: (error, stack) => AsyncError(error, stack),
  );
}

final konnektedFavoritesProvider = Provider<AsyncValue<List<Song>>>(
  (ref) =>
      _homeData(ref.watch(favoritesProvider), (state) => state.favoriteSongs),
);

final konnektedLibraryProvider = Provider<AsyncValue<List<Song>>>(
  (ref) => _homeData(
    ref.watch(songsProvider),
    (state) => preferLocalLibrarySongs(state.songs),
  ),
);

final konnektedRecentlyAddedProvider = Provider<AsyncValue<List<Song>>>(
  (ref) => _homeData(
    ref.watch(konnektedLibraryProvider),
    (songs) => _newestFirst(songs).take(12).toList(growable: false),
  ),
);

({String key, List<LokalMix> mixes})? _mixes;

/// Forgets the cached mixes (tests).
@visibleForTesting
void resetKonnektedMixes() => _mixes = null;

/// Your Mixes, by desktop's rules (`lokal_mixes.dart`). Like desktop, they
/// are built once and kept for the day rather than reshuffled on every play;
/// they are rebuilt when the day turns or the library or favourites change
/// size.
class KonnektedMixRefresh extends Notifier<int> {
  @override
  int build() => 0;
  void refresh() => state++;
}

final konnektedMixRefreshProvider = NotifierProvider<KonnektedMixRefresh, int>(
  KonnektedMixRefresh.new,
);

final konnektedMixesProvider = FutureProvider<List<LokalMix>>((ref) async {
  final library = ref.watch(konnektedLibraryProvider.select((s) => s.value));
  final liked =
      ref.watch(konnektedFavoritesProvider.select((s) => s.value)) ??
      const <Song>[];
  // Still loading: stay loading rather than flash an empty Home.
  if (library == null) return Completer<List<LokalMix>>().future;
  if (library.isEmpty) return const [];
  final refresh = ref.watch(konnektedMixRefreshProvider);
  final now = DateTime.now();
  final key =
      '$refresh|${now.year}-${now.month}-${now.day}|${Object.hashAll(library.map((s) => Object.hash(s.id, s.artist, s.genre, s.album)))}|${Object.hashAll(liked.map((s) => s.id))}';
  final cached = _mixes;
  if (cached != null && cached.key == key) return cached.mixes;
  final history = ref.read(konnektedHistoryRepositoryProvider);
  final recent = await history.getRecentHistory(limit: 50);
  final counts = await history.getPlayCounts();
  final mixes = lokalMixes(
    library: library,
    liked: liked,
    history: [for (final entry in recent) entry.song],
    playCounts: counts,
    now: now,
    refreshSeed: refresh,
  );
  _mixes = (key: key, mixes: mixes);
  return mixes;
});

/// Made for you: two songs from each of the first six mixes, picked once
/// per run (desktop's rule).
final konnektedMadeForYouProvider =
    Provider<AsyncValue<List<LokalMadeForYouPick>>>(
      (ref) => _homeData(ref.watch(konnektedMixesProvider), lokalMadeForYou),
    );

/// Wraps one song as a Cover Flow entry: each cover is a song, not an
/// album, so a single tap plays it.
AlbumGroup konnektedSongCover(Song song) => AlbumGroup(
  key: 'song:${song.id}',
  albumName: song.title,
  albumArtist: song.artist,
  songs: [song],
);

/// Home's Cover Flow: Made for you, one cover per song. Tapping one plays it
/// with the whole shelf as the queue.
final konnektedCoverAlbumsProvider = Provider<AsyncValue<List<AlbumGroup>>>(
  (ref) => _homeData(ref.watch(konnektedMadeForYouProvider), (picks) {
    final seen = <String>{};
    return [
      for (final pick in picks)
        if (seen.add(pick.song.id)) konnektedSongCover(pick.song),
    ];
  }),
);

List<Song> _newestFirst(Iterable<Song> songs) =>
    List<Song>.of(songs)..sort((a, b) {
      final compared = (b.dateAdded ?? DateTime(1970)).compareTo(
        a.dateAdded ?? DateTime(1970),
      );
      return compared != 0 ? compared : a.title.compareTo(b.title);
    });
