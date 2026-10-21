import 'dart:convert';

import '../src/rust/api/morneye_api.dart' show morneyeMediaInfo;

import 'dart:async';
import 'dart:io';

import 'package:isar_community/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/database.dart';
import '../models/song.dart';
import '../src/rust/api/scanner.dart';
import 'music_folder_service.dart';

/// Reads the actual local audio header; remote labels are only a fallback.
/// One worker repairs old rows and new imports without decoding or downloading audio.
class LocalMetadataRepair {
  static final instance = LocalMetadataRepair();
  static const _version = 'lokal.local_metadata.v2';
  Set<int> _pending = <int>{};
  final _waiters = <int, Completer<void>>{};
  final _scheduled = <int>{};
  final _seen = <String>{};
  Future<void>? _running;
  bool _loaded = false;
  bool _seeded = false;

  void warm(List<Song> songs) {
    final incoming = <int>{};
    for (final song in songs) {
      if (song.isNetworkSource || song.isPending) continue;
      final id = int.tryParse(song.id);
      if (id != null && _scheduled.add(id)) incoming.add(id);
    }
    _pending = _seeded
        ? {...incoming, ..._pending}
        : {..._pending, ...incoming};
    _seeded = true;
    if (_pending.isNotEmpty) unawaited(_drain().catchError((Object _) {}));
  }

  Future<void> repairDesktopCopies({
    void Function(int done, int total)? onProgress,
  }) async {
    if (!Database.isInitialized) return;
    final rows = await Database.songs.filter().sourceTypeIsNull().findAll();
    final ids = {
      for (final row in rows)
        if (row.filePath.contains('/desktop_music/')) row.id,
    };
    _pending = {
      ...ids,
      ..._pending,
    }; // Prioritize this repair over the background backlog.
    var done = 0;
    onProgress?.call(done, ids.length);
    final waiting = [
      for (final id in ids)
        (_waiters[id] ??= Completer<void>()).future.then(
          (_) => onProgress?.call(++done, ids.length),
        ),
    ];
    unawaited(
      _drain().catchError((Object error, StackTrace stack) {
        for (final waiter in _waiters.values) {
          if (!waiter.isCompleted) waiter.completeError(error, stack);
        }
        _waiters.clear();
      }),
    );
    await Future.wait(waiting);
    await (await SharedPreferences.getInstance()).setStringList(
      _version,
      _seen.toList(),
    );
  }

  Future<void> _drain() {
    return _running ??= _work().whenComplete(() => _running = null);
  }

  Future<void> _work() async {
    final prefs = await SharedPreferences.getInstance();
    if (!_loaded) {
      _seen.addAll(prefs.getStringList(_version) ?? const []);
      _loaded = true;
    }
    while (_pending.isNotEmpty && Database.isInitialized) {
      final id = _pending.first;
      _pending.remove(id);
      var read = false;
      try {
        read = await _repairOne(id);
      } finally {
        _waiters.remove(id)?.complete();
      }
      if (read && _pending.isNotEmpty)
        await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await prefs.setStringList(_version, _seen.toList());
  }

  Future<bool> _repairOne(int id) async {
    final row = await Database.songs.get(id);
    if (row == null || row.sourceType != null) return false;
    final signature =
        '$id:${row.filePath}:${row.fileSize}:${row.lastModified?.millisecondsSinceEpoch}';
    if (_seen.contains(signature)) return false;
    try {
      if (await probe(row)) _seen.add(signature);
    } catch (_) {
      /* Retry inaccessible files next session. */
    }
    return true;
  }

  /// Call before committing a newly copied file; also used to repair old rows.
  static Future<bool> probe(SongEntity row, {bool persist = true}) async {
    var path = row.filePath;
    if (path.startsWith('file://')) path = Uri.parse(path).toFilePath();
    if (path.startsWith('content://') || !await File(path).exists()) {
      final uri = path.startsWith('content://') ? path : row.mediaStoreUri;
      if (uri == null) return false;
      path =
          await MusicFolderService().cacheUriForPlayback(
            uri,
            extensionHint: row.fileType,
            maxSizeBytes: 256 * 1024 * 1024,
          ) ??
          '';
    }
    if (path.isEmpty) return false;
    final meta = await extractFileMetadata(path: path);
    if (meta == null) return false;
    String? codec;
    int? probedRate, probedBits;
    try {
      final info = jsonDecode(await morneyeMediaInfo(path: path)) as Map;
      final actual = info['codec']?.toString().toLowerCase();
      if (actual != null && actual != 'unknown') {
        codec = actual.startsWith('pcm_') ? 'WAV' : actual.toUpperCase();
      }
      probedRate = (info['sample_rate'] as num?)?.toInt();
      probedBits = (info['bit_depth'] as num?)?.toInt();
    } catch (_) {
      /* DSD and other formats retain Lofty's specialized metadata. */
    }
    void apply(SongEntity target) {
      if ((meta.sampleRate ?? 0) > 0) target.sampleRate = meta.sampleRate;
      if ((meta.bitDepth ?? 0) > 0) target.bitDepth = meta.bitDepth;
      // Lofty's audio_bitrate() is already kilobits per second.
      if ((meta.bitrate ?? 0) > 0) target.bitrate = meta.bitrate;
      if (meta.format.isNotEmpty) target.fileType = meta.format.toUpperCase();
      if (codec != null) target.fileType = codec;
      if ((target.sampleRate ?? 0) <= 0 && (probedRate ?? 0) > 0)
        target.sampleRate = probedRate;
      if ((target.bitDepth ?? 0) <= 0 && (probedBits ?? 0) > 0)
        target.bitDepth = probedBits;
      if (target.genre?.trim().isNotEmpty != true &&
          meta.genre?.trim().isNotEmpty == true)
        target.genre = meta.genre;
      const lossless = {
        'FLAC',
        'ALAC',
        'WAV',
        'WAVE',
        'AIFF',
        'AIF',
        'APE',
        'WV',
        'WAVPACK',
      };
      target.metadataComplete =
          (target.sampleRate ?? 0) > 0 &&
          (target.bitrate ?? 0) > 0 &&
          (!lossless.contains(target.fileType?.toUpperCase()) ||
              (target.bitDepth ?? 0) > 0);
    }

    apply(row);
    if (!persist) return row.metadataComplete;
    await Database.instance.writeTxn(() async {
      final current = await Database.songs.get(row.id);
      if (current == null ||
          current.filePath != row.filePath ||
          current.sourceType != null)
        return;
      apply(current);
      await Database.songs.put(current);
    });
    return row.metadataComplete;
  }
}
