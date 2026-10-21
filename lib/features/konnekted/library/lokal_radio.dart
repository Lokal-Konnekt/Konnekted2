import 'package:flick/l10n/l10n.dart';

import 'dart:math';

import 'package:flick/features/konnekted/konnekted_data.dart';
import 'package:flick/models/song.dart';
import 'package:flick/providers/player_provider.dart';
import 'package:flick/providers/songs_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'lokal_genres.dart';
import 'lokal_library_kit.dart';

/// Desktop's radio length.
const lokalRadioMax = 50;

final _featuring = RegExp(r'\s+(feat\.?|ft\.?|featuring|&|,|x)\s+.*$');

String _artistKey(String artist) =>
    lokalGenreKey(artist.toLowerCase().replaceFirst(_featuring, ''));

/// Song or artist radio from your own library, offline.
///
/// Desktop builds its radio from YouTube Music and Last.fm; this keeps to the
/// songs you have: the seed's artist, then songs sharing its genres and era,
/// liked songs a little ahead. At most [lokalRadioMax] songs, the seed first,
/// no more than six by one artist and three from one album, shuffled within
/// how well they match so two radios from one seed differ.
List<Song> buildLokalRadio({
  required List<Song> library,
  Song? seed,
  String? artist,
  Set<String> liked = const {},
  Random? random,
}) {
  assert(seed != null || artist != null);
  final rng = random ?? Random();
  final seedArtist = _artistKey(seed?.artist ?? artist ?? '');
  final seedSongs = seed != null
      ? [seed]
      : [
          for (final song in library)
            if (_artistKey(song.artist) == seedArtist ||
                _artistKey(song.albumArtist ?? '') == seedArtist)
              song,
        ];
  if (seedSongs.isEmpty) return const [];
  final genres = <String>{
    for (final song in seedSongs)
      for (final name in lokalSplitGenres(song.genre)) lokalGenreKey(name),
  };
  final years = [
    for (final song in seedSongs)
      if (song.year != null && song.year! > 0) song.year!,
  ];
  final year = years.isEmpty
      ? null
      : years.reduce((a, b) => a + b) ~/ years.length;

  final scored = <(Song, double)>[];
  for (final song in library) {
    if (song.id == seed?.id) continue;
    var score = 0.0;
    final sameArtist =
        _artistKey(song.artist) == seedArtist ||
        _artistKey(song.albumArtist ?? '') == seedArtist;
    if (sameArtist) score += 3;
    final shared = lokalSplitGenres(song.genre)
        .where((name) => genres.contains(lokalGenreKey(name)))
        .length;
    score += min(shared, 2) * 2;
    if (score == 0) continue;
    if (year != null && song.year != null && song.year! > 0) {
      final gap = (song.year! - year).abs();
      if (gap <= 2) {
        score += 1;
      } else if (gap <= 6) {
        score += .5;
      }
    }
    if (liked.contains(song.id)) score += 1;
    scored.add((song, score + rng.nextDouble() * 2));
  }
  scored.sort((a, b) => b.$2.compareTo(a.$2));

  final perArtist = <String, int>{};
  final perAlbum = <String, int>{};
  final radio = <Song>[?seed];
  final seen = <String>{for (final song in radio) song.id};
  for (final (song, _) in scored) {
    if (radio.length >= lokalRadioMax) break;
    final a = _artistKey(song.artist);
    final album = '${song.album ?? ''}|${song.albumArtist ?? song.artist}';
    final artistCap = seed == null && a == seedArtist ? 12 : 6;
    if ((perArtist[a] ?? 0) >= artistCap) continue;
    if (song.album != null && (perAlbum[album] ?? 0) >= 3) continue;
    if (!seen.add(song.id)) continue;
    perArtist[a] = (perArtist[a] ?? 0) + 1;
    perAlbum[album] = (perAlbum[album] ?? 0) + 1;
    radio.add(song);
  }
  if (seed == null) {
    // An artist radio opens with one of the artist's own songs.
    final first = radio.indexWhere((s) => _artistKey(s.artist) == seedArtist);
    if (first > 0) radio.insert(0, radio.removeAt(first));
  }
  return radio;
}

/// Builds a radio from [seed] (a song) or [artist] and plays it.
///
/// Takes a [context] that outlives the caller (a song's actions sheet closes
/// before the radio starts), and reads providers through its scope.
Future<void> startLokalRadio(
  BuildContext context, {
  Song? seed,
  String? artist,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  var library = container.read(konnektedLibraryProvider).value;
  if (library == null) {
    final sub = container.listen(songsProvider.future, (_, _) {});
    try {
      library = (await sub.read()).songs;
    } finally {
      sub.close();
    }
  }
  final liked = {
    for (final song
        in container.read(konnektedFavoritesProvider).value ?? const <Song>[])
      song.id,
  };
  final radio = buildLokalRadio(
    library: library,
    seed: seed,
    artist: artist,
    liked: liked,
  );
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  if (radio.length < 2) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          lokalText(
            'Not enough similar songs for a radio yet. Radio uses your library’s artists, genres and years.',
          ),
        ),
      ),
    );
    return;
  }
  try {
    await container
        .read(playerProvider.notifier)
        .play(radio.first, playlist: radio);
  } catch (_) {
    messenger.showSnackBar(
      SnackBar(content: Text(lokalText('Couldn’t start this radio.'))),
    );
    return;
  }
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        lokalText(
          "{arg0} Radio: {arg1}",
          args: {
            'arg0': seed?.title ?? artist,
            'arg1': lokalSongCount(radio.length),
          },
        ),
      ),
    ),
  );
}
