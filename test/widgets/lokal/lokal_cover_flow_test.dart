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

  testWidgets('iTunes reference triangles match four projected corners on both sides', (tester) async {
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
    final selected = panel('Third');

    // The first Transform in each Positioned cover applies the real
    // Matrix4 perspective. Project the actual local cover corners, including
    // its transform origin and homogeneous perspective division.
    Offset project(Transform panel, double x, double y) {
      final origin = panel.origin!;
      return MatrixUtils.transformPoint(
        panel.transform,
        Offset(x - origin.dx, y - origin.dy),
      ) + origin - Offset(size / 2, size / 2);
    }
    for (final panel in [left, right, selected]) {
      expect(panel.origin!.dx, closeTo(size / 2, .0001),
          reason: '3D pivot must be at artwork center');
      expect(panel.origin!.dy, closeTo(size / 2, .0001));
    }
    // Normalized coordinates measured on the iTunes reference. The outer
    // edges are ~92% of artwork height; the inner edges only ~65% and
    // drop toward the lower vanishing point. BOTH triangle slopes matter.
    final loTop = project(left, 0, 0);
    final loBottom = project(left, 0, size);
    final liTop = project(left, size, 0);
    final liBottom = project(left, size, size);
    final riTop = project(right, 0, 0);
    final riBottom = project(right, 0, size);
    final roTop = project(right, size, 0);
    final roBottom = project(right, size, size);
    void near(String label, double actual, double normalized) =>
        expect(actual / size, closeTo(normalized, .007), reason: label);

    near('left outside upper x', loTop.dx, -1.067);
    near('left outside upper y', loTop.dy, -.447);
    near('left outside lower y', loBottom.dy, .473);
    near('left inside upper x', liTop.dx, -.429);
    near('left inside upper y', liTop.dy, -.269);
    near('left inside lower y', liBottom.dy, .381);
    near('right inside upper x', riTop.dx, .429);
    near('right outside upper x', roTop.dx, 1.067);
    near('right outside upper y', roTop.dy, -.447);
    near('right outside lower y', roBottom.dy, .473);
    near('right inside upper y', riTop.dy, -.269);
    near('right inside lower y', riBottom.dy, .381);

    expect(liTop.dx, greaterThan(-size * .5),
        reason: 'center cover masks left inner edge');
    expect(riTop.dx, lessThan(size * .5),
        reason: 'center cover masks right inner edge');
    expect(loTop.dy, lessThan(liTop.dy),
        reason: 'top triangular gap slopes down to center');
    expect(loBottom.dy, greaterThan(liBottom.dy),
        reason: 'lower triangle slopes up to center');
    expect(roTop.dy, lessThan(riTop.dy));
    expect(roBottom.dy, greaterThan(riBottom.dy));
    expect(left.transform.entry(2, 0), lessThan(0),
        reason: 'left outer edge projects toward the viewer');
    expect(right.transform.entry(2, 0), greaterThan(0),
        reason: 'right outer edge projects toward the viewer');
    expect(left.transform.entry(3, 2), lessThan(0),
        reason: 'rearward depth must SHRINK the covers');
    expect(right.transform.entry(3, 2), lessThan(0));

    final coverStack = tester.widgetList<Stack>(
      find.descendant(of: find.byType(LokalCoverFlow), matching: find.byType(Stack)),
    ).firstWhere((stack) => stack.children.whereType<Positioned>().length == 5);
    expect(coverStack.children.last.key, const ValueKey('Third'),
        reason: 'center album paints above all four adjacent angled covers');
    expect(find.byType(ShaderMask), findsNothing,
        reason: 'mobile reflection shader must be completely removed');
    expect(find.byType(OverflowBox), findsNothing,
        reason: 'no mirrored second artwork subtree');
  });

  test('center translation is C1-smooth with exact iTunes side cover calibration', () {
    double pos(double a) => a >= 1
        ? .91 + (a - 1) * .18
        : .90 * a + .75 * a * a - .74 * a * a * a;
    double depth(double a) => a >= 1
        ? .60 + (a - 1) * .01
        : .60 * a * a * (3 - 2 * a);
    const e = .00001;
    expect(pos(0), 0);
    expect(pos(1), closeTo(.91, 1e-9));
    expect(pos(2) - pos(1), closeTo(.18, 1e-9));
    expect((pos(1) - pos(1 - e)) / e, closeTo((pos(1 + e) - pos(1)) / e, .001));
    expect((pos(e) - pos(0)) / e, closeTo(.90, .001));
    expect(depth(0), 0);
    expect(depth(1), closeTo(.60, 1e-9));
    expect((depth(1) - depth(1 - e)) / e,
        closeTo((depth(1 + e) - depth(1)) / e, .001));
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
