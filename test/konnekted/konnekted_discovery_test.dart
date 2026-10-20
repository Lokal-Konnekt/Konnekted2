import 'dart:async';

import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/discovery/lastfm_discovery.dart';
import 'package:flick/features/konnekted/konnekted_data.dart';
import 'package:flick/features/konnekted/konnekted_destination.dart';
import 'package:flick/features/konnekted/konnekted_discovery.dart';
import 'package:flick/features/konnekted/konnekted_discovery_view.dart';
import 'package:flick/features/konnekted/konnekted_home.dart';
import 'package:flick/features/settings/lokal/lokal_settings_group.dart';
import 'package:flick/models/song.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Song _song(
  String id,
  String artist,
  String title, {
  String? album,
  int? track,
}) => Song(
  id: id,
  title: title,
  artist: artist,
  album: album,
  trackNumber: track,
  duration: const Duration(minutes: 3),
  fileType: 'FLAC',
);

final _library = [
  _song(
    '1',
    'Estelle',
    'American Boy (feat. Kanye West)',
    album: 'Shine',
    track: 2,
  ),
  _song('2', 'Estelle', 'Wait a Minute', album: 'Shine', track: 1),
  _song('3', 'Daft Punk', 'One More Time'),
];

/// A Last.fm that recommends one song you have and one you don't.
Future<Map<String, dynamic>> _lastfm(
  String method,
  Map<String, String> params,
) async {
  Map<String, dynamic> track(String artist, String title) => {
    'name': title,
    'artist': {'name': artist},
  };
  return switch (method) {
    'user.getRecentTracks' => {
      'recenttracks': {
        'track': [
          {
            ...track('Daft Punk', 'One More Time'),
            'date': {
              'uts': '${DateTime.now().millisecondsSinceEpoch ~/ 1000 - 60}',
            },
          },
        ],
        '@attr': {'totalPages': '1'},
      },
    },
    'user.getTopTracks' => {
      'toptracks': {'track': []},
    },
    'user.getTopArtists' => {
      'topartists': {
        'artist': [
          {'name': 'Estelle'},
        ],
      },
    },
    'user.getTopAlbums' => {
      'topalbums': {
        'album': [
          {
            'name': 'Shine',
            'artist': {'name': 'Estelle'},
          },
        ],
      },
    },
    'track.getSimilar' => {
      'similartracks': {
        'track': [
          track('Estelle', 'American Boy'),
          track('Nobody', 'Not Here'),
          track('Somebody', 'Elsewhere'),
        ],
      },
    },
    'artist.getSimilar' => {
      'similarartists': {'artist': []},
    },
    'artist.getTopTracks' => {
      'toptracks': {'track': []},
    },
    _ => throw StateError(method),
  };
}

Widget _app(Widget child, {String? account = 'me'}) => ProviderScope(
  overrides: [
    konnektedLibraryProvider.overrideWithValue(AsyncData(_library)),
    konnektedFavoritesProvider.overrideWithValue(const AsyncData([])),
    konnektedRecentSongsProvider.overrideWith((ref) => Stream.value([])),
    konnektedGreetingProvider.overrideWith((ref) => Stream.value('Hello.')),
    konnektedLastfmAccountProvider.overrideWith((ref) async => account),
    konnektedLastfmCallProvider.overrideWithValue(_lastfm),
  ],
  child: MaterialApp(
    theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.dark)),
    home: Scaffold(body: child),
  ),
);

void main() {
  setUp(() {
    forgetLastfmSeeds();
    // Discovery remembers the chosen source in preferences.
    SharedPreferences.setMockInitialValues({});
  });

  test('the library index finds your copy, and albums and artists', () {
    final index = KonnektedLibraryIndex(_library);
    expect(
      index
          .match(
            const LokalDiscoveryTrack(title: 'American Boy', artist: 'Estelle'),
          )
          ?.id,
      '1',
    );
    expect(
      index.match(
        const LokalDiscoveryTrack(title: 'American Boy', artist: 'Someone'),
      ),
      isNull,
    );
    expect(index.album('Shine', 'Estelle').map((s) => s.id), ['2', '1']);
    expect(index.artist('Estelle [feat. Joi]').length, 2);
    expect(
      identical(
        KonnektedLibraryIndex.of(_library),
        KonnektedLibraryIndex.of(_library),
      ),
      isTrue,
    );
  });

  testWidgets('Discovery plays your copy with the shelf, else looks it up', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(412, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final played = <(Song, List<Song>)>[];
    final asked = <String>[];
    await tester.pumpWidget(
      _app(
        SingleChildScrollView(
          child: KonnektedDiscoveryView(
            onNavigate: (_) {},
            onPlay: (song, queue) => played.add((song, queue)),
            findSong: (track, {onStatus, additionalProtectedPaths}) async {
              asked.add(track.title);
              return null;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Fresh Finds'), findsOneWidget);
    expect(find.text('Quick Picks'), findsOneWidget);
    expect(find.text('Scrobble History'), findsOneWidget);
    expect(find.text('Albums For You'), findsOneWidget);
    expect(find.text('Artists For You'), findsOneWidget);

    await tester.tap(
      find.bySemanticsLabel('Play American Boy by Estelle, in your library'),
    );
    expect(played.single.$1.id, '1');
    expect(played.single.$2.map((s) => s.id), ['1']);

    await tester.tap(find.bySemanticsLabel('Play Not Here by Nobody'));
    await tester.pumpAndSettle();
    expect(asked, ['Not Here']);
    expect(find.textContaining('Couldn’t find Not Here'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Play Shine by Estelle'));
    expect(played.last.$2.map((s) => s.id), ['2', '1']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a song you don’t have plays with the shelf queued after it', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(412, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final played = <(Song, List<Song>)>[];
    final asked = <String>[];
    Song placeholder(LokalDiscoveryTrack track) => Song(
      id: 'pending:${track.key}',
      title: track.title,
      artist: track.artist,
      duration: Duration.zero,
      fileType: 'ONLINE',
      sourcePackage: Song.pendingSourcePackage,
    );
    await tester.pumpWidget(
      _app(
        SingleChildScrollView(
          child: KonnektedDiscoveryView(
            onNavigate: (_) {},
            onPlay: (song, queue) => played.add((song, queue)),
            findSong: (track, {onStatus, additionalProtectedPaths}) async {
              asked.add(track.title);
              return Song(
                id: 'discovery:${track.title}',
                title: track.title,
                artist: track.artist,
                duration: Duration.zero,
                fileType: 'M4A',
                filePath: '/cache/${track.title}.m4a',
              );
            },
            pendingSong: placeholder,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Play Not Here by Nobody'));
    await tester.pumpAndSettle();
    // Only the tapped song is fetched now; the others wait in the queue.
    expect(asked, ['Not Here']);
    final (song, queue) = played.single;
    expect(song.id, 'discovery:Not Here');
    expect(queue.map((s) => s.id), contains('1'));
    expect(queue.map((s) => s.id), contains('discovery:Not Here'));
    final waiting = queue.where((s) => s.isPending).map((s) => s.title);
    expect(waiting, ['Elsewhere']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('download progress updates one line in place, then clears', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(412, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final done = Completer<Song?>();
    void Function(String)? say;
    await tester.pumpWidget(
      _app(
        SingleChildScrollView(
          child: KonnektedDiscoveryView(
            onNavigate: (_) {},
            onPlay: (song, queue) {},
            pendingSong: (track) => _song(track.key, track.artist, track.title),
            findSong: (track, {onStatus, additionalProtectedPaths}) {
              say = onStatus;
              return done.future;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Play Not Here by Nobody'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    say!('Getting Not Here from Qobuz… 10%');
    await tester.pump();
    say!('Getting Not Here from Qobuz… 40%');
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Getting Not Here from Qobuz… 40%'), findsOneWidget);
    expect(find.textContaining('10%'), findsNothing);

    done.complete(_song('9', 'Nobody', 'Not Here'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    // A late report from the finished download says nothing.
    say!('Getting Not Here from Qobuz… 90%');
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('add-on progress is said once per change', () {
    final text = SpotiflacProgressText('Song', 'Qobuz');
    expect(text.update(percent: 10), 'Getting Song from Qobuz… 10%');
    expect(text.update(percent: 10.2), isNull);
    expect(
      text.update(message: 'Qobuz loading 10%'),
      'Getting Song from Qobuz… Qobuz loading 10%',
    );
    expect(text.update(message: 'Qobuz loading 10%'), isNull);
    expect(
      text.update(percent: 55, message: 'Decrypting'),
      'Getting Song from Qobuz… Decrypting 55%',
    );
  });

  testWidgets('Discovery fits a narrow screen with large text', (tester) async {
    tester.view
      ..physicalSize = const Size(320, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 2400),
            textScaler: TextScaler.linear(1.5),
          ),
          child: SingleChildScrollView(
            child: KonnektedDiscoveryView(
              onNavigate: (_) {},
              onPlay: (_, _) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Fresh Finds'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without Last.fm, Discovery leads to Online sources', (
    tester,
  ) async {
    final opened = <KonnektedDestination>[];
    await tester.pumpWidget(
      _app(
        SingleChildScrollView(
          child: KonnektedDiscoveryView(
            onNavigate: opened.add,
            onPlay: (_, _) {},
          ),
        ),
        account: null,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Online sources'));
    expect(opened, [
      const KonnektedDestination.settingsAt(
        LokalSettingsGroup.integrations,
        section: LokalOnlineSections.accounts,
      ),
    ]);
  });

  testWidgets('Home switches between Local and Discovery', (tester) async {
    tester.view
      ..physicalSize = const Size(412, 915)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(KonnektedHome(onNavigate: (_) {}, onPlay: (_, _) {})),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Local'), findsOneWidget);
    expect(find.text('Fresh Finds'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Discovery'));
    await tester.pumpAndSettle();
    expect(find.text('Fresh Finds'), findsOneWidget);
    expect(find.text('Open Flow'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Local'));
    await tester.pumpAndSettle();
    expect(find.text('Fresh Finds'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
