import 'package:flick/features/playlist_links/playlist_link_backend.dart';
import 'package:flick/features/playlist_links/playlist_link_http.dart';
import 'package:flick/features/playlist_links/playlist_link_importers.dart';
import 'package:flick/features/playlist_links/playlist_link_manager.dart';
import 'package:flick/features/playlist_links/playlist_link_models.dart';
import 'package:flick/features/playlist_links/playlist_link_store.dart';
import 'package:flick/models/playlist.dart';
import 'package:flick/models/song.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeImporter implements PlaylistLinkImporter {
  RemotePlaylistSnapshot snapshot;
  Object? failure;

  FakeImporter(this.snapshot);

  @override
  Future<RemotePlaylistSnapshot> fetch(
    ParsedPlaylistLink link, {
    PlaylistLinkCancellationToken? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    if (failure != null) throw failure!;
    return snapshot;
  }
}

class FakeLibrary implements PlaylistLinkLibrary {
  final List<Song> songs;

  FakeLibrary(this.songs);

  @override
  Future<List<Song>> getSongs() async => songs;
}

class FakeBackend implements LinkedPlaylistBackend {
  final Map<String, Playlist> values = {};
  int serial = 0;

  @override
  Future<List<Playlist>> getPlaylists() async => values.values.toList();

  @override
  Future<Playlist?> getPlaylist(String id) async => values[id];

  @override
  Future<Playlist?> createPlaylist(String name) async {
    if (values.values.any((playlist) => playlist.name == name)) return null;
    final value = Playlist(
      id: 'p${serial++}',
      name: name,
      createdAt: DateTime(2024),
    );
    values[value.id] = value;
    return value;
  }

  @override
  Future<bool> addSong(String playlistId, String songId) async {
    final playlist = values[playlistId];
    if (playlist == null) return false;
    if (!playlist.songIds.contains(songId)) {
      values[playlistId] = playlist.copyWith(
        songIds: [...playlist.songIds, songId],
      );
    }
    return true;
  }

  @override
  Future<bool> removeSong(String playlistId, String songId) async {
    final playlist = values[playlistId];
    if (playlist == null) return false;
    values[playlistId] = playlist.copyWith(
      songIds: playlist.songIds.where((id) => id != songId).toList(),
    );
    return true;
  }

  @override
  Future<bool> reorderSongs(
    String playlistId,
    int oldIndex,
    int newIndex,
  ) async {
    final playlist = values[playlistId];
    if (playlist == null) return false;
    final ids = [...playlist.songIds];
    final value = ids.removeAt(oldIndex);
    ids.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, value);
    values[playlistId] = playlist.copyWith(songIds: ids);
    return true;
  }

  @override
  Future<bool> deletePlaylist(String playlistId) async =>
      values.remove(playlistId) != null;

  @override
  Future<bool> replaceOrder(String playlistId, List<String> targetOrder) async {
    final playlist = values[playlistId];
    if (playlist == null) return false;
    values[playlistId] = playlist.copyWith(songIds: [...targetOrder]);
    return true;
  }
}

Song _song(String id, String title, String artist) => Song(
  id: id,
  title: title,
  artist: artist,
  duration: const Duration(minutes: 3),
  fileType: 'FLAC',
  filePath: '/music/$id.flac',
);

RemotePlaylistEntry _entry(String title, String artist) =>
    RemotePlaylistEntry(title: title, artist: artist);

RemotePlaylistSnapshot _snapshot(
  List<RemotePlaylistEntry> entries, {
  bool complete = true,
}) =>
    RemotePlaylistSnapshot(title: 'Mix', entries: entries, complete: complete);

const _url = 'https://www.youtube.com/playlist?list=PL_abc-12345';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'create dedupes matches in remote order and prevents duplicate link',
    () async {
      final backend = FakeBackend();
      final store = MemoryPlaylistLinkStore();
      final manager = PlaylistLinkManager(
        importer: FakeImporter(
          _snapshot([
            _entry('Two', 'B'),
            _entry('One', 'A'),
            _entry('Two', 'B'),
          ]),
        ),
        metadataStore: store,
        playlists: backend,
        library: FakeLibrary([_song('1', 'One', 'A'), _song('2', 'Two', 'B')]),
      );
      final preview = await manager.preview(_url);
      final record = await manager.createFromPreview(preview);

      expect((await backend.getPlaylist(record.playlistId))!.songIds, [
        '2',
        '1',
      ]);
      expect(record.duplicateMatches, 1);
      expect(
        () => manager.createFromPreview(preview),
        throwsA(isA<PlaylistLinkOperationException>()),
      );
      expect(await backend.getPlaylists(), hasLength(1));
    },
  );

  test('downloaded unmatched entry appears in the linked playlist immediately', () async {
    final backend = FakeBackend();
    final store = MemoryPlaylistLinkStore();
    final library = FakeLibrary([_song('1', 'One', 'A')]);
    final manager = PlaylistLinkManager(
      importer: FakeImporter(
        _snapshot([_entry('One', 'A'), _entry('Missing', 'B')]),
      ),
      metadataStore: store,
      playlists: backend,
      library: library,
    );
    final record = await manager.createFromPreview(await manager.preview(_url));
    expect(record.unmatchedEntries.single.title, 'Missing');
    library.songs.add(_song('new-file', 'Missing', 'B'));
    final id = await manager.attachDownloadedEntry(
      record.linkId, record.unmatchedEntries.single,
      savedPath: '/music/new-file.flac',
    );
    expect(id, 'new-file');
    expect((await backend.getPlaylist(record.playlistId))!.songIds,
        ['1', 'new-file']);
    expect((await store.load()).single.unmatchedEntries, isEmpty);
    expect((await store.load()).single.managedSongIds, ['1']);

    // A later remote refresh must not delete an explicitly saved track.
    final partial = await manager.refreshFromPreview(
      await manager.preview(_url), removeMissing: true,
    );
    expect(partial.playlist.songIds, ['1', 'new-file']);
  });

  test('linking a downloaded file fails safely when the file was not indexed', () async {
    final backend = FakeBackend();
    final store = MemoryPlaylistLinkStore();
    final manager = PlaylistLinkManager(
      importer: FakeImporter(_snapshot([_entry('Missing', 'B')])),
      metadataStore: store,
      playlists: backend,
      library: FakeLibrary([]),
    );
    final record = await manager.createFromPreview(await manager.preview(_url));
    await expectLater(
      manager.attachDownloadedEntry(
        record.linkId, record.unmatchedEntries.single,
        savedPath: '/music/not-indexed.flac',
      ),
      throwsA(isA<PlaylistLinkOperationException>()),
    );
    expect((await backend.getPlaylist(record.playlistId))!.songIds, isEmpty);
    expect((await store.load()).single.unmatchedEntries, hasLength(1));
  });

  test(
    'partial refresh only appends and keeps previous entries and local additions',
    () async {
      final backend = FakeBackend();
      final importer = FakeImporter(
        _snapshot([_entry('One', 'A'), _entry('Two', 'B')]),
      );
      final manager = PlaylistLinkManager(
        importer: importer,
        metadataStore: MemoryPlaylistLinkStore(),
        playlists: backend,
        library: FakeLibrary([
          _song('1', 'One', 'A'),
          _song('2', 'Two', 'B'),
          _song('3', 'Three', 'C'),
        ]),
      );
      final record = await manager.createFromPreview(
        await manager.preview(_url),
      );
      await backend.addSong(record.playlistId, 'local');
      importer.snapshot = _snapshot([_entry('Three', 'C')], complete: false);
      final result = await manager.refreshFromPreview(
        await manager.preview(_url),
        removeMissing: true,
      );

      expect(result.playlist.songIds, ['1', '2', 'local', '3']);
      expect(result.removedMissing, isFalse);
      expect(result.record.isPartial, isTrue);
    },
  );

  test(
    'complete refresh requires removal flag and retains local additions',
    () async {
      final backend = FakeBackend();
      final importer = FakeImporter(
        _snapshot([_entry('One', 'A'), _entry('Two', 'B')]),
      );
      final manager = PlaylistLinkManager(
        importer: importer,
        metadataStore: MemoryPlaylistLinkStore(),
        playlists: backend,
        library: FakeLibrary([
          _song('1', 'One', 'A'),
          _song('2', 'Two', 'B'),
          _song('3', 'Three', 'C'),
        ]),
      );
      final record = await manager.createFromPreview(
        await manager.preview(_url),
      );
      await backend.addSong(record.playlistId, 'local');
      importer.snapshot = _snapshot([_entry('Three', 'C'), _entry('Two', 'B')]);
      final preview = await manager.preview(_url);
      final result = await manager.refreshFromPreview(
        preview,
        removeMissing: true,
      );

      expect(result.playlist.songIds, ['3', '2', 'local']);
      final repeated = await manager.refreshFromPreview(
        await manager.preview(_url),
        removeMissing: true,
      );
      expect(repeated.changed, isFalse);
    },
  );

  test(
    'remote failure preserves saved state and persistence failure rolls back playlist',
    () async {
      final backend = FakeBackend();
      final store = MemoryPlaylistLinkStore();
      final importer = FakeImporter(_snapshot([_entry('One', 'A')]));
      final manager = PlaylistLinkManager(
        importer: importer,
        metadataStore: store,
        playlists: backend,
        library: FakeLibrary([_song('1', 'One', 'A'), _song('2', 'Two', 'B')]),
      );
      final record = await manager.createFromPreview(
        await manager.preview(_url),
      );
      importer.failure = const PlaylistLinkHttpException('Failed');
      await expectLater(
        manager.preview(_url),
        throwsA(isA<PlaylistLinkHttpException>()),
      );
      expect((await store.load()).single.managedSongIds, ['1']);

      importer.failure = null;
      importer.snapshot = _snapshot([_entry('Two', 'B')]);
      final preview = await manager.preview(_url);
      store.failWrites = true;
      await expectLater(
        manager.refreshFromPreview(preview, removeMissing: true),
        throwsA(isA<PlaylistLinkStoreException>()),
      );
      expect((await backend.getPlaylist(record.playlistId))!.songIds, ['1']);
      expect((await store.load()).single.managedSongIds, ['1']);
    },
  );

  test(
    'preferences metadata reloads and unlink leaves the saved playlist intact',
    () async {
      SharedPreferences.setMockInitialValues({});
      final backend = FakeBackend();
      final store = SharedPreferencesPlaylistLinkStore();
      final manager = PlaylistLinkManager(
        importer: FakeImporter(
          _snapshot([_entry('One', 'A'), _entry('Missing', 'Nobody')]),
        ),
        metadataStore: store,
        playlists: backend,
        library: FakeLibrary([_song('1', 'One', 'A')]),
      );
      final record = await manager.createFromPreview(
        await manager.preview(_url),
      );
      final reloaded = await SharedPreferencesPlaylistLinkStore().load();

      expect(reloaded.single.linkId, record.linkId);
      expect(reloaded.single.unmatchedEntries.single.title, 'Missing');
      await manager.unlink(record.linkId);
      expect(await store.load(), isEmpty);
      expect((await backend.getPlaylist(record.playlistId))!.songIds, ['1']);
    },
  );
}
