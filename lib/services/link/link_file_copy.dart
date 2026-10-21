import 'dart:io';

import '../../data/database.dart';
import '../../data/repositories/song_repository.dart';
import '../../models/lokal_remote_state.dart';
import '../../models/song.dart';
import 'link_journal.dart';
import 'lokal_desktop_source.dart';
import 'lokal_link_service.dart';

class LinkCopyPlan {
  const LinkCopyPlan({
    required this.server,
    required this.toDesktop,
    required this.toPhone,
  });
  final NetworkServerEntity server;
  final List<Song> toDesktop;
  final List<({Map<String, dynamic> track, Song? existing})> toPhone;
  int get total => toDesktop.length + toPhone.length;
}

/// Explicit, non-destructive copies. Rechecking both catalogues on each attempt
/// makes retries skip completed files without a second transfer queue/database.
class LinkFileCopy {
  LinkFileCopy({
    required this.credentials,
    required this.socket,
    required this.connected,
    required this.onProgress,
  });
  final LokalRemoteCredentials credentials;
  final LokalLinkService socket;
  final bool Function() connected;
  final void Function(LinkCopyProgress) onProgress;

  void _check() {
    if (!connected())
      throw StateError('Reconnect to your desktop to continue copying.');
  }

  Future<LinkCopyPlan> plan() async {
    _check();
    onProgress(const LinkCopyProgress(phase: LinkCopyPhase.checking));
    final source = LokalDesktopSource.instance;
    await source.requireOriginalFileSupport(credentials);
    final server = await source.ensureServer(credentials);
    final songs = await SongRepository().getAllSongs();
    final local = <Song>[];
    for (final song in songs) {
      if (song.isNetworkSource || song.filePath == null) continue;
      final uri = Uri.tryParse(song.filePath!);
      if (uri?.scheme == 'content' ||
          await File(uri?.scheme == 'file' ? uri!.toFilePath() : song.filePath!)
              .exists())
        local.add(song);
    }
    final missing = <Song>[];
    for (var offset = 0; offset < local.length; offset += 250) {
      _check();
      final batch = local.skip(offset).take(250).toList();
      final reply = await socket.request('command', {
        'action': 'resolveTracks',
        'value': {
          'queue': [
            for (final song in batch)
              {
                ...LinkJournal.instance.songWire(song),
                'track_key': await LinkJournal.instance.trackKeyFor(song),
              },
          ],
        },
      });
      if (reply.body['missing'] is! List)
        throw const FormatException(
          'Update Lokal on your PC to compare song files.',
        );
      for (final index in reply.body['missing'] as List) {
        if (index is! int || index < 0 || index >= batch.length)
          throw const FormatException('Invalid missing-song response.');
        missing.add(batch[index]);
      }
    }
    String name(String value) =>
        value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    String key(String artist, String title) =>
        '${name(artist)}\u0000${name(title)}';
    final localByName = <String, List<Song>>{};
    for (final song in local)
      localByName.putIfAbsent(key(song.artist, song.title), () => []).add(song);
    final downloads = <({Map<String, dynamic> track, Song? existing})>[];
    final seen = <String>{};
    for (final track in await source.readCatalogue(credentials)) {
      _check();
      final id = track['id'].toString();
      if (!seen.add(id)) continue;
      final title = track['title'] as String? ?? '',
          artist = track['artist'] as String? ?? '';
      final seconds = (track['duration'] as num? ?? 0).toDouble();
      if ((localByName[key(artist, title)] ?? []).any(
        (song) => (song.duration.inMilliseconds / 1000 - seconds).abs() <= 2,
      ))
        continue;
      final existing = songs
          .where(
            (song) =>
                (song.sourceType == 'lokal' &&
                    song.remoteServerId == server.id &&
                    song.remoteId == id) ||
                (!song.isNetworkSource &&
                    name(song.artist) == name(artist) &&
                    name(song.title) == name(title) &&
                    (song.duration.inMilliseconds / 1000 - seconds).abs() <= 2),
          )
          .firstOrNull;
      downloads.add((track: track, existing: existing));
    }
    _check();
    // Keep the operation reserved while the user reviews the copy preview.
    onProgress(const LinkCopyProgress(phase: LinkCopyPhase.checking));
    return LinkCopyPlan(server: server, toDesktop: missing, toPhone: downloads);
  }

  Future<void> copy(LinkCopyPlan plan) async {
    var processed = 0, sent = 0, received = 0;
    final failures = <String>[];
    void report(LinkCopyPhase phase, {String? title, bool toDesktop = false}) =>
        onProgress(
          LinkCopyProgress(
            phase: phase,
            total: plan.total,
            processed: processed,
            sent: sent,
            received: received,
            failures: List.unmodifiable(failures),
            currentTitle: title,
            toDesktop: toDesktop,
          ),
        );
    try {
      report(LinkCopyPhase.copying);
      for (final song in plan.toDesktop) {
        _check();
        report(LinkCopyPhase.copying, title: song.title, toDesktop: true);
        try {
          await LokalDesktopSource.instance.uploadToDesktop(song, credentials);
          sent++;
        } catch (_) {
          failures.add(song.title);
        }
        processed++;
        report(LinkCopyPhase.copying);
      }
      for (final entry in plan.toPhone) {
        _check();
        final title = entry.track['title'] as String? ?? 'Song';
        report(LinkCopyPhase.copying, title: title);
        try {
          await LokalDesktopSource.instance.copyOriginalToPhone(
            plan.server,
            entry.track,
            existing: entry.existing,
          );
          received++;
        } catch (_) {
          failures.add(title);
        }
        processed++;
        report(LinkCopyPhase.copying);
      }
      _check();
      report(LinkCopyPhase.complete);
    } catch (_) {
      report(LinkCopyPhase.paused);
      rethrow;
    }
  }
}
