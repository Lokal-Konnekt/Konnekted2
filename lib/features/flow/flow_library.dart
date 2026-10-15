import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/recently_played_repository.dart';
import '../../models/song.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/songs_provider.dart';
import 'domain/flow_engine.dart';
import 'domain/flow_models.dart';

final flowHistoryProvider = FutureProvider<List<String>>((ref) async {
  final history = await RecentlyPlayedRepository().getRecentHistory(limit: 500);
  return history.map((entry) => entry.song.id).toList();
});

final flowLibraryProvider = FutureProvider<FlowLibrary>((ref) async {
  final songsFuture = ref.watch(songsProvider.future);
  final favoritesFuture = ref.watch(favoritesProvider.future);
  final historyFuture = ref.watch(flowHistoryProvider.future);
  // Attach the optional history error handler before waiting for the library.
  String? warning;
  final history = historyFuture.catchError((Object _) {
    warning =
        'Listening history is unavailable. Flow is using your likes and '
        'plays observed in Flow.';
    return <String>[];
  });
  final songs = await songsFuture;
  final favorites = await favoritesFuture;
  return FlowLibrary(
    songs: songs.songs,
    favoriteIds: favorites.favoriteIds,
    historyIds: await history,
    warning: warning,
  );
});

class FlowLibrary {
  FlowLibrary({
    required Iterable<Song> songs,
    required Set<String> favoriteIds,
    this.historyIds = const [],
    this.warning,
  }) : songs = List.unmodifiable(
         songs.where(
           (song) =>
               !song.isExternal &&
               !song.isNetworkSource &&
               song.filePath?.trim().isNotEmpty == true,
         ),
       ),
       favoriteIds = Set.unmodifiable(favoriteIds) {
    byId = {for (final song in this.songs) song.id: song};
    tracks = this.songs
        .map(
          (song) => FlowTrack(
            id: song.id,
            title: song.title,
            artist: song.artist,
            album: song.album ?? '',
            durationMs: song.duration.inMilliseconds,
            genres: flowGenres(song.genre),
          ),
        )
        .toList(growable: false);
  }

  final List<Song> songs;
  final Set<String> favoriteIds;
  final List<String> historyIds;
  final String? warning;
  late final Map<String, Song> byId;
  late final List<FlowTrack> tracks;
  int get favoriteCount => favoriteIds.intersection(byId.keys.toSet()).length;
  bool get unlocked => FlowRules.isUnlocked(favoriteCount);

  List<Song> mix(FlowData data, DateTime now) {
    if (!unlocked) return const [];
    const engine = FlowEngine();
    final result = data.session.trackIds.isNotEmpty && data.session.isFresh(now)
        ? engine.restore(library: tracks, data: data, now: now)
        : engine.recommend(
            library: tracks,
            favoriteIds: favoriteIds,
            historyIds: historyIds,
            data: data,
          );
    return result.map((track) => byId[track.id]!).toList();
  }

  List<Song> topUp(FlowData data) {
    if (!unlocked) return const [];
    final remaining = FlowRules.maxSessionTracks - data.session.trackIds.length;
    return const FlowEngine()
        .recommend(
          library: tracks,
          favoriteIds: favoriteIds,
          historyIds: historyIds,
          data: data,
          excludeIds: data.session.trackIds.toSet(),
          limit: remaining.clamp(0, FlowRules.topUpTracks),
        )
        .map((track) => byId[track.id]!)
        .toList();
  }
}
