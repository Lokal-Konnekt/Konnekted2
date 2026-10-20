import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/konnekted/konnekted_data.dart';
import 'package:flick/features/konnekted/konnekted_destination.dart';
import 'package:flick/features/konnekted/konnekted_dock.dart';
import 'package:flick/features/konnekted/konnekted_home.dart';
import 'package:flick/features/konnekted/konnekted_library.dart';
import 'package:flick/features/konnekted/lokal_mixes.dart';
import 'package:flick/features/settings/lokal/lokal_settings_group.dart';
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

// Lokal glass reads the performance-mode setting, so every pump has a scope.
Widget _app(Widget child, {double scale = 1}) => ProviderScope(
  child: MaterialApp(
    theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.dark)),
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(320, 568),
        textScaler: TextScaler.linear(scale),
        padding: const EdgeInsets.only(top: 24, bottom: 24),
        disableAnimations: true,
      ),
      child: Scaffold(body: child),
    ),
  ),
);

Song _track(String id) => Song(
  id: id,
  title: 'Track $id',
  artist: 'Artist $id',
  duration: const Duration(minutes: 3),
  fileType: 'FLAC',
);

void main() {
  testWidgets('Made for you and Your Mixes play with their own queues', (
    tester,
  ) async {
    final mixes = [
      for (final name in ['Daily Mix', 'New Arrivals', 'Most Played'])
        LokalMix(
          id: name,
          name: name,
          type: LokalMixType.daily,
          tracks: [for (var i = 0; i < 4; i++) _track('$name $i')],
        ),
    ];
    final picks = [
      for (final mix in mixes)
        for (final song in mix.tracks.take(2))
          LokalMadeForYouPick(song: song, mix: mix),
    ];
    final played = <(Song, List<Song>)>[];
    tester.view
      ..physicalSize = const Size(412, 915)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        ListView(
          children: [
            KonnektedMadeForYou(
              picks: picks,
              onPlay: (song, queue) => played.add((song, queue)),
            ),
            KonnektedYourMixes(
              mixes: mixes,
              onPlay: (song, queue) => played.add((song, queue)),
            ),
          ],
        ),
      ),
    );
    expect(find.text('Made for you'), findsOneWidget);
    expect(find.text('DAILY MIX'), findsWidgets);
    await tester.tap(find.text('Track Daily Mix 0'));
    expect(played.single.$1, picks.first.song);
    expect(played.single.$2, [for (final pick in picks) pick.song]);

    await tester.ensureVisible(find.text('Most Played'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Most Played'));
    expect(played.last.$1, mixes[2].tracks.first);
    expect(played.last.$2, mixes[2].tracks);
    expect(find.text('4 songs'), findsNWidgets(3));
  });

  testWidgets('a Cover Flow tap plays that song with the whole shelf queued', (
    tester,
  ) async {
    final recent = [_track('r1'), _track('r2'), _track('r3')];
    Song? played;
    List<Song>? queue;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          konnektedLibraryProvider.overrideWithValue(AsyncData(recent)),
          konnektedRecentSongsProvider.overrideWith(
            (ref) => Stream.value(recent),
          ),
        ],
        child: _app(
          KonnektedCoverFlowSection(
            onPlay: (song, shelf) {
              played = song;
              queue = shelf;
            },
            onOpenFlow: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Track r1'), findsOneWidget);
    final stage = find.bySemanticsLabel(RegExp('^Cover Flow'));
    await tester.tapAt(tester.getCenter(stage) + const Offset(150, 0));
    await tester.pumpAndSettle();
    expect(played?.id, 'r2');
    expect(queue?.map((s) => s.id), ['r1', 'r2', 'r3']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no mixes, no sections', (tester) async {
    await tester.pumpWidget(
      _app(
        Column(
          children: [
            KonnektedMadeForYou(picks: const [], onPlay: (_, _) {}),
            KonnektedYourMixes(mixes: const [], onPlay: (_, _) {}),
          ],
        ),
      ),
    );
    expect(find.text('Made for you'), findsNothing);
    expect(find.text('Your Mixes'), findsNothing);
  });

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
            konnektedGreetingProvider.overrideWith(
              (ref) => Stream.value('Your listening streak has some momentum.'),
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
      expect(
        find.textContaining(RegExp('^Good (morning|afternoon|evening)\$')),
        findsOneWidget,
      );
      expect(
        find.text('Your listening streak has some momentum.'),
        findsOneWidget,
      );
      // Top right opens Settings; the logo, top left, opens Appearance.
      await tester.tap(find.bySemanticsLabel('Settings'));
      await tester.tap(find.bySemanticsLabel('Appearance'));
      expect(find.byTooltip('Settings'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Open Flow'));
      expect(opened, [
        KonnektedDestination.settings,
        const KonnektedDestination.settingsAt(LokalSettingsGroup.appearance),
        KonnektedDestination.flow,
      ]);
      await tester.scrollUntilVisible(find.text('Add your music'), 180);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add your music'));
      expect(
        opened.last,
        const KonnektedDestination.settingsAt(
          LokalSettingsGroup.library,
          section: 'Folders',
        ),
      );
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
        const KonnektedDestination.settingsAt(
          LokalSettingsGroup.library,
          section: 'Folders',
        ),
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
      await tester.tap(find.bySemanticsLabel(tab.label));
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

  Widget dock({
    required KonnektedTab selected,
    required ValueChanged<KonnektedTab> onSelect,
    bool collapsed = false,
    VoidCallback? onExpand,
  }) => Align(
    alignment: Alignment.bottomCenter,
    child: KonnektedDock(
      selected: selected,
      onSelect: onSelect,
      collapsed: collapsed,
      onExpand: onExpand,
      miniPlayer: KonnektedMiniPlayerContent(
        song: _song,
        isPlaying: false,
        onOpen: () {},
        onPlayPause: () {},
        onNext: () {},
        onQueue: () {},
        progress: const SizedBox.shrink(),
      ),
    ),
  );

  testWidgets('dragging the lens across the tab capsule picks a tab', (
    tester,
  ) async {
    var selected = KonnektedTab.listen;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) => dock(
            selected: selected,
            onSelect: (tab) => setState(() => selected = tab),
          ),
        ),
      ),
    );
    final home = tester.getCenter(find.bySemanticsLabel('Home'));
    final you = tester.getCenter(find.bySemanticsLabel('You'));
    final gesture = await tester.startGesture(home);
    await gesture.moveBy(const Offset(20, 0));
    await gesture.moveTo(you);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(selected, KonnektedTab.settings);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolled-down dock tucks the mini player between circles', (
    tester,
  ) async {
    var expands = 0;
    var collapsed = false;
    late StateSetter set;
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return dock(
              selected: KonnektedTab.library,
              onSelect: (_) {},
              collapsed: collapsed,
              onExpand: () => expands++,
            );
          },
        ),
      ),
    );
    final openHeight = tester.getSize(find.byType(KonnektedDock)).height;
    expect(find.byTooltip('Open queue'), findsOneWidget);

    set(() => collapsed = true);
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(KonnektedDock)).height,
      lessThan(openHeight),
    );
    // The hidden tabs leave the semantics tree; the shrunken capsule stays.
    expect(find.bySemanticsLabel('Home'), findsNothing);
    expect(find.byTooltip('Open queue'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Open player for')), findsOneWidget);
    expect(find.bySemanticsLabel('Search'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Show tabs. Library'));
    expect(expands, 1);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('dock without a song is one row and never collapses', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        Align(
          alignment: Alignment.bottomCenter,
          child: KonnektedDock(
            selected: KonnektedTab.explore,
            onSelect: (_) {},
            hasMiniPlayer: false,
            collapsed: true,
            miniPlayer: const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(KonnektedDock)).height,
      KonnektedDock.reservedHeight(hasMiniPlayer: false, systemInset: 24),
    );
    expect(find.bySemanticsLabel('Home'), findsOneWidget);
  });
}
