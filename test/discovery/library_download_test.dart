import 'dart:io';

import 'package:flick/data/entities/song_entity.dart';
import 'package:flick/features/discovery/discovery_models.dart';
import 'package:flick/features/search/library_download.dart';
import 'package:flick/models/song.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late File cached;
  final upserts = <SongEntity>[];
  final registered = <String>[];
  final indexed = <String>[];
  final covers = <String>[];

  setUp(() async {
    root = await Directory.systemTemp.createTemp('library_download_test');
    cached = File(p.join(root.path, 'cache', 'abc.m4a'));
    await cached.create(recursive: true);
    await cached.writeAsBytes(List.filled(64, 7));
    upserts.clear();
    registered.clear();
    indexed.clear();
    covers.clear();
  });

  tearDown(() => root.delete(recursive: true));

  Song prepared() => Song(
    id: 'discovery:abc',
    title: 'Song: One?',
    artist: 'The Artist',
    album: 'Album',
    duration: const Duration(seconds: 200),
    fileType: 'M4A',
    sampleRate: 44100,
    filePath: cached.path,
    isExternal: true,
  );

  LibraryDownloader downloader(
    List<LibraryDownloadFolder> folders, {
    bool tagged = true,
  }) => LibraryDownloader(
    folders: () async => folders,
    fallbackRoot: p.join(root.path, 'Music'),
    registerFolder: (path, name) async => registered.add(path),
    upsert: (entity) async => upserts.add(entity),
    tag: (path, song) async => tagged,
    cover: (path, song, url) async => covers.add(url),
    indexMedia: (paths) async => indexed.addAll(paths),
    now: () => DateTime(2026, 10, 20),
  );

  test('copies into the first writable library folder and adds it', () async {
    final music = Directory(p.join(root.path, 'Library'))..createSync();
    final saved = await downloader([
      const LibraryDownloadFolder(uri: 'content://saf-only', name: 'SD'),
      LibraryDownloadFolder(
        uri: 'content://tree/music',
        name: 'Music',
        path: music.path,
      ),
    ]).save(prepared(), artwork: 'https://example.com/cover.jpg');

    expect(saved.fallback, isFalse);
    expect(saved.folderName, 'Music');
    expect(
      saved.path,
      p.join(music.path, 'Lokal Downloads', 'The Artist - Song One.m4a'),
    );
    expect(File(saved.path).readAsBytesSync(), hasLength(64));
    expect(cached.existsSync(), isTrue, reason: 'the cache keeps its copy');

    final entity = upserts.single;
    expect(entity.filePath, saved.path);
    expect(entity.title, 'Song: One?');
    expect(entity.artist, 'The Artist');
    expect(entity.album, 'Album');
    expect(entity.durationMs, 200000);
    expect(entity.fileType, 'M4A');
    expect(entity.folderUri, 'content://tree/music');
    expect(entity.relativeFolderPath, 'Lokal Downloads');
    expect(entity.hasLocalEdits, isFalse);
    expect(indexed, [saved.path]);
    expect(covers, ['https://example.com/cover.jpg']);
    expect(registered, isEmpty);
  });

  test(
    'a second copy gets a numbered name; untagged keeps its names',
    () async {
      final music = Directory(p.join(root.path, 'Library'))..createSync();
      final folders = [
        LibraryDownloadFolder(uri: 'u', name: 'Music', path: music.path),
      ];
      await downloader(folders).save(prepared());
      final second = await downloader(folders, tagged: false).save(prepared());
      expect(p.basename(second.path), 'The Artist - Song One (2).m4a');
      expect(upserts.last.hasLocalEdits, isTrue);
    },
  );

  test(
    'falls back to Lokal Downloads in Music and adds it to the library',
    () async {
      // A library folder that can't hold a new folder (it's a file here).
      final blocked = File(p.join(root.path, 'blocked'))..createSync();
      final saved = await downloader([
        LibraryDownloadFolder(uri: 'u', name: 'Locked', path: blocked.path),
      ]).save(prepared());

      final fallback = p.join(root.path, 'Music', 'Lokal Downloads');
      expect(saved.fallback, isTrue);
      expect(saved.folderName, 'Lokal Downloads');
      expect(p.dirname(saved.path), fallback);
      expect(registered, [fallback]);
      expect(upserts.single.folderUri, fallback);
      expect(upserts.single.relativeFolderPath, '');
    },
  );

  test('fails with a message when nothing can be written', () async {
    File(p.join(root.path, 'Music')).createSync(); // Music is a file.
    await expectLater(
      downloader(const []).save(prepared()),
      throwsA(isA<DiscoveryException>()),
    );
    expect(upserts, isEmpty);
  });

  test('a missing download is an error', () async {
    cached.deleteSync();
    await expectLater(
      downloader(const []).save(prepared()),
      throwsA(isA<DiscoveryException>()),
    );
  });

  test('file names drop characters file systems refuse', () {
    final song = prepared();
    expect(
      LibraryDownloader.fileName(song, '.mp3'),
      'The Artist - Song One.mp3',
    );
    expect(
      LibraryDownloader.fileName(
        Song(
          id: 'x',
          title: '..',
          artist: '/',
          duration: Duration.zero,
          fileType: 'MP3',
        ),
        '.mp3',
      ),
      'Song.mp3',
    );
  });
}
