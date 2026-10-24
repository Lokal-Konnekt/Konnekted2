import 'package:flick/data/repositories/song_repository.dart';
import 'package:flick/models/song.dart';
import 'package:flick/services/favorites_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Songs implements SongRepository {
  _Songs(this.songs);
  final List<Song> songs;

  @override
  Future<List<Song>> getAllSongs() async => songs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingSongs implements SongRepository {
  @override
  Future<List<Song>> getAllSongs() async => throw StateError('database unavailable');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('liked streamed songs survive service restart and appear in Liked', () async {
    const online = Song(
      id: 'discovery:example', title: 'Streamed track',
      artist: 'Artist', album: 'Album',
      duration: Duration(minutes: 3), fileType: 'OPUS',
      resolution: '138 kbps', remoteId: 'video-123',
      sourcePackage: 'konnekted.discovery', isExternal: true,
    );
    final service = FavoritesService(songRepository: _Songs([]));
    expect(await service.toggleFavorite(online.id, song: online), isTrue);

    // The real Favorites provider instantiates a new service on invalidation,
    // not the instance which handled the heart tap.
    final reopened = FavoritesService(songRepository: _Songs([]));
    final liked = await reopened.getFavorites();
    expect(liked, hasLength(1));
    expect(liked.single.title, online.title);
    expect(liked.single.artist, online.artist);
    expect(liked.single.fileType, 'OPUS');
    expect(liked.single.resolution, '138 kbps');
    expect(await reopened.isFavorite(online.id), isTrue);

    expect(await reopened.toggleFavorite(online.id), isFalse);
    expect(await FavoritesService(songRepository: _Songs([])).getFavorites(),
        isEmpty);
  });

  test('online metadata supplements but does not duplicate local liked songs', () async {
    const local = Song(
      id: 'local-1', title: 'Library song', artist: 'Artist',
      duration: Duration(minutes: 1), fileType: 'FLAC',
    );
    const streamed = Song(
      id: 'stream-2', title: 'Stream song', artist: 'Artist',
      duration: Duration(minutes: 1), fileType: 'AAC',
      isExternal: true, sourcePackage: 'konnekted.discovery',
    );
    final repo = _Songs([local]);
    final service = FavoritesService(songRepository: repo);
    await service.addFavorite(local.id, song: local);
    await service.addFavorite(streamed.id, song: streamed);
    final liked = await FavoritesService(songRepository: repo).getFavorites();
    expect(liked.map((song) => song.id), containsAll([local.id, streamed.id]));
    expect(liked, hasLength(2));
  });

  test('simultaneous player instances do not overwrite each other’s likes', () async {
    const first = Song(
      id: 'discovery:tidal:1', title: 'Tidal track', artist: 'Artist',
      duration: Duration(minutes: 4), fileType: 'FLAC',
      sourcePackage: 'konnekted.morneye-live', isExternal: true,
    );
    const second = Song(
      id: 'discovery:yt:2', title: 'YT track', artist: 'Artist',
      duration: Duration(minutes: 2), fileType: 'OPUS',
      sourcePackage: 'konnekted.discovery', isExternal: true,
    );
    final playerA = FavoritesService(songRepository: _Songs([]));
    final playerB = FavoritesService(songRepository: _Songs([]));
    await Future.wait([
      playerA.addFavorite(first.id, song: first),
      playerB.addFavorite(second.id, song: second),
    ]);
    final reopened = FavoritesService(songRepository: _Songs([]));
    expect((await reopened.getFavoriteIds()), containsAll([first.id, second.id]));
    expect((await reopened.getFavorites()).map((s) => s.id),
        containsAll([first.id, second.id]));
    await playerA.removeFavorite(first.id);
    expect(await playerB.isFavorite(first.id), isFalse,
        reason: 'Services must not keep stale per-instance favorite IDs');
    expect(await playerB.isFavorite(second.id), isTrue);
    await reopened.clearFavorites();
    expect(await FavoritesService(songRepository: _Songs([])).getFavorites(),
        isEmpty);
  });

  test('a failed local library lookup does not hide saved online likes', () async {
    const song = Song(
      id: 'discovery:tidal:3', title: 'Streamed', artist: 'Singer',
      duration: Duration(minutes: 2), fileType: 'FLAC',
      sourcePackage: 'konnekted.morneye-live', isExternal: true,
    );
    await FavoritesService(songRepository: _Songs([]))
        .addFavorite(song.id, song: song);
    final likes = await FavoritesService(
      songRepository: _FailingSongs(),
    ).getFavorites();
    expect(likes.single.id, song.id);
  });

  test('old liked IDs remain liked even when no metadata was persisted', () async {
    SharedPreferences.setMockInitialValues({
      'favorite_song_ids': ['older-external-id'],
    });
    final service = FavoritesService(songRepository: _Songs([]));
    expect(await service.getFavoriteIds(), contains('older-external-id'));
    expect(await service.isFavorite('older-external-id'), isTrue);
  });

}
