import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flick/features/discovery/discovery_http.dart';
import 'package:flick/features/discovery/discovery_models.dart';
import 'package:flick/features/discovery/discovery_playback.dart';
import 'package:flick/features/discovery/discovery_sources.dart';
import 'package:flick/src/rust/api/audio_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

// Header fixtures exercise staging; native probing is injected here, not faked
// in production. Hardware/decoder integration is explicitly a separate check.
final flacHeader = [...ascii.encode('fLaC'), ...List.filled(48, 0)];
final fixtureTrack = DiscoveryTrack(
  id: 'recording-1',
  title: 'Fixture recording',
  artist: 'Fixture artist',
  duration: const Duration(seconds: 60),
  source: DiscoverySource.addon,
  addonBase: Uri.parse('https://addon.example'),
  sourceUrl: Uri.parse('https://catalog.example/recording-1'),
);
final fixtureAudio = ResolvedDiscoveryAudio(
  Uri.parse('https://media.example/file.mp3?secret=signed'),
);

void main() {
  late Directory directory;
  setUp(
    () async =>
        directory = await Directory.systemTemp.createTemp('discovery_test_'),
  );
  tearDown(() async => directory.delete(recursive: true));

  test(
    'downloads without credentials, probes bytes and builds a real local Song',
    () async {
      final client = MockClient((request) async {
        expect(request.url, fixtureAudio.url);
        expect(
          request.headers.keys.map((k) => k.toLowerCase()),
          isNot(contains('authorization')),
        );
        expect(request.followRedirects, isFalse);
        return http.Response.bytes(flacHeader, 200);
      });
      addTearDown(client.close);
      var probes = 0;
      final cache = DiscoveryPlaybackCache(
        http: DiscoveryHttp(client),
        directory: () async => directory,
        probe: (path) async {
          probes++;
          expect(
            p.extension(path),
            '.flac',
          ); // URL's MP3 suffix is not trusted.
          expect(await File(path).readAsBytes(), flacHeader);
          return const AudioProbeFormat(
            sampleRate: 44100,
            channels: 2,
            bitsPerSample: 16,
          );
        },
      );
      final song = await cache.prepare(fixtureTrack, fixtureAudio);
      expect(probes, 1);
      expect(song.fileType, 'FLAC');
      expect(song.sampleRate, 44100);
      expect(song.bitDepth, 16);
      expect(song.resolution, isNull);
      expect(song.filePath, startsWith(directory.path));
      expect(song.filePath, isNot(contains('secret')));
      expect(song.remoteId, fixtureTrack.sourceUrl.toString());
      expect(
        song.isNetworkSource,
        isFalse,
      ); // No unsupported RemoteSourceService route.
      expect(await File(song.filePath!).exists(), isTrue);
    },
  );

  test(
    'lossy decoder bit width never becomes a lossless quality claim',
    () async {
      final client = MockClient(
        (_) async => http.Response.bytes([
          ...ascii.encode('ID3'),
          ...List.filled(40, 0),
        ], 200),
      );
      addTearDown(client.close);
      final cache = DiscoveryPlaybackCache(
        http: DiscoveryHttp(client),
        directory: () async => directory,
        probe: (_) async => const AudioProbeFormat(
          sampleRate: 48000,
          channels: 2,
          bitsPerSample: 32,
        ),
      );
      final song = await cache.prepare(fixtureTrack, fixtureAudio);
      expect(song.fileType, 'MP3');
      expect(song.sampleRate, 48000);
      expect(song.bitDepth, isNull);
      expect(song.resolution, isNull);
    },
  );

  test(
    'HTML named FLAC and playlist payloads never reach native probe',
    () async {
      for (final bytes in [
        ascii.encode('<html>not audio</html>'),
        ascii.encode('#EXTM3U\nhttps://media.example/file'),
      ]) {
        final client = MockClient((_) async => http.Response.bytes(bytes, 200));
        addTearDown(client.close);
        final cache = DiscoveryPlaybackCache(
          http: DiscoveryHttp(client),
          directory: () async => directory,
          probe: (_) async => fail('Probe must not be called'),
        );
        await expectLater(
          cache.prepare(fixtureTrack, fixtureAudio),
          throwsA(isA<DiscoveryException>()),
        );
        expect(await directory.list().toList(), isEmpty);
      }
    },
  );

  test(
    'native probe failure removes the staged file and is not treated as playable',
    () async {
      final client = MockClient(
        (_) async => http.Response.bytes(flacHeader, 200),
      );
      addTearDown(client.close);
      final cache = DiscoveryPlaybackCache(
        http: DiscoveryHttp(client),
        directory: () async => directory,
        probe: (_) async =>
            throw StateError('decoder failure with private path'),
      );
      await expectLater(
        cache.prepare(fixtureTrack, fixtureAudio),
        throwsA(
          isA<DiscoveryException>().having(
            (e) => e.message,
            'sanitized',
            isNot(contains('private path')),
          ),
        ),
      );
      expect(await directory.list().toList(), isEmpty);
    },
  );

  test(
    'oversized declared or chunked download is bounded and partial file removed',
    () async {
      for (final declared in [true, false]) {
        final client = MockClient.streaming(
          (_, _) async => http.StreamedResponse(
            Stream.fromIterable([flacHeader, List.filled(100, 0)]),
            200,
            contentLength: declared ? 152 : null,
          ),
        );
        addTearDown(client.close);
        final cache = DiscoveryPlaybackCache(
          http: DiscoveryHttp(client),
          directory: () async => directory,
          maxFileBytes: 80,
          maxCacheBytes: 160,
          probe: (_) async => fail('Oversized file must not be probed'),
        );
        await expectLater(
          cache.prepare(fixtureTrack, fixtureAudio),
          throwsA(isA<DiscoveryException>()),
        );
        expect(await directory.list().toList(), isEmpty);
      }
    },
  );

  test('download timeout cancels stream and removes partial file', () async {
    final stream = StreamController<List<int>>();
    final client = MockClient.streaming((_, _) async {
      stream.add(flacHeader);
      return http.StreamedResponse(stream.stream, 200);
    });
    addTearDown(client.close);
    final cache = DiscoveryPlaybackCache(
      http: DiscoveryHttp(client),
      directory: () async => directory,
      downloadTimeout: const Duration(milliseconds: 20),
      probe: (_) async => fail('Timeout must not be probed'),
    );
    await expectLater(
      cache.prepare(fixtureTrack, fixtureAudio),
      throwsA(isA<DiscoveryException>()),
    );
    expect(await directory.list().toList(), isEmpty);
    await stream.close();
  });

  test(
    'cancellation after native probe prevents handoff and cleans up',
    () async {
      final cancel = Completer<void>();
      final client = MockClient(
        (_) async => http.Response.bytes(flacHeader, 200),
      );
      addTearDown(client.close);
      final cache = DiscoveryPlaybackCache(
        http: DiscoveryHttp(client),
        directory: () async => directory,
        probe: (_) async {
          cancel.complete();
          await Future<void>.delayed(Duration.zero);
          return const AudioProbeFormat(sampleRate: 44100, channels: 2);
        },
      );
      await expectLater(
        cache.prepare(fixtureTrack, fixtureAudio, cancel: cancel.future),
        throwsA(isA<DiscoveryException>()),
      );
      expect(await directory.list().toList(), isEmpty);
    },
  );

  test(
    'LRU reservation preserves queued file and bounds total storage',
    () async {
      final old = File(p.join(directory.path, 'old.flac'));
      final protected = File(p.join(directory.path, 'queued.flac'));
      await old.writeAsBytes(List.filled(80, 0));
      await protected.writeAsBytes(List.filled(80, 0));
      final client = MockClient(
        (_) async => http.Response.bytes(flacHeader, 200),
      );
      addTearDown(client.close);
      final cache = DiscoveryPlaybackCache(
        http: DiscoveryHttp(client),
        directory: () async => directory,
        maxFileBytes: 100,
        maxCacheBytes: 200,
        protectedPaths: () => {protected.path},
        probe: (_) async =>
            const AudioProbeFormat(sampleRate: 44100, channels: 2),
      );
      await cache.prepare(fixtureTrack, fixtureAudio);
      expect(await old.exists(), isFalse);
      expect(await protected.exists(), isTrue);
      var bytes = 0;
      await for (final entry in directory.list()) {
        bytes += await (entry as File).length();
      }
      expect(bytes, lessThanOrEqualTo(200));
    },
  );

  test('full protected cache fails before media request', () async {
    final protected = File(p.join(directory.path, 'queued.flac'));
    await protected.writeAsBytes(List.filled(150, 0));
    final client = MockClient((_) async => fail('No space must not download'));
    addTearDown(client.close);
    final cache = DiscoveryPlaybackCache(
      http: DiscoveryHttp(client),
      directory: () async => directory,
      maxFileBytes: 100,
      maxCacheBytes: 200,
      protectedPaths: () => {protected.path},
    );
    await expectLater(
      cache.prepare(fixtureTrack, fixtureAudio),
      throwsA(isA<DiscoveryException>()),
    );
    expect(await protected.length(), 150);
  });
}
