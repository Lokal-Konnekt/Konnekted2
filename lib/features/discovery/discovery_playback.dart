import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/song.dart';
import '../../services/metadata_editor_service.dart';
import '../../src/rust/api/audio_api.dart' as native;
import 'discovery_http.dart';
import 'discovery_models.dart';
import 'discovery_sources.dart';

typedef DiscoveryAudioProbe = Future<native.AudioProbeFormat> Function(
  String path,
);

/// Downloads actual media before engine handoff. Never treats a URL as a File.
/// The native probe is mandatory; provider file/quality labels are ignored.
class DiscoveryPlaybackCache {
  DiscoveryPlaybackCache({
    required this.http,
    DiscoveryAudioProbe? probe,
    Future<Directory> Function()? directory,
    Set<String> Function()? protectedPaths,
    this.maxFileBytes = 128 * 1024 * 1024,
    this.maxCacheBytes = 1024 * 1024 * 1024,
    this.downloadTimeout = const Duration(minutes: 2),
    this.rangeBytes = 10 * 1024 * 1024,
    Future<void> Function(String audio, String cover)? embedCover,
  }) : _embedCover = embedCover ?? _embedCoverInFile,
       _probe = probe ?? ((path) => native.audioProbeFormat(path: path)),
       _directory = directory ?? _defaultDirectory,
       _protectedPaths = protectedPaths ?? (() => {});

  final DiscoveryHttp http;
  final Future<void> Function(String audio, String cover) _embedCover;
  final DiscoveryAudioProbe _probe;
  final Future<Directory> Function() _directory;
  final Set<String> Function() _protectedPaths;
  final int maxFileBytes;
  final int maxCacheBytes;
  final Duration downloadTimeout;

  /// The size of each part when a recording is fetched in parts.
  final int rangeBytes;
  bool _busy = false;

  static Future<Directory> _defaultDirectory() async => Directory(
    p.join((await getApplicationCacheDirectory()).path, 'discovery_audio'),
  );

  Future<Song> prepare(
    DiscoveryTrack track,
    ResolvedDiscoveryAudio audio, {
    Future<void>? cancel,
    void Function(int bytes)? onProgress,
  }) async {
    if (_busy) {
      throw const DiscoveryException('Another recording is being prepared.');
    }
    if (maxFileBytes <= 0 || maxCacheBytes < maxFileBytes) {
      throw const DiscoveryException('Invalid playback cache limits.');
    }
    _busy = true;
    File? partial;
    File? ready;
    RandomAccessFile? output;
    var cancelled = false;
    if (cancel != null) unawaited(cancel.then((_) => cancelled = true));
    try {
      final root = await _directory();
      await root.create(recursive: true);
      // 128MB was reserved for *every* track even when it occupied only
      // a few MB, leading to false "cache full" failures on populated queues.
      // Known lengths reserve exactly their bytes; unknown lengths grow
      // incrementally under the same hard cache ceiling.
      await _reserve(root, audio.length ?? 0);
      if (cancelled) throw const DiscoveryException('Request cancelled.');
      // Random suffix prevents overwriting a cached file currently in use.
      // Names contain neither titles nor signed URLs/tokens.
      final hash = sha256.convert(utf8.encode(track.key)).toString();
      partial = File(
        p.join(
          root.path,
          '$hash-${DateTime.now().microsecondsSinceEpoch}.part',
        ),
      );
      output = await partial.open(mode: FileMode.writeOnly);
      final prefix = <int>[];
      var received = 0;
      Future<void> write(List<int> chunk) async {
        if (prefix.length < 64) prefix.addAll(chunk.take(64 - prefix.length));
        if (audio.length == null) {
          // Include existing .part bytes in the next space calculation;
          // _reserve never evicts an active, recently modified .part file.
          await _reserve(root, chunk.length);
        }
        await output!.writeFrom(chunk);
        received += chunk.length;
        onProgress?.call(received);
      }

      final length = audio.length;
      if (length == null) {
        await http.transfer(
          audio.url,
          headers: audio.headers,
          maxBytes: maxFileBytes,
          deadline: downloadTimeout,
          cancel: cancel,
          followMediaRedirects: audio.url.host.endsWith('.googlevideo.com'),
          onChunk: write,
        );
      } else {
        if (length <= 0 || length > maxFileBytes) {
          throw const DiscoveryException(
            'The recording exceeds the download size limit.',
          );
        }
        // In parts, each a `range` of the file, under one overall deadline.
        final started = DateTime.now();
        final googleVideo = audio.url.host.toLowerCase().endsWith(
          '.googlevideo.com',
        );
        final client = audio.url.queryParameters['c']?.toUpperCase() ?? '';
        // Match the resolver clients' bounded-range capability (BitChord's
        // PlayerClient.rangeBytesFor). A 16KB preflight may succeed while the
        // old 10MB download ranges are refused for anonymous VR/TV clients.
        final chunkBytes = googleVideo
            ? math.min(
                rangeBytes,
                client == 'ANDROID_VR' || client.startsWith('TVHTML5_SIMPLY')
                    ? 512 * 1024
                    : 1024 * 1024,
              )
            : rangeBytes;
        for (var start = 0; start < length;) {
          final end = math.min(start + chunkBytes, length) - 1;
          final left = downloadTimeout - DateTime.now().difference(started);
          if (left <= Duration.zero) {
            throw const DiscoveryException('The source timed out. Try again.');
          }
          // Googlevideo links are signed/client-bound: keep the exact URL
          // and use the Range header the media endpoint expects.
          final partBytes = await http.transfer(
            googleVideo
                ? audio.url
                : audio.url.replace(
                    queryParameters: {
                      ...audio.url.queryParameters,
                      'range': '$start-$end',
                    },
                  ),
            headers: {
              ...audio.headers,
              if (googleVideo) 'Range': 'bytes=$start-$end',
            },
            maxBytes: end - start + 1,
            deadline: left,
            cancel: cancel,
            allowPartial: googleVideo,
            followMediaRedirects: googleVideo,
            rangeStart: googleVideo ? start : null,
            onChunk: write,
          );
          start += partBytes;
        }
        if (received != length) {
          throw const DiscoveryException(
            'The source returned an empty or incomplete response.',
          );
        }
      }
      await output.close();
      output = null;
      if (cancelled) throw const DiscoveryException('Request cancelled.');
      final format = sniffAudioContainer(prefix);
      ready = await partial.rename(p.setExtension(partial.path, '.$format'));
      partial = null;
      final song = await _verified(track, ready, format, hash);
      if (cancelled) throw const DiscoveryException('Request cancelled.');
      ready = null; // Ownership passes to bounded cache / PlayerService.
      return song;
    } finally {
      try {
        await output?.close();
        if (partial != null && await partial.exists()) await partial.delete();
        if (ready != null && await ready.exists()) await ready.delete();
      } finally {
        _busy = false;
      }
    }
  }

  /// Moves [source], a file an add-on already downloaded, into the cache
  /// and checks it like a downloaded one.
  Future<Song> adopt(DiscoveryTrack track, File source) async {
    if (_busy) {
      throw const DiscoveryException('Another recording is being prepared.');
    }
    _busy = true;
    File? ready;
    try {
      final size = await source.length();
      if (size <= 0 || size > maxFileBytes) {
        throw const DiscoveryException(
          'The recording exceeds the download size limit.',
        );
      }
      final root = await _directory();
      await root.create(recursive: true);
      await _reserve(root, size);
      final prefix = await source
          .openRead(0, 64)
          .fold<List<int>>([], (all, chunk) => all..addAll(chunk));
      String format;
      try {
        format = sniffAudioContainer(prefix);
      } on DiscoveryException {
        // Containers only the add-on's own probe knows: it named the file.
        format = p.extension(source.path).replaceFirst('.', '').toLowerCase();
        if (!const {'aac', 'webm', 'wv', 'opus'}.contains(format)) rethrow;
      }
      final hash = sha256.convert(utf8.encode(track.key)).toString();
      final target = p.join(
        root.path,
        '$hash-${DateTime.now().microsecondsSinceEpoch}.$format',
      );
      try {
        ready = await source.rename(target);
      } on FileSystemException {
        // Another volume: copy instead.
        ready = await source.copy(target);
      }
      final song = await _verified(track, ready, format, hash);
      ready = null; // Ownership passes to bounded cache / PlayerService.
      return song;
    } finally {
      try {
        if (ready != null && await ready.exists()) await ready.delete();
      } finally {
        _busy = false;
      }
    }
  }

  /// The native probe's verdict on [ready], as a song to play.
  Future<Song> _verified(
    DiscoveryTrack track,
    File ready,
    String format,
    String hash,
  ) async {
    native.AudioProbeFormat metadata;
    try {
      metadata = await _probe(ready.path).timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const DiscoveryException(
        'The native engine could not verify this audio file. Its codec may be unsupported.',
      );
    }
    if (metadata.sampleRate <= 0 ||
        metadata.channels <= 0 ||
        metadata.channels > 32) {
      throw const DiscoveryException(
        'The downloaded file has no valid audio format.',
      );
    }
    // A lossy decoder's output sample width is not source bit depth.
    final bits = format == 'flac' && (metadata.bitsPerSample ?? 0) > 0
        ? metadata.bitsPerSample
        : null;
    final cover = await _cover(track, ready);
    return Song(
      id: 'discovery:$hash',
      title: track.title,
      artist: track.artist,
      album: track.album,
      albumArt: cover,
      duration: track.duration ?? Duration.zero,
      fileType: format.toUpperCase(),
      sampleRate: metadata.sampleRate,
      bitDepth: bits,
      filePath: ready.path,
      // Keep canonical source metadata separate from the local cache path.
      // Signed media URLs remain in memory, never in the playback queue.
      remoteId: track.sourceUrl?.toString() ?? track.id,
      sourcePackage: 'konnekted.discovery',
      isExternal: true,
    );
  }

  /// Where the cover of the audio at [audio] is kept: beside it, so the
  /// player, the mini player and the notification read it as a file.
  static String coverPath(String audio) =>
      '${p.withoutExtension(audio)}$_coverSuffix';
  static const _coverSuffix = '-cover.jpg';
  static const _maxCoverBytes = 4 * 1024 * 1024;

  /// Downloads [track]'s cover next to [ready]; null when it has none or
  /// it can't be fetched (the song still plays, without a picture).
  Future<String?> _cover(DiscoveryTrack track, File ready) async {
    final url = Uri.tryParse(track.artwork ?? '');
    if (url == null || url.scheme != 'https') return null;
    final file = File(coverPath(ready.path));
    IOSink? sink;
    try {
      sink = file.openWrite();
      final out = sink;
      await http.transfer(
        url,
        headers: const {'Accept': 'image/*'},
        maxBytes: _maxCoverBytes,
        deadline: const Duration(seconds: 15),
        onChunk: out.add,
      );
      await out.close();
      sink = null;
      // Also embed it in the audio's tags, so the file keeps its cover if
      // it is saved to the library.
      try {
        await _embedCover(ready.path, file.path);
      } catch (_) {}
      return file.path;
    } catch (_) {
      try {
        await sink?.close();
      } catch (_) {}
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      return null;
    }
  }

  static Future<void> _embedCoverInFile(String audio, String cover) async {
    await MetadataEditorService.instance.writeCoverArtToPath(
      audio,
      await File(cover).readAsBytes(),
    );
  }

  Future<void> _reserve(Directory root, int reservation) async {
    final audio = _protectedPaths();
    // A song kept keeps its cover.
    final protected = {...audio, for (final path in audio) coverPath(path)};
    final files = <({File file, FileStat stat})>[];
    var total = 0;
    await for (final entry in root.list(followLinks: false)) {
      if (entry is! File) continue;
      final stat = await entry.stat();
      total += stat.size;
      files.add((file: entry, stat: stat));
    }
    files.sort((a, b) => a.stat.modified.compareTo(b.stat.modified));
    for (final entry in files) {
      if (total + reservation <= maxCacheBytes) break;
      if (protected.contains(entry.file.path)) continue;
      // Do not evict in-flight downloads while multiple lookups are active.
      if (p.extension(entry.file.path) == '.part' &&
          DateTime.now().difference(entry.stat.modified) < downloadTimeout) {
        continue;
      }
      await entry.file.delete();
      total -= entry.stat.size;
    }
    if (total + reservation > maxCacheBytes) {
      throw const DiscoveryException(
        'The playback cache is full of queued audio. Clear those queue entries and retry.',
      );
    }
  }
}

/// Header inspection chooses only a container extension; the native probe is
/// still required. HTML, JSON, playlists and forged URL suffixes never suffice.
String sniffAudioContainer(List<int> bytes) {
  bool at(int offset, String magic) =>
      bytes.length >= offset + magic.length &&
      List.generate(
        magic.length,
        (i) => bytes[offset + i] == magic.codeUnitAt(i),
      ).every((v) => v);
  if (at(0, 'fLaC')) return 'flac';
  if (at(0, 'RIFF') && at(8, 'WAVE')) return 'wav';
  if (at(0, 'OggS')) return 'ogg';
  // InnerTubeX AUTO commonly selects Opus in WebM. Symphonia supports the
  // Matroska container; the native probe below still validates its audio.
  if (bytes.length >= 4 &&
      bytes[0] == 0x1a &&
      bytes[1] == 0x45 &&
      bytes[2] == 0xdf &&
      bytes[3] == 0xa3) {
    return 'webm';
  }
  if (at(4, 'ftyp')) return 'm4a';
  if (at(0, 'ID3') ||
      (bytes.length >= 4 &&
          bytes[0] == 0xff &&
          bytes[1] & 0xe0 == 0xe0 &&
          bytes[1] & 0x06 != 0 &&
          bytes[2] & 0xf0 != 0xf0 &&
          bytes[2] & 0xf0 != 0)) {
    return 'mp3';
  }
  throw const DiscoveryException(
    'The downloaded response is not a supported progressive audio file.',
  );
}
