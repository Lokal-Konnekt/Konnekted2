import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/song.dart';
import '../../providers/player_provider.dart';
import '../../providers/playlist_provider.dart';
import 'domain/flow_models.dart';
import 'flow_library.dart';
import 'flow_playback.dart';
import 'flow_store.dart';

final flowStoreProvider = FutureProvider<FlowStore>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return FlowStore(
    read: () async => prefs.getString(FlowStore.preferenceKey),
    write: (text) => prefs.setString(FlowStore.preferenceKey, text),
  );
});

final flowMessageProvider = NotifierProvider<FlowMessage, String?>(
  FlowMessage.new,
);

class FlowMessage extends Notifier<String?> {
  @override
  String? build() => null;
  void show(String? message) => state = message;
}

// Intentionally kept alive after the screen is first opened: queue growth and
// real player observations continue when the user visits another screen.
final flowControllerProvider = AsyncNotifierProvider<FlowController, FlowData>(
  FlowController.new,
);

class FlowController extends AsyncNotifier<FlowData> {
  late FlowStore _store;
  Future<void> _pending = Future.value();
  String? _lastStartedId;
  bool _growthScheduled = false;
  String? _lastGrowthAttempt;

  @override
  Future<FlowData> build() async {
    _store = await ref.watch(flowStoreProvider.future);
    final data = await _store.load();
    if (!ref.mounted) return data;
    ref.listen(playerProvider, (_, next) => _observe(next));
    return data;
  }

  Future<void> _serialize(Future<void> Function() action) {
    final result = _pending.then((_) async {
      if (!ref.mounted) return;
      await action();
    });
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> _commit(FlowData data) async {
    await _store.save(data);
    if (ref.mounted) state = AsyncData(data);
  }

  void _background(Future<void> operation) {
    unawaited(
      operation.catchError((Object error) {
        if (ref.mounted) {
          ref
              .read(flowMessageProvider.notifier)
              .show('Flow could not update: $error');
        }
      }),
    );
  }

  void _observe(PlayerState player) {
    final song = player.currentSong;
    if (state.value == null || !player.isPlaying || song == null) return;
    if (_lastStartedId != song.id &&
        !song.isExternal &&
        !song.isNetworkSource) {
      _lastStartedId = song.id;
      _background(
        _serialize(() async {
          final data = state.requireValue;
          final session = data.session;
          await _commit(
            data.copyWith(
              recentIds: [song.id, ...data.recentIds],
              session: FlowSession(
                trackIds: session.trackIds,
                seed: session.seed,
                builtAtMs: session.builtAtMs,
                currentId:
                    ref.read(flowPlaybackProvider).ownsSession(session.seed) &&
                        session.trackIds.contains(song.id)
                    ? song.id
                    : session.currentId,
              ),
            ),
          );
        }),
      );
    }
    final playback = ref.read(flowPlaybackProvider);
    final session = state.requireValue.session;
    final growthKey = '${session.seed}:${song.id}:${session.trackIds.length}';
    if (!_growthScheduled &&
        player.upNext.isEmpty &&
        session.trackIds.contains(song.id) &&
        _lastGrowthAttempt != growthKey &&
        playback.ownsSession(session.seed)) {
      _growthScheduled = true;
      _lastGrowthAttempt = growthKey;
      _background(
        grow(onlyWhenLast: true).whenComplete(() {
          _growthScheduled = false;
        }),
      );
    }
  }

  FlowData _newSession(
    FlowLibrary library,
    FlowData data, {
    FlowConfig? config,
  }) {
    final next = data.copyWith(
      config: config,
      session: FlowSession(seed: (data.session.seed + 1) & 0x7fffffff),
    );
    final now = DateTime.now();
    final songs = library.mix(next, now);
    return next.copyWith(
      session: FlowSession(
        trackIds: songs.map((song) => song.id),
        seed: next.session.seed,
        builtAtMs: now.millisecondsSinceEpoch,
      ),
    );
  }

  /// Apply persists a fresh preview, but never restarts audio under a slider.
  Future<void> apply(FlowConfig config) => _serialize(() async {
    final library = await ref.read(flowLibraryProvider.future);
    await _commit(_newSession(library, state.requireValue, config: config));
  });

  Future<void> newMix() => _serialize(() async {
    final library = await ref.read(flowLibraryProvider.future);
    await _commit(_newSession(library, state.requireValue));
  });

  Future<void> play({
    String? songId,
    bool shuffle = false,
  }) => _serialize(() async {
    final library = await ref.read(flowLibraryProvider.future);
    var data = state.requireValue;
    if (shuffle) data = _newSession(library, data);
    final songs = library.mix(data, DateTime.now());
    if (songs.isEmpty) {
      throw StateError('No eligible local tracks in this Flow.');
    }
    final target = songId ?? data.session.currentId;
    final first = songs.where((s) => s.id == target).firstOrNull ?? songs.first;
    data = data.copyWith(
      session: FlowSession(
        trackIds: songs.map((s) => s.id),
        seed: data.session.seed,
        builtAtMs: DateTime.now().millisecondsSinceEpoch,
        currentId: first.id,
      ),
    );
    await _commit(data);
    await ref.read(flowPlaybackProvider).play(songs, first, data.session.seed);
  });

  /// Host addToQueue inserts immediately after the current track. Grow only
  /// at the last track to append safely without replacing playback or seeking.
  Future<void> grow({bool onlyWhenLast = false}) => _serialize(() async {
    final playback = ref.read(flowPlaybackProvider);
    var data = state.requireValue;
    final active = playback.ownsSession(data.session.seed);
    if (onlyWhenLast &&
        (!active ||
            !playback.state.isPlaying ||
            playback.state.upNext.isNotEmpty)) {
      return;
    }
    if (active && playback.state.upNext.isNotEmpty) return;
    final library = await ref.read(flowLibraryProvider.future);
    if (data.session.trackIds.isEmpty ||
        (!active && !data.session.isFresh(DateTime.now()))) {
      data = _newSession(library, data);
    }
    final extra = library.topUp(data);
    if (extra.isEmpty) return;
    // Persist the plan before touching the player. If a platform append fails,
    // a retry cannot accidentally enqueue the successfully appended prefix twice.
    await _commit(
      data.copyWith(
        session: FlowSession(
          trackIds: [...data.session.trackIds, ...extra.map((song) => song.id)],
          seed: data.session.seed,
          builtAtMs: data.session.builtAtMs,
          currentId: data.session.currentId,
        ),
      ),
    );
    for (final song in extra) {
      if (active) {
        if (!playback.ownsSession(data.session.seed)) break;
        await playback.append(song);
      }
    }
  });

  Future<void> ban(Song song) => _serialize(() async {
    final data = state.requireValue;
    final library = await ref.read(flowLibraryProvider.future);
    final recording = library.tracks.where((s) => s.id == song.id).firstOrNull;
    final ids = {
      song.id,
      if (recording != null)
        ...library.tracks
            .where((s) => s.recordingKey == recording.recordingKey)
            .map((s) => s.id),
    };
    final bans = {...data.bannedIds, ...ids};
    if (bans.length > FlowRules.maxBans) {
      throw StateError('Remove a Flow ban before adding another.');
    }
    await _commit(data.copyWith(bannedIds: bans));
    final playback = ref.read(flowPlaybackProvider);
    if (playback.ownsSession(data.session.seed)) {
      await playback.removeUpcoming(ids);
      if (ids.contains(playback.state.currentSong?.id)) await playback.next();
    }
  });

  Future<void> unban(String id) => _serialize(() async {
    final data = state.requireValue;
    await _commit(data.copyWith(bannedIds: {...data.bannedIds}..remove(id)));
  });

  /// Count only an explicit Flow Skip tap, never a natural track transition.
  Future<void> skip() => _serialize(() async {
    final playback = ref.read(flowPlaybackProvider);
    final data = state.requireValue;
    final id = playback.state.currentSong?.id;
    if (id == null || !playback.ownsSession(data.session.seed)) return;
    final skips = {...data.skipCounts}..remove(id);
    skips[id] = ((data.skipCounts[id] ?? 0) + 1).clamp(1, 1000);
    while (skips.length > FlowRules.maxSignals) {
      skips.remove(skips.keys.first);
    }
    await _commit(data.copyWith(skipCounts: skips));
    await playback.next();
  });

  Future<void> savePlaylist(String name) => _serialize(() async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Enter a playlist name.');
    final library = await ref.read(flowLibraryProvider.future);
    final songs = library.mix(state.requireValue, DateTime.now());
    if (songs.isEmpty) throw StateError('There are no tracks to save.');
    final service = ref.read(playlistServiceProvider);
    final playlist = await service.createPlaylist(trimmed);
    if (playlist == null) {
      throw StateError('That playlist name is already in use.');
    }
    try {
      final saved = await service.updatePlaylist(
        playlist.copyWith(
          songIds: songs.map((s) => s.id).toList(),
          songAddedAt: {for (final song in songs) song.id: DateTime.now()},
        ),
      );
      if (saved == null) throw StateError('Could not save the Flow tracks.');
    } catch (_) {
      await service.deletePlaylist(playlist.id);
      rethrow;
    } finally {
      if (ref.mounted) ref.invalidate(playlistsProvider);
    }
  });
}
