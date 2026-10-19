import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/data/repositories/song_repository.dart';
import 'package:flick/features/konnekted/konnekted_data.dart';
import 'package:flick/models/song.dart';
import 'package:flick/widgets/lokal/lokal_cover_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Song _track(String id, String album, {int addedDay = 1}) => Song(
  id: id,
  title: 'Track $id',
  artist: 'Artist',
  album: album,
  albumArtist: 'Artist',
  duration: const Duration(minutes: 3),
  fileType: 'FLAC',
  filePath: '/music/$album/$id.flac',
  dateAdded: DateTime(2026, 1, addedDay),
);

AlbumGroup _album(String name, List<Song> songs) =>
    AlbumGroup(key: name, albumName: name, albumArtist: 'Artist', songs: songs);

Widget _app(Widget child) => MaterialApp(
  theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.dark)),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  final albums = [
    _album('First', [_track('1a', 'First'), _track('1b', 'First')]),
    _album('Second', [_track('2a', 'Second')]),
    _album('Third', [_track('3a', 'Third')]),
  ];

  testWidgets('a swipe spins to the next album and settles on it', (
    tester,
  ) async {
    final seen = <int>[];
    await tester.pumpWidget(
      _app(
        LokalCoverFlow(
          albums: albums,
          cover: (album) => ColoredBox(
            color: Colors.blueGrey,
            child: Text('cover ${album.albumName}'),
          ),
          onPlay: (_, _) {},
          onIndexChanged: seen.add,
        ),
      ),
    );
    expect(find.text('First'), findsOneWidget);
    await tester.drag(find.byType(LokalCoverFlow), const Offset(-90, 0));
    await tester.pumpAndSettle();
    expect(seen.last, 1);
    expect(find.text('Second'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the facing cover flips to its tracks and plays the album', (
    tester,
  ) async {
    Song? played;
    List<Song>? queue;
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        LokalCoverFlow(
          albums: albums,
          cover: (_) => const ColoredBox(color: Colors.blueGrey),
          onPlay: (song, album) {
            played = song;
            queue = album;
          },
        ),
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel(RegExp('^Cover Flow'))).value,
      '1 of 3',
    );
    await tester.tapAt(
      tester.getCenter(find.byType(LokalCoverFlow)) - const Offset(0, 40),
    );
    await tester.pumpAndSettle();
    expect(find.text('Track 1b'), findsOneWidget);
    await tester.tap(find.text('PLAY'));
    expect(played?.id, '1a');
    expect(queue?.map((s) => s.id), ['1a', '1b']);
    semantics.dispose();
  });

  test(
    'cover shelves: newest albums first, recent ones in play order',
    () async {
      final library = [
        _track('old', 'Old', addedDay: 1),
        _track('new', 'New', addedDay: 9),
        _track('mid1', 'Mid', addedDay: 5),
        _track('mid2', 'Mid', addedDay: 4),
      ];
      final container = ProviderContainer(
        overrides: [
          konnektedLibraryProvider.overrideWithValue(AsyncData(library)),
          konnektedRecentSongsProvider.overrideWith(
            (ref) => Stream.value([library[3], library[0], library[2]]),
          ),
        ],
      );
      addTearDown(container.dispose);
      final added = container.read(
        konnektedCoverAlbumsProvider(KonnektedCoverShelf.added),
      );
      expect(added.value!.map((a) => a.albumName), ['New', 'Mid', 'Old']);

      final sub = container.listen(
        konnektedCoverAlbumsProvider(KonnektedCoverShelf.recent),
        (_, _) {},
      );
      addTearDown(sub.close);
      await container.read(konnektedRecentSongsProvider.future);
      expect(
        container
            .read(konnektedCoverAlbumsProvider(KonnektedCoverShelf.recent))
            .value!
            .map((a) => a.albumName),
        ['Mid', 'Old'],
      );
    },
  );
}
