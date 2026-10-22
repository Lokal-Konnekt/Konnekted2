import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flick/models/lokal_remote_state.dart';
import 'package:flick/models/song.dart';
import 'package:flick/services/link/lokal_desktop_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late File file;
  final credentials = LokalRemoteCredentials(
    origin: Uri.parse('http://desktop.local:3000'),
    remoteToken: 'fixture-pairing-token',
  );
  Song song() => Song(
    id: '42',
    title: '駅',
    artist: 'Artist',
    album: 'Album',
    duration: const Duration(seconds: 10),
    fileType: 'FLAC',
    filePath: file.path,
  );
  setUp(() async {
    root = await Directory.systemTemp.createTemp('lokal-upload');
    file = await File(
      '${root.path}/song.flac',
    ).writeAsBytes([102, 76, 97, 67, ...List.generate(128000, (i) => i % 256)]);
  });
  tearDown(() async => root.delete(recursive: true));
  test('streams original bytes with a matching length, checksum and Unicode metadata', () async {
    final original = await file.readAsBytes();
    final source = LokalDesktopSource(
      uploadClientFactory: () => MockClient.streaming((request, stream) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/remote/files');
        expect(request.headers['x-remote-token'], 'fixture-pairing-token');
        expect(request.headers['content-type'], 'application/octet-stream');
        expect(request.contentLength, original.length);
        final metadata = jsonDecode(
          utf8.decode(base64Url.decode(request.headers['x-link-metadata']!)),
        ) as Map;
        expect(metadata['extension'], 'flac');
        expect(metadata['title'], '駅');
        final received = await stream.toBytes();
        expect(received, original);
        expect(metadata['sha256'], sha256.convert(received).toString());
        return http.StreamedResponse(
          Stream.value(utf8.encode('{"ok":true,"trackId":"pc-42"}')),
          200,
        );
      }),
    );
    await source.uploadToDesktop(song(), credentials);
    expect(await file.readAsBytes(), original);
  });
  test(
    'retains the desktop reason for HTTP 400 instead of hiding it',
    () async {
      final source = LokalDesktopSource(
        uploadClientFactory: () => MockClient.streaming((_, stream) async {
          await stream.drain<void>();
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(
                jsonEncode({'error': 'The file checksum did not match.'}),
              ),
            ),
            400,
          );
        }),
      );
      await expectLater(
        source.uploadToDesktop(song(), credentials),
        throwsA(
          isA<StateError>()
              .having(
                (e) => e.message,
                'desktop reason',
                contains('checksum did not match'),
              )
              .having((e) => e.message, 'status', contains('HTTP 400')),
        ),
      );
    },
  );
  test('rejects empty files before sending', () async {
    await file.writeAsBytes([]);
    final source = LokalDesktopSource(
      uploadClientFactory: () => throw StateError('must not send'),
    );
    await expectLater(
      source.uploadToDesktop(song(), credentials),
      throwsA(
        isA<StateError>().having((e) => e.message, 'empty', contains('empty')),
      ),
    );
  });
}
