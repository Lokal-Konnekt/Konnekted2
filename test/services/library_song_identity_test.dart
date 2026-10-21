import 'package:flick/models/song.dart';
import 'package:flick/services/link/library_song_identity.dart';
import 'package:flutter_test/flutter_test.dart';

Song song(String id, String title, String path, {String? source}) => Song(
  id: id,
  title: title,
  artist: 'Artist',
  album: 'Album',
  duration: const Duration(minutes: 3),
  fileType: 'FLAC',
  filePath: path,
  sourceType: source,
);
void main() {
  test(
    'history ghosts never count as library files; owned desktop songs remain',
    () {
      final local = song('1', 'Local', '/music/local.flac');
      final duplicate = song('2', 'Local', 'lokal://1/2', source: 'lokal');
      final ghost = song(
        '3',
        'Streamed once',
        'ghost://desktop/1/3',
        source: 'lokal',
      );
      final owned = song('4', 'PC file', 'lokal://1/4', source: 'lokal');
      expect(
        preferLocalLibrarySongs([local, duplicate, ghost, owned])
            .map((s) => s.id),
        ['1', '4'],
      );
    },
  );
}
