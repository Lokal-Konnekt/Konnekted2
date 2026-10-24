import 'package:flutter_test/flutter_test.dart';
import 'package:flick/services/link/link_playlist_order.dart';

Map<String, dynamic> op(
  String kind,
  String key,
  int clock, {
  Object? position,
  String? name,
}) => {
  'op': kind,
  'hlc': '${clock.toString().padLeft(16, '0')}:00000000',
  'device_id': 'desktop-1',
  'op_id': 'op-$clock',
  'fields': {
    if (key.isNotEmpty) 'track_key': key,
    if (position != null) 'position': position,
    if (name != null) 'name': name,
  },
};

void main() {
  test('desktop numeric positions beat alphabetic song titles', () {
    final state = LinkPlaylistOrder.replay([
      op('playlist.create', '', 1, name: 'Driving'),
      op('playlist.add', 'a-song', 2, position: 2),
      op('playlist.add', 'z-song', 3, position: 0),
      op('playlist.add', 'm-song', 4, position: 1),
    ]);
    expect(state.name, 'Driving');
    expect(state.deleted, isFalse);
    expect(state.members.map((e) => e.trackKey),
        ['z-song', 'm-song', 'a-song']);
  });

  test('legacy equal/missing positions retain arrival order, never title order', () {
    final state = LinkPlaylistOrder.replay([
      op('playlist.create', '', 1, name: 'Old sync'),
      op('playlist.add', 'z-track', 2, position: 0),
      op('playlist.add', 'b-track', 3, position: 0),
      op('playlist.add', 'a-track', 4, position: 0),
      op('playlist.add', 'unspecified', 5),
    ]);
    expect(state.members.map((e) => e.trackKey),
        ['z-track', 'b-track', 'a-track', 'unspecified']);
  });

  test('moves override positions and remove eliminates the member', () {
    final state = LinkPlaylistOrder.replay([
      op('playlist.add', 'a', 1, position: 0),
      op('playlist.add', 'b', 2, position: 1),
      op('playlist.add', 'c', 3, position: 2),
      op('playlist.move', 'a', 4, position: 4),
      op('playlist.remove', 'b', 5),
    ]);
    expect(state.members.map((e) => e.trackKey), ['c', 'a']);
  });

  test('a string position from legacy journal is treated as numeric', () {
    final state = LinkPlaylistOrder.replay([
      op('playlist.add', 'A', 1, position: '10'),
      op('playlist.add', 'Z', 2, position: '2'),
    ]);
    expect(state.members.map((e) => e.trackKey), ['Z', 'A']);
  });

  test('replay does not depend on page or operation input order', () {
    final rows = [
      op('playlist.create', '', 1, name: 'Imported'),
      op('playlist.add', 'track3', 3, position: 3),
      op('playlist.add', 'track1', 2, position: 1),
    ];
    expect(LinkPlaylistOrder.replay(rows.reversed).members.map((e) => e.trackKey),
        ['track1', 'track3']);
  });

  test('delete and recreation do not resurrect stale members', () {
    final state = LinkPlaylistOrder.replay([
      op('playlist.create', '', 1, name: 'First'),
      op('playlist.add', 'old', 2, position: 0),
      op('playlist.delete', '', 3),
      op('playlist.create', '', 4, name: 'New'),
      op('playlist.add', 'fresh', 5, position: 0),
    ]);
    expect(state.name, 'New');
    expect(state.deleted, isFalse);
    expect(state.members.map((e) => e.trackKey), ['fresh']);
  });

  test('negative and fractional positions preserve genuine manual order', () {
    final state = LinkPlaylistOrder.replay([
      op('playlist.add', 'middle', 1, position: 1.5),
      op('playlist.add', 'first', 2, position: -0.5),
      op('playlist.add', 'last', 3, position: 3),
    ]);
    expect(state.members.map((e) => e.trackKey), ['first', 'middle', 'last']);
  });
}
