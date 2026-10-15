import 'package:flick/features/konnekted/konnekted_data.dart';
import 'package:flick/features/konnekted/konnekted_destination.dart';
import 'package:flick/features/konnekted/konnekted_dock.dart';
import 'package:flick/features/konnekted/konnekted_home.dart';
import 'package:flick/features/konnekted/konnekted_library.dart';
import 'package:flick/features/konnekted/konnekted_style.dart';
import 'package:flick/models/song.dart';
import 'package:flick/providers/player_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _song = Song(
  id: 'test-track',
  title: 'A long track title to exercise the compact dock',
  artist: 'An artist with a long display name',
  duration: Duration(minutes: 3),
  fileType: 'FLAC',
);

Widget _app(Widget child, {double scale = 1}) => MaterialApp(
  theme: KonnektedStyle.theme(ThemeData.dark()),
  home: MediaQuery(
    data: MediaQueryData(
      size: const Size(320, 568),
      textScaler: TextScaler.linear(scale),
      padding: const EdgeInsets.only(top: 24, bottom: 24),
      disableAnimations: true,
    ),
    child: Scaffold(body: child),
  ),
);

void main() {
  testWidgets(
    'empty home uses real provider boundaries and opens Flow and import',
    (tester) async {
      final opened = <KonnektedDestination>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            konnektedLibraryProvider.overrideWithValue(const AsyncData([])),
            konnektedFavoritesProvider.overrideWithValue(const AsyncData([])),
            konnektedRecentSongsProvider.overrideWith(
              (ref) => Stream.value([]),
            ),
          ],
          child: _app(
            KonnektedHome(
              onNavigate: opened.add,
              onPlay: (_, _) =>
                  fail('No music should be playable in an empty library'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Listen now'), findsOneWidget);
      await tester.tap(find.text('Open Flow'));
      expect(opened, [KonnektedDestination.flow]);
      await tester.scrollUntilVisible(find.text('Add your music'), 180);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add your music'));
      expect(opened.last, KonnektedDestination.librarySettings);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'library import and browse actions survive a narrow large-text screen',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final opened = <KonnektedDestination>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            konnektedLibraryProvider.overrideWithValue(const AsyncData([])),
          ],
          child: _app(KonnektedLibrary(onNavigate: opened.add), scale: 2),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Add a music folder'), 160);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add a music folder'));
      await tester.scrollUntilVisible(find.text('Albums'), 180);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Albums'));
      expect(opened, [
        KonnektedDestination.librarySettings,
        KonnektedDestination.albums,
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('shelf reports errors and retry without pretending to be empty', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      _app(
        SingleChildScrollView(
          child: KonnektedSongShelf(
            title: 'Favorites',
            songs: AsyncError(StateError('Unavailable'), StackTrace.empty),
            emptyTitle: 'Empty favorites',
            emptyMessage: 'No favorites yet',
            onSeeAll: () {},
            onRetry: () => retries++,
            onPlay: (_, _) {},
          ),
        ),
      ),
    );
    expect(find.text('Couldn’t load this shelf'), findsOneWidget);
    expect(find.text('Empty favorites'), findsNothing);
    await tester.tap(find.text('Try again'));
    expect(retries, 1);
  });

  testWidgets('shelf playback passes the tapped track and its real queue', (
    tester,
  ) async {
    Song? played;
    List<Song>? queue;
    await tester.pumpWidget(
      _app(
        SingleChildScrollView(
          child: KonnektedSongShelf(
            title: 'Recent music',
            songs: const AsyncData([_song]),
            emptyTitle: 'Empty',
            emptyMessage: 'Empty',
            onSeeAll: () {},
            onRetry: () {},
            onPlay: (song, shelf) {
              played = song;
              queue = shelf;
            },
          ),
        ),
        scale: 2,
      ),
    );
    await tester.tap(find.text(_song.title));
    expect(played, same(_song));
    expect(queue, [_song]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'mini player is absent without a current song and never opens a native player',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentSongProvider.overrideWithValue(null),
            isPlayingProvider.overrideWith(
              (ref) => throw StateError('Must not be read without a song'),
            ),
          ],
          child: _app(KonnektedMiniPlayer(onOpen: () {}, onQueue: () {})),
        ),
      );
      expect(find.byType(KonnektedMiniPlayerContent), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('compact dock keeps player, pause, queue, and all tabs usable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var playerOpens = 0;
    var pauseTaps = 0;
    var queueOpens = 0;
    var selected = KonnektedTab.listen;
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) => Align(
            alignment: Alignment.bottomCenter,
            child: KonnektedDock(
              selected: selected,
              onSelect: (tab) => setState(() => selected = tab),
              miniPlayer: KonnektedMiniPlayerContent(
                song: _song,
                isPlaying: true,
                onOpen: () => playerOpens++,
                onPlayPause: () => pauseTaps++,
                onNext: () {},
                onQueue: () => queueOpens++,
                progress: const LinearProgressIndicator(value: .25),
              ),
            ),
          ),
        ),
        scale: 2,
      ),
    );
    await tester.tap(find.bySemanticsLabel(RegExp('Open player for')));
    await tester.tap(find.byTooltip('Pause'));
    await tester.tap(find.byTooltip('Open queue'));
    for (final tab in KonnektedTab.values) {
      await tester.tap(find.text(tab.label));
      await tester.pump();
      expect(selected, tab);
      expect(
        tester.getSemantics(find.bySemanticsLabel(tab.label)),
        matchesSemantics(
          label: tab.label,
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
      );
    }
    expect(playerOpens, 1);
    expect(pauseTaps, 1);
    expect(queueOpens, 1);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
