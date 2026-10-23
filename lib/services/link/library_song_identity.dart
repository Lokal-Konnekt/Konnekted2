import 'package:flick/features/discovery/recommendation_match.dart'
    show leadArtist, recommendationKey, titleKey;
import 'package:flick/models/song.dart';

/// Linked desktop entries remain in storage for playlist/history identities,
/// but a locally available copy takes precedence in the *displayed library*.
///
/// This is intentionally recording-level, not fuzzy artwork matching: require
/// the same lead artist, normalized recording title and a known duration within
/// two seconds. Featured-artist credit differences must not produce duplicate
/// rows, but live/remix/edit variants must remain separate.
///
/// Server-only music stays visible. Nothing is removed from the database.
List<Song> preferLocalLibrarySongs(List<Song> songs) {
  String? recordingKey(Song song) {
    if (song.duration <= Duration.zero) return null;
    final artist = recommendationKey(leadArtist(song.artist));
    final title = titleKey(song.title);
    if (artist.isEmpty || title.isEmpty) return null;
    return '$artist\u0000$title';
  }

  // Index real phone copies once, rather than comparing every local song to
  // the full desktop catalogue. This is linear for normal library imports.
  final locallyAvailable = <String, List<Song>>{};
  for (final song in songs) {
    if (song.isNetworkSource ||
        song.isPending ||
        song.filePath?.isNotEmpty != true ||
        song.filePath!.startsWith('ghost://')) {
      continue;
    }
    final key = recordingKey(song);
    if (key != null) (locallyAvailable[key] ??= []).add(song);
  }

  bool duplicatedOnPhone(Song desktop) {
    if (desktop.sourceType != 'lokal') return false;
    final key = recordingKey(desktop);
    if (key == null) return false;
    return (locallyAvailable[key] ?? const <Song>[]).any((phone) {
      final sameDuration =
          (phone.duration - desktop.duration).abs() <=
          const Duration(seconds: 2);
      if (!sameDuration) return false;

      // A missing album tag is common in desktop/mobile sync and shouldn't
      // prevent an otherwise strong recording match. Distinct *known* album
      // titles can represent different masters and are kept separate.
      final localAlbum = recommendationKey(phone.album);
      final desktopAlbum = recommendationKey(desktop.album);
      return localAlbum.isEmpty ||
          desktopAlbum.isEmpty ||
          localAlbum == desktopAlbum;
    });
  }

  return [
    for (final song in songs)
      if (!(song.filePath?.startsWith('ghost://') ?? false) &&
          !duplicatedOnPhone(song))
        song,
  ];
}
