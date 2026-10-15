import 'dart:async';

import 'package:flick/data/repositories/recently_played_repository.dart';
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
