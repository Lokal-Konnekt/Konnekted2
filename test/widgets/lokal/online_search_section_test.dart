import 'dart:convert';
import 'dart:io';

import 'package:flick/data/entities/song_entity.dart';
import 'package:flick/features/discovery/discovery_artwork.dart';
import 'package:flick/features/discovery/discovery_http.dart';
import 'package:flick/features/discovery/discovery_models.dart';
import 'package:flick/features/konnekted/konnekted_discovery.dart';
import 'package:flick/features/search/library_download.dart';
import 'package:flick/features/search/widgets/online_search_section.dart';
import 'package:flick/models/song.dart';
import 'package:flick/providers/player_provider.dart';
import 'package:flick/services/queue_pre_resolver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

OnlineSource _source(String id, String name, List<String> titles) =>
    OnlineSource(
      id: id,
      name: name,
      addon: id != 'yt',
      results: (query) async => [
        for (final title in titles)
          OnlineResult(
            DiscoveryTrack(
              id: '$id-$title',
              title: title,
              artist: 'Artist',
              source: DiscoverySource.morneye,
            ),
          ),
      ],
      play: (_) async => throw const DiscoveryException('No stream'),
    );

final _nowPlaying = Song(
  id: 'now',
  title: 'Now playing',
  artist: 'Someone',
  duration: const Duration(minutes: 3),
  fileType: 'FLAC',
  filePath: '/library/now.flac',
);

class _FakePlayer extends PlayerNotifier {
  _FakePlayer({this.current});

  final Song? current;
  final queued = <Song>[];
  final movedToNext = <int>[];

  @override
  PlayerState build() => PlayerState(currentSong: current);

  @override
  Future<int> addToQueue(Song song) async {
    queued.add(song);
    return queued.length - 1;
  }

  @override
  Future<void> moveQueueItemToNext(int index) async => movedToNext.add(index);
}

/// Covers are looked up nowhere: no library, and Deezer/iTunes find nothing.
final _quietArtwork = [
  discoveryLocalArtworkProvider.overrideWithValue(DiscoveryLocalArtwork.empty),
  discoveryArtworkResolverProvider.overrideWithValue(
    DiscoveryArtworkResolver(
      DiscoveryHttp(
        MockClient(
          (_) async => http.Response(
            jsonEncode({'data': [], 'results': []}),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      ),
    ),
  ),
];

Future<void> _pump(
  WidgetTester tester, {
  required List<OnlineSource> sources,
  _FakePlayer? player,
  Song Function(OnlineSource, DiscoveryTrack)? pendingSong,
  Future<Song> Function(OnlineSource, DiscoveryTrack, void Function(String))?
  prepare,
  LibraryDownloader? downloader,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ..._quietArtwork,
        if (player != null) playerProvider.overrideWith(() => player),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              OnlineSearchSection(
                query: 'song',
                sources: (_, _) async => sources,
                pendingSong: pendingSong,
                prepare: prepare,
                downloader: downloader,
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('add-ons appear as sources and their results play on tap', (
    tester,
  ) async {
    await _pump(
      tester,
      sources: [
        _source('yt', 'YouTube Music', ['From YouTube']),
        _source('a-tidal', 'Tidal', ['From Tidal']),
      ],
    );
    expect(find.text('From YouTube'), findsOneWidget);

    await tester.tap(find.text('Tidal'));
    await tester.pumpAndSettle();
    expect(find.text('From Tidal'), findsOneWidget);
    expect(find.text('From an add-on you installed'), findsOneWidget);

    await tester.tap(find.text('From Tidal'));
    await tester.pumpAndSettle();
    expect(find.text('No stream'), findsOneWidget);
  });

  testWidgets('a long press offers play, queue and download actions', (
    tester,
  ) async {
    await _pump(
      tester,
      sources: [
        _source('yt', 'YouTube Music', ['Song A']),
      ],
    );
    await tester.longPress(find.text('Song A'));
    await tester.pumpAndSettle();
    for (final label in [
      'Play',
      'Play next',
      'Add to queue',
      'Download to library',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Artist · YouTube Music'), findsOneWidget);
  });

  testWidgets('Play next queues a placeholder that resolves ahead', (
    tester,
  ) async {
    final player = _FakePlayer(current: _nowPlaying);
    final resolver = QueuePreResolver();
    await _pump(
      tester,
      sources: [
        _source('yt', 'YouTube Music', ['Song A']),
      ],
      player: player,
      pendingSong: (source, track) =>
          onlinePendingSong(source.id, track, resolver: resolver),
    );

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play next'));
    await tester.pumpAndSettle();

    final pending = player.queued.single;
    expect(pending.isPending, isTrue);
    expect(pending.title, 'Song A');
    expect(pending.artist, 'Artist');
    expect(player.movedToNext, [0]);
    expect(find.text('Song A plays next'), findsOneWidget);

    await tester.longPress(find.text('Song A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to queue'));
    await tester.pumpAndSettle();
    expect(player.queued, hasLength(2));
    expect(player.movedToNext, [0], reason: 'Add to queue goes at the end');
    expect(find.text('Added Song A to the queue'), findsOneWidget);
  });

  testWidgets('Download to library fetches the song and saves it', (
    tester,
  ) async {
    late Directory root;
    late File cached;
    final saved = <SongEntity>[];
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('online_download_test');
      cached = File(p.join(root.path, 'cache.m4a'))
        ..writeAsBytesSync(List.filled(16, 1));
      Directory(p.join(root.path, 'Library')).createSync();
    });
    addTearDown(() => root.deleteSync(recursive: true));

    final fetched = <String>[];
    await _pump(
      tester,
      sources: [
        _source('yt', 'YouTube Music', ['Song A']),
      ],
      prepare: (source, track, onStatus) async {
        fetched.add('${source.id}:${track.id}');
        return Song(
          id: 'discovery:1',
          title: track.title,
          artist: track.artist,
          duration: const Duration(minutes: 3),
          fileType: 'M4A',
          filePath: cached.path,
        );
      },
      downloader: LibraryDownloader(
        folders: () async => [
          LibraryDownloadFolder(
            uri: 'content://music',
            name: 'Music',
            path: p.join(root.path, 'Library'),
          ),
        ],
        fallbackRoot: p.join(root.path, 'Fallback'),
        registerFolder: (_, _) async {},
        upsert: (entity) async => saved.add(entity),
        tag: (_, _) async => true,
        cover: (_, _, _) async {},
        indexMedia: (_) async {},
      ),
    );

    await tester.longPress(find.text('Song A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download to library'));
    // The copy is real file work: let it run between frames.
    final done = find.textContaining('Saved Song A');
    for (var i = 0; i < 200 && done.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    await tester.pumpAndSettle();

    expect(fetched, ['yt:yt-Song A']);
    expect(saved.single.title, 'Song A');
    expect(
      saved.single.filePath,
      p.join(root.path, 'Library', 'Lokal Downloads', 'Artist - Song A.m4a'),
    );
    expect(
      find.text('Saved Song A to your library (Music/Lokal Downloads).'),
      findsOneWidget,
    );
  });

  testWidgets('a failed download says why', (tester) async {
    await _pump(
      tester,
      sources: [
        _source('yt', 'YouTube Music', ['Song A']),
      ],
      prepare: (_, _, _) async =>
          throw const DiscoveryException('Not available here.'),
    );
    await tester.longPress(find.text('Song A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download to library'));
    await tester.pumpAndSettle();
    expect(
      find.text('Couldn’t save Song A. Not available here.'),
      findsOneWidget,
    );
  });
}
