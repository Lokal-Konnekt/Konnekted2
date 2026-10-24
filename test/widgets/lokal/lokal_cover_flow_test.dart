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

  testWidgets('iTunes side covers hinge inward and visually bring their OUTER edges forward', (
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
    // Check the actual perspective divide, not just the rotation sign:
    // the OUTSIDE edges must be projected larger/nearer than the inside edges.
    // This catches the exact reversed-fan regression shown on Home.
    double scaleAtEdge(Transform panel, double edge) {
      final w = panel.transform.entry(3, 0) * (edge - panel.origin!.dx) +
          panel.transform.entry(3, 3);
      return 1 / w;
    }
    expect(left.transform.entry(2, 0), greaterThan(0),
        reason: 'left cover turns towards the centre, not away from it');
    expect(right.transform.entry(2, 0), lessThan(0),
        reason: 'right cover turns towards the centre, not away from it');
    expect(scaleAtEdge(left, 0), greaterThan(scaleAtEdge(left, size)),
        reason: 'left outside edge must appear closer than the inside edge');
    expect(scaleAtEdge(right, size), greaterThan(scaleAtEdge(right, 0)),
        reason: 'right outside edge must appear closer than the inside edge');
    // iTunes reference: the centered square ends at ±.50 * size. The
    // neighbors' inner hinges must sit INSIDE that boundary (±.42 * size),
    // so the center square visually occludes them, not merely touches them.
    // Read the projected hinge, including perspective's homogeneous divide,
    // rather than asserting only the unprojected translation constant.
    double projectedOffset(Transform transform) =>
        transform.transform.entry(0, 3) / transform.transform.entry(3, 3);
    final leftInsideEdge = projectedOffset(left) + size / 2;
    final rightInsideEdge = projectedOffset(right) - size / 2;
    expect(leftInsideEdge, closeTo(-size * .42, size * .01),
        reason: 'left inside edge must sit behind the center artwork');
    expect(rightInsideEdge, closeTo(size * .42, size * .01),
        reason: 'right inside edge must sit behind the center artwork');
    expect(leftInsideEdge, greaterThan(-size * .50 + size * .07));
    expect(rightInsideEdge, lessThan(size * .50 - size * .07));
    expect(left.transform.entry(2, 3), lessThan(0),
        reason: 'left neighbor must remain at negative depth');
    expect(right.transform.entry(2, 3), lessThan(0),
        reason: 'right neighbor must remain at negative depth');
    // Flutter paints the farthest covers first, the center cover last.
    final coverStack = tester.widgetList<Stack>(
      find.descendant(
        of: find.byType(LokalCoverFlow),
        matching: find.byType(Stack),
      ),
    ).firstWhere((stack) => stack.children.whereType<Positioned>().length == 5);
    expect(coverStack.children.last.key, const ValueKey('Third'),
        reason: 'selected cover must cover both neighbors in paint order');
    expect(find.byType(ColoredBox), findsWidgets);
  });

  test('tucked-under hinge spacing is C1-continuous at the first neighbor', () {
    // Regression for the original flush-at-border .52 geometry.
    const hinge = .42;
    const shift = .52 - hinge;
    double inside(double a) => a >= 1
        ? hinge + (a - 1) * .34
        : .66 * a - .10 * a * a - .04 * a * a * a
            - shift * (3 * a * a - 2 * a * a * a);
    const e = .00001;
    expect(inside(0), 0);
    expect(inside(1), closeTo(.42, 1e-9));
    expect(inside(2) - inside(1), closeTo(.34, 1e-9));
    expect((inside(1) - inside(1 - e)) / e,
        closeTo((inside(1 + e) - inside(1)) / e, .001));
    expect((inside(e) - inside(0)) / e,
        closeTo((inside(0) - inside(-e).abs()) / e, .001));
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
