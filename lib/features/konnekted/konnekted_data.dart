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

final konnektedRecentSongsProvider = StreamProvider.autoDispose<List<Song>>((
  ref,
) {
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
final konnektedGreetingProvider = StreamProvider.autoDispose<String>((ref) {
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

final konnektedFavoritesProvider = Provider.autoDispose<AsyncValue<List<Song>>>(
  (ref) =>
      ref.watch(favoritesProvider).whenData((state) => state.favoriteSongs),
);

final konnektedLibraryProvider = Provider.autoDispose<AsyncValue<List<Song>>>(
  (ref) => ref.watch(songsProvider).whenData((state) => state.songs),
);

final konnektedRecentlyAddedProvider =
    Provider.autoDispose<AsyncValue<List<Song>>>(
      (ref) => ref.watch(konnektedLibraryProvider).whenData((songs) {
        final sorted = List<Song>.of(songs)
          ..sort((a, b) {
            final compared = (b.dateAdded ?? DateTime(1970)).compareTo(
              a.dateAdded ?? DateTime(1970),
            );
            return compared != 0 ? compared : a.title.compareTo(b.title);
          });
        return sorted.take(12).toList(growable: false);
      }),
    );

({String key, List<LokalMix> mixes})? _mixes;

/// Forgets the cached mixes (tests).
@visibleForTesting
void resetKonnektedMixes() => _mixes = null;

/// Your Mixes, by desktop's rules (`lokal_mixes.dart`). Like desktop, they
/// are built once and kept for the day rather than reshuffled on every play;
/// they are rebuilt when the day turns or the library or favourites change
/// size.
final konnektedMixesProvider = FutureProvider.autoDispose<List<LokalMix>>((
  ref,
) async {
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
    Provider.autoDispose<AsyncValue<List<LokalMadeForYouPick>>>(
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

/// Marks a Cover Flow entry that is one of Your Mixes, not an album.
const konnektedMixKeyPrefix = 'lokal-mix:';

/// Albums for Home's Cover Flow: the ones played lately, or newest added.
final konnektedCoverAlbumsProvider = Provider.autoDispose
    .family<AsyncValue<List<AlbumGroup>>, KonnektedCoverShelf>((ref, shelf) {
      if (shelf == KonnektedCoverShelf.madeForYou) {
        // Your Mixes as covers; the key marks them for the collage art.
        return ref
            .watch(konnektedMixesProvider)
            .whenData(
              (mixes) => [
                for (final mix in mixes)
                  AlbumGroup(
                    key: '$konnektedMixKeyPrefix${mix.id}',
                    albumName: mix.title,
                    albumArtist: '${mix.tracks.length} songs',
                    songs: mix.tracks,
                  ),
              ],
            );
      }
      final library = ref.watch(konnektedLibraryProvider);
      return library.whenData((songs) {
        final albums = SongsState(
          songs: songs
              .where((song) => !song.isNetworkSource && !song.isExternal)
              .toList(),
          sortOption: SongSortOption.album,
        ).albumGroups;
        if (albums.isEmpty) return const <AlbumGroup>[];
        switch (shelf) {
          case KonnektedCoverShelf.madeForYou:
          case KonnektedCoverShelf.added:
            DateTime newest(AlbumGroup album) => album.songs
                .map((song) => song.dateAdded ?? DateTime(1970))
                .reduce((a, b) => a.isAfter(b) ? a : b);
            return (List<AlbumGroup>.of(albums)
                  ..sort((a, b) => newest(b).compareTo(newest(a))))
                .take(40)
                .toList(growable: false);
          case KonnektedCoverShelf.recent:
            final recent =
                ref.watch(konnektedRecentSongsProvider).value ?? const [];
            final byId = <String, AlbumGroup>{
              for (final album in albums)
                for (final song in album.songs) song.id: album,
            };
            final seen = <String>{};
            return [
              for (final song in recent)
                if (byId[song.id] case final album?)
                  if (seen.add(album.key)) album,
            ];
        }
      });
    });
