import '../milestone_service.dart';
import '../local_metadata_repair.dart';
import '../../models/song.dart';

import 'dart:convert';

import 'package:isar_community/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/database.dart';
import '../../data/repositories/recently_played_repository.dart';
import '../../data/repositories/song_repository.dart';
import '../../models/lokal_remote_state.dart';
import '../../models/playlist.dart';
import '../favorites_service.dart';
import '../playlist_service.dart';
import 'link_journal.dart';
import 'link_profile_service.dart';
import 'lokal_desktop_source.dart';
import 'lokal_link_service.dart';

/// Symmetric, cursor-based merge. Only explicit operations remove playlist items;
/// a missing desktop row can never delete a phone file, like, or playlist.
class LinkSyncCoordinator {
  LinkSyncCoordinator({
    required this.socket,
    required this.credentials,
    required this.favorites,
    this.onChanged,
    this.onProfileChanged,
    this.onProgress,
    this.initialProgress = const LinkSyncProgress(),
  });
  final LokalLinkService socket;
  final LokalRemoteCredentials credentials;
  final FavoritesService favorites;
  final void Function()? onChanged;
  final void Function()? onProfileChanged;
  final void Function(LinkSyncProgress)? onProgress;
  final LinkSyncProgress initialProgress;
  late LinkSyncProgress _progress = initialProgress;
  Future<void>? _active;
  List<Song>? _matchCandidates;
  final _matchCache = <String, Song?>{};
  bool get busy => _active != null;

  Future<Song?> _match(Map<String, dynamic> track) async {
    final key = track['track_key']?.toString();
    if (key != null && _matchCache.containsKey(key)) return _matchCache[key];
    final song = await LinkJournal.instance.match(
      track,
      candidates: _matchCandidates,
    );
    if (key != null) _matchCache[key] = song;
    return song;
  }

  static String prefixFor(LokalRemoteCredentials value) =>
      'lokal.link.${value.desktopId}.user.${value.desktopUserId ?? 'guest'}';
  String get _prefix => prefixFor(credentials);
  Future<void> enableMerge() async {
    final active = _active;
    if (active != null) await active;
    await _run(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_prefix.merge', true);
      final ids = (prefs.getStringList('favorite_song_ids') ?? []).toSet();
      await LinkJournal.instance.captureFavorites(ids);
      await LinkJournal.instance.capturePlaylists(
        await PlaylistService.instance.getPlaylists(),
      );
      await _synchronize(importCatalog: true);
    });
  }

  void _report(
    LinkSyncPhase phase, {
    int processed = 0,
    int? total,
    int? catalogSongs,
    DateTime? completedAt,
  }) {
    _progress = LinkSyncProgress(
      phase: phase,
      processed: processed,
      total: total,
      catalogSongs: catalogSongs ?? _progress.catalogSongs,
      completedAt: completedAt ?? _progress.completedAt,
    );
    onProgress?.call(_progress);
  }

  void _requireReady() {
    if (!socket.connected) throw StateError('Desktop link disconnected.');
    if (!Database.isInitialized)
      throw StateError('The music library is not ready.');
  }

  Future<void> _run(Future<void> Function() action) {
    final active = _active;
    if (active != null) return active;
    final task = _execute(action);
    _active = task;
    return task.whenComplete(() {
      if (identical(_active, task)) _active = null;
    });
  }

  Future<void> _execute(Future<void> Function() action) async {
    _report(LinkSyncPhase.preparing);
    try {
      _requireReady();
      await action();
      _requireReady();
      final completedAt = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        '$_prefix.last_sync',
        completedAt.millisecondsSinceEpoch,
      );
      if (_progress.catalogSongs case final count?) {
        await prefs.setInt('$_prefix.catalog_songs', count);
      }
      _report(LinkSyncPhase.complete, completedAt: completedAt);
    } catch (_) {
      _report(
        LinkSyncPhase.paused,
        processed: _progress.processed,
        total: _progress.total,
      );
      rethrow;
    } finally {
      _matchCandidates = null;
      _matchCache.clear();
    }
  }

  Future<void> _backfillHistory() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('lokal.link.history_backfilled') == true) return;
    final device = await LinkJournal.instance.deviceId();
    final rows = await Database.recentlyPlayed
        .filter()
        .eventIdIsNull()
        .findAll();
    final songs = {
      for (final song in await SongRepository().getAllSongs()) song.id: song,
    };
    for (final row in rows) {
      final song = songs[row.songId.toString()];
      if (song == null) continue;
      final id = 'mobile_${device}_${row.id}';
      // Legacy history retained song duration, not measured listen time. Keep
      // that existing estimate rather than inventing a new historic measurement.
      await LinkJournal.instance.recordPlay(
        eventId: id,
        songId: song.id,
        playedAt: row.playedAt.millisecondsSinceEpoch,
        msPlayed: row.listenedMs ?? song.duration.inMilliseconds,
      );
      row.eventId = id;
      await Database.instance.writeTxn(() => Database.recentlyPlayed.put(row));
    }
    await prefs.setBool('lokal.link.history_backfilled', true);
  }

  Future<void> synchronize({bool importCatalog = false}) async {
    final active = _active;
    if (active != null) return active;
    if (!socket.connected || !Database.isInitialized) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('$_prefix.merge') != true) return;
    await _run(() => _synchronize(importCatalog: importCatalog));
  }

  Future<void> _synchronize({required bool importCatalog}) async {
    final prefs = await SharedPreferences.getInstance();
    final source = LokalDesktopSource.instance,
        server = await LokalDesktopSource.instance.ensureServer(credentials);
    if (importCatalog ||
        prefs.getBool('$_prefix.catalog') != true ||
        prefs.getBool('$_prefix.owned_catalog_v2') != true) {
      _report(LinkSyncPhase.catalog);
      await for (final progress in source.syncLibrary(server)) {
        _requireReady();
        _report(
          LinkSyncPhase.catalog,
          processed: progress.filesProcessed,
          total: progress.totalFiles,
          catalogSongs: progress.totalFiles,
        );
      }
      await prefs.setBool('$_prefix.catalog', true);
      await prefs.setBool('$_prefix.owned_catalog_v2', true);
      onChanged?.call();
    }
    await LocalMetadataRepair.instance.repairDesktopCopies(
      onProgress: (done, total) {
        _report(LinkSyncPhase.metadata, processed: done, total: total);
      },
    );
    _report(LinkSyncPhase.lyrics);
    await source.syncCopiedLyrics(
      server,
      stillCurrent: () => socket.connected,
      onProgress: (done, total) =>
          _report(LinkSyncPhase.lyrics, processed: done, total: total),
    );
    _requireReady();
    _matchCandidates = List<Song>.of(await SongRepository().getAllSongs());
    for (final kind in ['library', 'history']) {
      if (kind == 'history') await _backfillHistory();
      _requireReady();
      final phase = kind == 'history'
          ? LinkSyncPhase.history
          : LinkSyncPhase.library;
      var processed = 0;
      _report(phase);
      final pushKey = '$_prefix.$kind.push';
      while (socket.connected) {
        final cursor = prefs.getInt(pushKey) ?? 0;
        final batch = kind == 'history'
            ? await LinkJournal.instance.historyAfter(cursor)
            : await LinkJournal.instance.libraryAfter(cursor);
        final items = batch['items'] as List;
        if (items.isEmpty) break;
        await socket.request('$kind.push', {'items': items});
        processed += items.length;
        _report(phase, processed: processed);
        await prefs.setInt(pushKey, batch['cursor'] as int);
        if (batch['hasMore'] != true) break;
      }
      final pullKey = '$_prefix.$kind.pull';
      while (socket.connected) {
        final reply = await socket.request('$kind.pull', {
          'cursor': prefs.getInt(pullKey) ?? 0,
        });
        final items = reply.body['items'];
        if (items is! List || reply.body['cursor'] is! int)
          throw const FormatException('Invalid desktop sync page.');
        if (kind == 'history') {
          final added = await LinkJournal.instance.mergeHistory(items);
          for (final item in added) {
            var song = await _match(item);
            // History is not ownership: retain the play event in the journal,
            // but never create a library song just because it was streamed.
            if (song != null)
              await RecentlyPlayedRepository().recordPlay(
                song.id,
                eventId: item['event_id'] as String,
                playedAt: DateTime.fromMillisecondsSinceEpoch(
                  item['played_at'] as int,
                ),
                listenedMs: item['ms_played'] as int,
              );
          }
        } else {
          final added = await LinkJournal.instance.mergeLibrary(items);
          if (added.isNotEmpty) {
            await _materializeLibraryPage(added);
            onChanged?.call();
          }
        }
        await prefs.setInt(pullKey, reply.body['cursor'] as int);
        processed += items.length;
        _report(phase, processed: processed);
        if (reply.body['hasMore'] != true) break;
      }
    }
    _requireReady();
    _report(LinkSyncPhase.finalizing);
    await LinkProfileService.sync(credentials);
    onProfileChanged?.call();
    MilestoneService.changes.add(null);
  }

  Future<void> _materializeLibraryPage(List<Map<String, dynamic>> items) async {
    final playlists = <String, Map<String, dynamic>>{};
    final likes = <String, bool>{};
    for (final item in items) {
      if (item['entity'] == 'playlist') {
        playlists[item['entity_id'] as String] = item;
      } else if (item['entity'] == 'like') {
        if (!await LinkJournal.instance.wins(item, 'liked')) continue;
        final song = await _match({
          ...Map<String, dynamic>.from(item['fields'] as Map),
          'track_key': item['entity_id'],
        });
        if (song != null) likes[song.id] = item['op'] == 'like';
      } else {
        await _materialize(item);
      }
    }
    if (likes.isNotEmpty) await favorites.setManyFromLink(likes);
    // mergeLibrary has already persisted every operation in this page. One
    // replay per playlist produces the same state as replaying it per member.
    for (final item in playlists.values) {
      await _materialize(item);
    }
  }

  Future<void> _materialize(Map<String, dynamic> item) async {
    final journal = LinkJournal.instance,
        fields = Map<String, dynamic>.from(item['fields'] as Map);
    switch (item['entity']) {
      case 'like':
        if (!await journal.wins(item, 'liked')) return;
        final song = await _match({...fields, 'track_key': item['entity_id']});
        if (song != null)
          await favorites.setFromLink(song.id, item['op'] == 'like');
        break;
      case 'playlist':
        final id = item['entity_id'] as String;
        final prefs = await SharedPreferences.getInstance();
        final localId = prefs.getString('lokal.link.playlist_local.$id') ?? id;
        await prefs.setString('lokal.link.playlist_uuid.$localId', id);
        await prefs.setString('lokal.link.playlist_local.$id', localId);
        final all = await Database.instance.libraryOpEntitys
            .filter()
            .entityIdEqualTo(id)
            .findAll();
        all.sort(
          (a, b) => '${a.hlc}:${a.deviceId}:${a.opId}'.compareTo(
            '${b.hlc}:${b.deviceId}:${b.opId}',
          ),
        );
        String? name;
        var deleted = false;
        final members = <String, Map<String, dynamic>>{};
        for (final op in all) {
          final f = Map<String, dynamic>.from(jsonDecode(op.fieldsJson) as Map);
          if (op.op == 'playlist.create') {
            name = f['name']?.toString() ?? 'Playlist';
            deleted = false;
          }
          if (op.op == 'playlist.rename') name = f['name']?.toString() ?? name;
          if (op.op == 'playlist.delete') deleted = true;
          if ([
                'playlist.add',
                'playlist.move',
                'playlist.remove',
              ].contains(op.op) &&
              f['track_key'] is String)
            members[f['track_key'] as String] = {
              ...f,
              'removed': op.op == 'playlist.remove',
            };
        }
        if (name == null) return;
        final positions =
            members.entries.where((e) => e.value['removed'] != true).toList()
              ..sort((a, b) {
                final n = (a.value['position'] as num? ?? 0).compareTo(
                  b.value['position'] as num? ?? 0,
                );
                return n == 0 ? a.key.compareTo(b.key) : n;
              });
        final songIds = <String>[];
        for (final entry in positions) {
          final song = await _match({...entry.value, 'track_key': entry.key});
          if (song != null) songIds.add(song.id);
        }
        final old = await PlaylistService.instance.getPlaylist(localId);
        final playlist =
            old?.copyWith(
              name: name,
              songIds: songIds,
              updatedAt: DateTime.now(),
            ) ??
            Playlist(
              id: localId,
              name: name,
              songIds: songIds,
              createdAt: DateTime.now(),
            );
        await PlaylistService.instance.putFromLink(playlist, deleted: deleted);
        // Store the merged baseline so a later local edit only journals its delta.
        final snapshot = Map<String, dynamic>.from(
          jsonDecode(prefs.getString('lokal.link.playlists_snapshot') ?? '{}')
              as Map,
        );
        if (deleted) {
          snapshot.remove(id);
        } else {
          snapshot[id] = {
            'name': name,
            'members': positions.map((e) => e.key).toList(),
          };
        }
        await prefs.setString(
          'lokal.link.playlists_snapshot',
          jsonEncode(snapshot),
        );
        break;
      case 'track':
        const editable = [
          'title',
          'artist',
          'album',
          'album_artist',
          'genre',
          'year',
          'track_num',
        ];
        // Desktop UPDATE triggers can emit hash-only operations even when
        // tag values did not change. They must not rewrite every phone row.
        if (!editable.any(fields.containsKey)) return;
        final song = await _match({...fields, 'track_key': item['entity_id']});
        if (song?.filePath == null) return;
        await journal.registerTrackAlias(song!.id, item['entity_id'] as String);
        final winning = <String, dynamic>{};
        for (final field in [
          'title',
          'artist',
          'album',
          'album_artist',
          'genre',
          'year',
          'track_num',
        ])
          if (fields.containsKey(field) && await journal.wins(item, field))
            winning[field] = fields[field];
        // The matching snapshot identifies rows; edits earlier in this sync
        // may already have changed their metadata, so compare the current row.
        final currentRow = await Database.songs
            .filter()
            .filePathEqualTo(song.filePath!)
            .findFirst();
        if (currentRow == null) return;
        final current = <String, dynamic>{
          'title': currentRow.title,
          'artist': currentRow.artist,
          'album': currentRow.album,
          'album_artist': currentRow.albumArtist,
          'genre': currentRow.genre,
          'year': currentRow.year,
          'track_num': currentRow.trackNumber,
        };
        winning.removeWhere(
          (field, value) => value == null || value == current[field],
        );
        if (winning.isEmpty) return;
        await SongRepository().updateSongMetadata(
          song.filePath!,
          title: winning['title'] as String?,
          artist: winning['artist'] as String?,
          album: winning['album'] as String?,
          albumArtist: winning['album_artist'] as String?,
          genre: winning['genre'] as String?,
          year: (winning['year'] as num?)?.toInt(),
          trackNumber: (winning['track_num'] as num?)?.toInt(),
          recordLink: false,
        );
        break;
    }
  }
}
