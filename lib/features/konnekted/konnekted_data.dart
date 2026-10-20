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

final konnektedRecentSongsProvider = StreamProvider<List<Song>>((ref) {
  final repository = ref.watch(konnektedHistoryRepositoryProvider);
  // Subscribe before the initial read so a play during startup is not lost.
  final changes = StreamController<void>();
  final subscription = repository.watchHistory().listen(
    changes.add,
    onError: changes.addError,
  );
  changes.add(null);
  ref.onDispose(() {
    unawaited(subscription.cancel());
    unawaited(changes.close());
  });
  return changes.stream.asyncMap((_) async {
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
final konnektedGreetingProvider = StreamProvider<String>((ref) {
  final repository = ref.watch(konnektedHistoryRepositoryProvider);
  final changes = StreamController<void>();
  final subscription = repository.watchHistory().listen(
    changes.add,
    onError: changes.addError,
  );
  changes.add(null);
  ref.onDispose(() {
    unawaited(subscription.cancel());
    unawaited(changes.close());
  });
  return changes.stream.asyncMap(
    (_) async =>
        lokalHomeGreeting(await repository.getRecentHistory(limit: 40)),
  );
});

final konnektedFavoritesProvider = Provider<AsyncValue<List<Song>>>(
  (ref) =>
      ref.watch(favoritesProvider).whenData((state) => state.favoriteSongs),
);

final konnektedLibraryProvider = Provider<AsyncValue<List<Song>>>(
  (ref) => ref.watch(songsProvider).whenData((state) => state.songs),
);

final konnektedRecentlyAddedProvider = Provider<AsyncValue<List<Song>>>(
  (ref) => ref
      .watch(konnektedLibraryProvider)
      .whenData(
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
final konnektedMixesProvider = FutureProvider<List<LokalMix>>((ref) async {
  final library = ref.watch(konnektedLibraryProvider.select((s) => s.value));
  final liked =
      ref.watch(konnektedFavoritesProvider.select((s) => s.value)) ??
      const <Song>[];
  // Still loading: stay loading rather than flash an empty Home.
  if (library == null) return Completer<List<LokalMix>>().future;
  if (library.isEmpty) return const [];
  final now = DateTime.now();
  final key =
      '${now.year}-${now.month}-${now.day}|${library.length}|${liked.length}';
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
  );
  _mixes = (key: key, mixes: mixes);
  return mixes;
});

/// Made for you: two songs from each of the first six mixes, picked once
/// per run (desktop's rule).
final konnektedMadeForYouProvider =
    Provider<AsyncValue<List<LokalMadeForYouPick>>>(
      (ref) => ref.watch(konnektedMixesProvider).whenData(lokalMadeForYou),
    );

/// The three Cover Flow shelves on Home.
enum KonnektedCoverShelf {
  recent('Recent'),
  madeForYou('Made for you'),
  added('New');

  const KonnektedCoverShelf(this.label);

  final String label;
}

/// How many songs Home's New Cover Flow shelf shows.
const konnektedCoverAddedLimit = 40;

/// Wraps one song as a Cover Flow entry: each cover is a song, not an
/// album, so a single tap plays it.
AlbumGroup konnektedSongCover(Song song) => AlbumGroup(
  key: 'song:${song.id}',
  albumName: song.title,
  albumArtist: song.artist,
  songs: [song],
);

/// Songs for Home's Cover Flow, one cover each: the ones played lately,
/// Made for you, or the newest added. Tapping one plays it with the whole
/// shelf as the queue.
final konnektedCoverAlbumsProvider =
    Provider.family<AsyncValue<List<AlbumGroup>>, KonnektedCoverShelf>((
      ref,
      shelf,
    ) {
      List<AlbumGroup> covers(Iterable<Song> songs) {
        final seen = <String>{};
        return [
          for (final song in songs)
            if (seen.add(song.id)) konnektedSongCover(song),
        ];
      }

      switch (shelf) {
        case KonnektedCoverShelf.recent:
          return ref.watch(konnektedRecentSongsProvider).whenData(covers);
        case KonnektedCoverShelf.madeForYou:
          return ref
              .watch(konnektedMadeForYouProvider)
              .whenData((picks) => covers(picks.map((pick) => pick.song)));
        case KonnektedCoverShelf.added:
          return ref
              .watch(konnektedLibraryProvider)
              .whenData(
                (songs) => covers(
                  _newestFirst(
                    songs.where(
                      (song) => !song.isNetworkSource && !song.isExternal,
                    ),
                  ).take(konnektedCoverAddedLimit),
                ),
              );
      }
    });

List<Song> _newestFirst(Iterable<Song> songs) =>
    List<Song>.of(songs)..sort((a, b) {
      final compared = (b.dateAdded ?? DateTime(1970)).compareTo(
        a.dateAdded ?? DateTime(1970),
      );
      return compared != 0 ? compared : a.title.compareTo(b.title);
    });
