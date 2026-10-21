import 'package:flick/models/song.dart';

/// A synced desktop placeholder stays in storage for playlist/history references,
/// but should not duplicate the same recording already available on the phone.
List<Song> preferLocalLibrarySongs(List<Song> songs) {
  String normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  String key(Song song) =>
      '${normalize(song.artist)}|${normalize(song.title)}|${normalize(song.album ?? '')}';
  final local = <String, List<Song>>{};
  for (final song in songs) {
    if (!song.isNetworkSource &&
        !song.isPending &&
        song.filePath?.isNotEmpty == true &&
        song.duration > Duration.zero) {
      (local[key(song)] ??= []).add(song);
    }
  }
  return [
    for (final song in songs)
      if (!(song.filePath?.startsWith('ghost://') ?? false) &&
          (song.sourceType != 'lokal' ||
              song.duration <= Duration.zero ||
              !(local[key(song)] ?? const <Song>[]).any(
                (candidate) =>
                    (candidate.duration - song.duration).abs() <=
                    const Duration(seconds: 2),
              )))
        song,
  ];
}
