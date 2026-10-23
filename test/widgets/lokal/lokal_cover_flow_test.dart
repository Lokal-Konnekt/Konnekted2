import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/data/repositories/song_repository.dart';
import 'package:flick/features/konnekted/konnekted_data.dart';
import 'package:flick/features/konnekted/lokal_mixes.dart';
import 'package:flick/models/song.dart';
import 'package:flick/widgets/lokal/lokal_cover_flow.dart';
import 'dart:math' as math;

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

  testWidgets('iTunes side covers hinge inward and point their OUTER edges at the viewer', (
    tester,
  ) async {
    final five = [
      ...albums,
      _album('Fourth', [_track('4a', 'Fourth')]),
      _album('Fifth', [_track('5a', 'Fifth')]),
    ];
    await tester.pumpWidget(_app(LokalCoverFlow(
      albums: five,
      initialIndex: 2,
      cover: (_) => const ColoredBox(color: Colors.blueGrey),
      onPlay: (_, _) {},
    )));
    final size = math.min(250.0, tester.getSize(find.byType(LokalCoverFlow)).width * .60);
    Transform panel(String key) => tester.widget<Transform>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(Transform),
      ).first,
    );
    final left = panel('Second');
    final right = panel('Fourth');
    expect(left.origin!.dx, closeTo(size, .001), reason: 'left cover hinges on right/inner edge');
    expect(right.origin!.dx, closeTo(0, .001), reason: 'right cover hinges on left/inner edge');
    expect(left.transform.entry(2, 0), lessThan(0), reason: 'left OUTER edge faces forward');
    expect(right.transform.entry(2, 0), greaterThan(0), reason: 'right OUTER edge faces forward');
    expect(find.byType(ColoredBox), findsWidgets);
  });

  testWidgets('Home Cover Flow starts centered for odd and even shelves', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final four = [...albums, _album('Fourth', [_track('4a', 'Fourth')])];

    Widget shelf(List<AlbumGroup> entries) => _app(
      LokalCoverFlow(
        key: ValueKey(entries.length),
        albums: entries,
        initialIndex: entries.length ~/ 2,
        cover: (_) => const ColoredBox(color: Colors.blueGrey),
        onPlay: (_, _) {},
      ),
    );

    await tester.pumpWidget(shelf(albums));
    expect(
      tester.getSemantics(find.bySemanticsLabel(RegExp('^Cover Flow'))).value,
      '2 of 3',
    );
    expect(find.text('Second'), findsOneWidget);

    // Async recommendations can increase the shelf length while Home is open.
    await tester.pumpWidget(shelf(four));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.bySemanticsLabel(RegExp('^Cover Flow'))).value,
      '3 of 4',
    );
    expect(find.text('Third'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets(
    'removing cover flow during a drag does not query a dead context',
    (tester) async {
      await tester.pumpWidget(
        _app(
          LokalCoverFlow(
            albums: albums,
            cover: (_) => const ColoredBox(color: Colors.blueGrey),
            onPlay: (_, _) {},
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(LokalCoverFlow)),
      );
      await gesture.moveBy(const Offset(-40, 0));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await gesture.cancel();
      expect(tester.takeException(), isNull);
    },
  );

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

  testWidgets('with onSelect, one tap on any cover centres and selects it', (
    tester,
  ) async {
    final selected = <int>[];
    final seen = <int>[];
    await tester.pumpWidget(
      _app(
        LokalCoverFlow(
          albums: albums,
          cover: (_) => const ColoredBox(color: Colors.blueGrey),
          onPlay: (_, _) => fail('the track list should stay closed'),
          onSelect: selected.add,
          onIndexChanged: seen.add,
        ),
      ),
    );
    final centre =
        tester.getCenter(find.byType(LokalCoverFlow)) - const Offset(0, 40);
    // The facing cover: selected at once, no flip.
    await tester.tapAt(centre);
    await tester.pumpAndSettle();
    expect(selected, [0]);
    expect(find.text('PLAY'), findsNothing);
    // A side cover: comes forward and is selected in the same tap.
    await tester.tapAt(centre + const Offset(150, 0));
    await tester.pumpAndSettle();
    expect(selected, [0, 1]);
    expect(seen.last, 1);
    expect(find.text('Second'), findsOneWidget);
    // Long-press on the facing cover still shows its tracks.
    await tester.longPressAt(centre);
    await tester.pumpAndSettle();
    expect(find.text('PLAY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('Cover Flow holds Made for you, one song per cover, no repeats', () {
    final songs = [_track('a', 'A'), _track('b', 'B'), _track('a', 'A')];
    const mix = LokalMix(
      id: 'm',
      name: 'Daily Mix',
      type: LokalMixType.daily,
      tracks: [],
    );
    final container = ProviderContainer(
      overrides: [
        konnektedMadeForYouProvider.overrideWithValue(
          AsyncData([
            for (final song in songs) LokalMadeForYouPick(song: song, mix: mix),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);
    final covers = container.read(konnektedCoverAlbumsProvider).value!;
    expect(covers.map((a) => a.songs.single.id), ['a', 'b']);
    expect(covers.first.albumName, 'Track a');
  });
}
