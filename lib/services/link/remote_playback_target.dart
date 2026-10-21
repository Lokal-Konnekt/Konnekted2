import '../../models/song.dart';

/// The UI can drive a target without claiming it is the local native engine.
abstract interface class RemotePlaybackTarget {
  String get outputName;
  Future<void> play(Song song, {List<Song>? queue});
  Future<void> pause();
  Future<void> resume();
  Future<void> seek(Duration position);
  Future<void> next();
  Future<void> previous();
  Future<void> setVolume(double value);
  Future<void> removeFromQueue(int index);
  Future<void> reorderQueue(int from, int to);
}

class DesktopPlaybackTarget implements RemotePlaybackTarget {
  DesktopPlaybackTarget({required this.outputName, required this.command});
  @override
  final String outputName;
  final Future<void> Function(String, Object?) command;
  Map<String, dynamic> _track(Song song) => {
    'id': song.sourceType == 'lokal' ? song.remoteId : song.id,
    'title': song.title,
    'artist': song.artist,
    'album': song.album ?? '',
    'duration': song.duration.inMilliseconds / 1000,
  };
  @override
  Future<void> play(Song song, {List<Song>? queue}) {
    final songs = queue ?? [song],
        index = (queue ?? [song]).indexWhere((entry) => entry.id == song.id);
    return command('handoff', {
      'queue': songs.map(_track).toList(),
      'index': index < 0 ? 0 : index,
      'positionMs': 0,
    });
  }

  @override
  Future<void> pause() => command('pause', null);
  @override
  Future<void> resume() => command('play', null);
  @override
  Future<void> seek(Duration position) =>
      command('seek', position.inMilliseconds / 1000);
  @override
  Future<void> next() => command('next', null);
  @override
  Future<void> previous() => command('prev', null);
  @override
  Future<void> setVolume(double value) => command('volume', value);
  @override
  Future<void> removeFromQueue(int index) =>
      command('removeFromQueue', {'index': index});
  @override
  Future<void> reorderQueue(int from, int to) =>
      command('reorderQueue', {'from': from, 'to': to});
  Future<void> addToQueue(Song song) =>
      command('queueFromMetadata', {'track': _track(song)});
}
