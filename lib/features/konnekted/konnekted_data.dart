import 'dart:async';

import 'package:flick/data/repositories/recently_played_repository.dart';
import 'package:flick/data/repositories/song_repository.dart';
import 'package:flick/models/song.dart';
import 'package:flick/providers/favorites_provider.dart';
import 'package:flick/providers/songs_provider.dart';
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

/// The two Cover Flow shelves on Home.
enum KonnektedCoverShelf {
  recent('Recent'),
  added('New');

  const KonnektedCoverShelf(this.label);

  final String label;
}

/// Albums for Home's Cover Flow: the ones played lately, or newest added.
final konnektedCoverAlbumsProvider = Provider.autoDispose
    .family<AsyncValue<List<AlbumGroup>>, KonnektedCoverShelf>((ref, shelf) {
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
