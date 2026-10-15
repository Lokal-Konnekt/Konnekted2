import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/song.dart';
import '../../src/rust/api/audio_api.dart' as native;
import 'discovery_http.dart';
import 'discovery_models.dart';
import 'discovery_sources.dart';

typedef DiscoveryAudioProbe =
    Future<native.AudioProbeFormat> Function(String path);

/// Downloads actual media before engine handoff. Never treats a URL as a File.
/// The native probe is mandatory; provider file/quality labels are ignored.
class DiscoveryPlaybackCache {
  DiscoveryPlaybackCache({
    required this.http,
    DiscoveryAudioProbe? probe,
    Future<Directory> Function()? directory,
    Set<String> Function()? protectedPaths,
    this.maxFileBytes = 128 * 1024 * 1024,
    this.maxCacheBytes = 384 * 1024 * 1024,
    this.downloadTimeout = const Duration(minutes: 2),
  }) : _probe = probe ?? ((path) => native.audioProbeFormat(path: path)),
       _directory = directory ?? _defaultDirectory,
       _protectedPaths = protectedPaths ?? (() => {});

  final DiscoveryHttp http;
  final DiscoveryAudioProbe _probe;
  final Future<Directory> Function() _directory;
  final Set<String> Function() _protectedPaths;
  final int maxFileBytes;
  final int maxCacheBytes;
  final Duration downloadTimeout;
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
      await _reserve(root, maxFileBytes);
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
      await http.transfer(
        audio.url,
        maxBytes: maxFileBytes,
        deadline: downloadTimeout,
        cancel: cancel,
        onChunk: (chunk) async {
          if (prefix.length < 64) prefix.addAll(chunk.take(64 - prefix.length));
          await output!.writeFrom(chunk);
          received += chunk.length;
          onProgress?.call(received);
        },
      );
      await output.close();
      output = null;
      if (cancelled) throw const DiscoveryException('Request cancelled.');
      final format = sniffAudioContainer(prefix);
      ready = await partial.rename(p.setExtension(partial.path, '.$format'));
      partial = null;
      native.AudioProbeFormat metadata;
      try {
        metadata = await _probe(
          ready.path,
        ).timeout(const Duration(seconds: 15));
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
      if (cancelled) throw const DiscoveryException('Request cancelled.');
      // A lossy decoder's output sample width is not source bit depth.
      final bits = format == 'flac' && (metadata.bitsPerSample ?? 0) > 0
          ? metadata.bitsPerSample
          : null;
      final song = Song(
        id: 'discovery:$hash',
        title: track.title,
        artist: track.artist,
        album: track.album,
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

  Future<void> _reserve(Directory root, int reservation) async {
    final protected = _protectedPaths();
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
