import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flick/features/morneye/morneye_host.dart';
import 'package:flick/features/morneye/morneye_live_playback.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('morneye-live-test-');
    MorneyeLiveRegistry.instance.clear();
  });
  tearDown(() async {
    MorneyeLiveRegistry.instance.clear();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('64 KiB of actual FLAC makes a growing download playable', () async {
    final session = MorneyeLiveSession();
    final file = File('${directory.path}/audio.flac.part');
    final ready = <int>[0x66, 0x4c, 0x61, 0x43, ...List<int>.filled(65532, 1)];
    await file.writeAsBytes(ready);
    session.observe(MorneyeTransfer(
      part: file.path,
      file: '${directory.path}/audio.flac',
      total: 100000,
      written: ready.length,
    ));
    await session.playable.timeout(const Duration(seconds: 1));
    expect(session.isTransferring, isTrue);
    final response = await session.request(0, 100000);
    expect(response.sourceLength, 100000);
    expect(response.contentLength, 100000);
    expect(response.contentType, 'audio/flac');

    // The first range must not complete while the remaining bytes are absent.
    final collected = <int>[];
    final completed = Completer<void>();
    response.stream.listen(
      collected.addAll,
      onDone: completed.complete,
      onError: completed.completeError,
    );
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(completed.isCompleted, isFalse);

    await file.writeAsBytes(List<int>.filled(34464, 2), mode: FileMode.append);
    session.observe(MorneyeTransfer(
      part: file.path,
      file: '${directory.path}/audio.flac',
      total: 100000,
      written: 100000,
    ));
    await completed.future.timeout(const Duration(seconds: 2));
    expect(collected.length, 100000);
    expect(collected.take(4), [0x66, 0x4c, 0x61, 0x43]);
    expect(collected.last, 2);
    final finalFile = File('${directory.path}/cached.flac');
    await file.rename(finalFile.path);
    session.promote(finalFile.path);
    expect(session.isTransferring, isFalse);
    final seek = await session.request(90000, 100000);
    expect(await seek.stream.expand((bytes) => bytes).length, 10000);
  });

  test('live Qobuz/Tidal FLAC reads actual STREAMINFO, not HiRes catalogue max', () async {
    List<int> header(int depth, int rate) {
      final h = List<int>.filled(42, 0);
      h.setRange(0, 4, [0x66, 0x4c, 0x61, 0x43]);
      h[4] = 0; h[5] = 0; h[6] = 0; h[7] = 34;
      h[18] = (rate >> 12) & 0xff;
      h[19] = (rate >> 4) & 0xff;
      h[20] = ((rate & 0x0f) << 4) | (((depth - 1) >> 4) & 1);
      h[21] = ((depth - 1) & 0x0f) << 4;
      return h;
    }
    final cd = MorneyeLiveSession.readFlacStreamInfo(header(16, 44100));
    expect(cd?.bitDepth, 16);
    expect(cd?.sampleRate, 44100);
    final hires = MorneyeLiveSession.readFlacStreamInfo(header(24, 96000));
    expect(hires?.bitDepth, 24);
    expect(hires?.sampleRate, 96000);
    expect(MorneyeLiveSession.readFlacStreamInfo([1, 2, 3]), isNull);

    final session = MorneyeLiveSession();
    final file = File('${directory.path}/cd.flac.part');
    final bytes = [...header(16, 44100), ...List<int>.filled(65536-42, 0)];
    await file.writeAsBytes(bytes);
    session.observe(MorneyeTransfer(
      part: file.path, file: '${directory.path}/cd.flac',
      total: 100000, written: bytes.length,
    ));
    await session.playable.timeout(const Duration(seconds: 1));
    expect(session.bitDepth, 16);
    expect(session.sampleRate, 44100);
  });

  test('non-FLAC header never opens a growing source', () async {
    final session = MorneyeLiveSession();
    final file = File('${directory.path}/audio.flac.part');
    await file.writeAsBytes(List<int>.filled(65536, 0));
    session.observe(MorneyeTransfer(
      part: file.path,
      file: '${directory.path}/audio.flac',
      total: 100000,
      written: 65536,
    ));
    expect(session.isPlayable, isFalse);
  });

  test('unknown transfer length cannot claim early playback readiness', () async {
    final session = MorneyeLiveSession();
    final file = File('${directory.path}/audio.flac.part');
    await file.writeAsBytes([
      0x66, 0x4c, 0x61, 0x43,
      ...List<int>.filled(65532, 0),
    ]);
    session.observe(MorneyeTransfer(
      part: file.path, file: '${directory.path}/audio.flac',
      total: 0, written: 65536,
    ));
    expect(session.isPlayable, isFalse);
  });

  test('registry exposes only opaque handles and rejects missing sessions', () {
    final registry = MorneyeLiveRegistry.instance;
    final session = MorneyeLiveSession();
    final handle = registry.register(session);
    expect(handle, startsWith('lokal-morneye-live://audio/'));
    expect(handle, isNot(contains(directory.path)));
    expect(registry.resolve(handle), same(session));
    registry.clear();
    expect(registry.resolve(handle), isNull);
  });
}
