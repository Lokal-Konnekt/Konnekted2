import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/data/repositories/recently_played_repository.dart';
import 'package:flick/features/konnekted/konnekted_destination.dart';
import 'package:flick/features/konnekted/konnekted_you.dart';
import 'package:flick/features/settings/lokal/lokal_settings_group.dart';
import 'package:flick/models/song.dart';
import 'package:flick/services/milestone_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _song = Song(
  id: '1',
  title: 'Midnight City',
  artist: 'M83',
  duration: Duration(minutes: 4),
  fileType: 'FLAC',
);

ListeningRecap _recap(ListeningRecapPeriod period, {int plays = 12}) {
  final now = DateTime(2026, 10, 20, 21);
  final range = period.rangeFor(now);
  return ListeningRecap(
    period: period,
    start: range.start,
    endExclusive: range.endExclusive,
    totalPlays: plays,
    totalListeningTime: Duration(minutes: plays * 4),
    uniqueSongs: 1,
    uniqueArtists: 1,
    activeDays: 2,
    peakHour: 21,
    topSong: null,
    topArtist: RankedRecapArtist(
      artist: 'M83',
      plays: plays,
      uniqueSongs: 1,
      listeningTime: Duration(minutes: plays * 4),
      lastPlayedAt: now,
    ),
    topAlbum: null,
    topSongs: [
      RankedRecapSong(
        song: _song,
        plays: plays,
        listeningTime: Duration(minutes: plays * 4),
        lastPlayedAt: now,
      ),
    ],
    topArtists: [
      RankedRecapArtist(
        artist: 'M83',
        plays: plays,
        uniqueSongs: 1,
        listeningTime: Duration(minutes: plays * 4),
        lastPlayedAt: now,
      ),
    ],
    topAlbums: const [],
  );
}

Widget _app({
  required ValueChanged<KonnektedDestination> onNavigate,
  Map<ListeningRecapPeriod, ListeningRecap> recaps = const {},
  YouAccounts accounts = const YouAccounts(),
  int? streak,
  List<MilestoneRecord> milestones = const [],
}) => ProviderScope(
  overrides: [
    youRecapsProvider.overrideWith((ref) => Stream.value(recaps)),
    youAccountsProvider.overrideWithValue(accounts),
    youStreakProvider.overrideWith((ref) async => streak),
    youMilestonesProvider.overrideWith((ref) async => milestones),
  ],
  child: MaterialApp(
    theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.dark)),
    home: MediaQuery(
      data: const MediaQueryData(
        size: Size(390, 2400),
        padding: EdgeInsets.only(top: 24, bottom: 24),
        disableAnimations: true,
      ),
      child: Scaffold(body: KonnektedYou(onNavigate: onNavigate)),
    ),
  ),
);

void _tall(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(390, 2400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('empty: a default name, placeholders and no badges', (
    tester,
  ) async {
    _tall(tester);
    await tester.pumpWidget(_app(onNavigate: (_) {}));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('MINUTES THIS WEEK'), findsOneWidget);
    expect(find.text('DAY STREAK'), findsNothing);
    expect(find.text('RECAP'), findsOneWidget);
    for (final period in ['WEEK', 'MONTH', 'YEAR']) {
      expect(find.text(period), findsOneWidget);
    }
    expect(find.text('Nothing yet'), findsNWidgets(3));
    expect(find.text('No badges yet'), findsOneWidget);
    expect(find.text('CONNECTED'), findsNothing);
    expect(find.text('CONNECT'), findsNWidgets(3));
    // The old You rows are gone; Settings covers them.
    expect(find.text('Equalizer'), findsNothing);
    expect(find.text('Appearance'), findsNothing);
  });

  testWidgets('populated: name, minutes, streak, stats, badges, accounts', (
    tester,
  ) async {
    _tall(tester);
    await tester.pumpWidget(
      _app(
        onNavigate: (_) {},
        recaps: {
          for (final p in youRecapPeriods)
            p: _recap(
              p,
              plays: switch (p) {
                ListeningRecapPeriod.weekly => 12,
                ListeningRecapPeriod.monthly => 40,
                _ => 300,
              },
            ),
        },
        accounts: const YouAccounts(lastFm: 'gustave', youtubeMusic: true),
        streak: 6,
        milestones: [
          MilestoneRecord(
            type: MilestoneType.songs100,
            achievedAt: DateTime(2026, 10, 1),
          ),
        ],
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('gustave'), findsOneWidget);
    expect(find.text('G'), findsOneWidget);
    // 12 plays × 4 minutes this week, in the header and the stats.
    expect(find.text('48'), findsNWidgets(2));
    expect(find.text('6'), findsOneWidget);
    expect(find.text('48 min'), findsOneWidget);
    expect(find.text('1,200 min'), findsOneWidget);
    expect(find.text('9:00 PM'), findsOneWidget);
    expect(find.text('Midnight City'), findsOneWidget);
    expect(find.text('100 songs'), findsOneWidget);
    expect(find.text('CONNECTED'), findsNWidgets(2));
    expect(find.text('CONNECT'), findsOneWidget);

    // The stats follow the segmented control.
    await tester.tap(find.text('Month'));
    await tester.pump();
    expect(find.text('160'), findsOneWidget);
  });

  testWidgets('the gear, chips and rows open Settings where they belong', (
    tester,
  ) async {
    _tall(tester);
    final semantics = tester.ensureSemantics();
    final opened = <KonnektedDestination>[];
    await tester.pumpWidget(_app(onNavigate: opened.add));
    await tester.pump();

    await tester.tap(find.byTooltip('Settings'));
    await tester.tap(find.bySemanticsLabel('Last.fm, not connected'));
    await tester.tap(find.bySemanticsLabel('ListenBrainz, not connected'));
    await tester.tap(find.bySemanticsLabel('YouTube Music, not connected'));
    await tester.tap(find.text('Full history'));
    await tester.tap(find.text('Help'));
    await tester.tap(find.text('About'));
    await tester.pump();

    semantics.dispose();

    const scrobbling = KonnektedDestination.settingsAt(
      LokalSettingsGroup.data,
      section: LokalDataSections.accounts,
    );
    expect(opened, [
      KonnektedDestination.settings,
      scrobbling,
      scrobbling,
      const KonnektedDestination.settingsAt(
        LokalSettingsGroup.data,
        section: LokalDataSections.accounts,
      ),
      KonnektedDestination.recentlyPlayed,
      const KonnektedDestination.settingsAt(
        LokalSettingsGroup.about,
        section: 'Help',
      ),
      const KonnektedDestination.settingsAt(
        LokalSettingsGroup.about,
        section: 'About',
      ),
    ]);
  });

  test('the name is an account username, else "You"', () {
    expect(const YouAccounts().name, 'You');
    expect(const YouAccounts(lastFm: '  ').name, 'You');
    expect(const YouAccounts(listenBrainz: 'lb').name, 'lb');
    expect(const YouAccounts(lastFm: 'fm', listenBrainz: 'lb').name, 'fm');
  });
}
