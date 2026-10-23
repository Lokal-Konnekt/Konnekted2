import 'package:flick/services/atmos_playback_support.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lokal/atmos');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('does not request Atmos without a licensed decoder/output', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'capabilities') return {
        'available': false, 'jocDecoder': false, 'passthrough': false,
      };
      return false;
    });
    expect(await AtmosPlaybackSupport.available, isFalse);
    expect(await AtmosPlaybackSupport.isJocFile('/tmp/stereo.m4a'), isFalse);
  });

  test('uses native file inspection, never the source catalogue alone', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'capabilities') return {
        'available': true, 'jocDecoder': true, 'passthrough': false,
      };
      if (call.method == 'inspect') {
        final path = (call.arguments as Map)['path'] as String;
        return path.endsWith('/true-joc.m4a');
      }
      return null;
    });
    expect(await AtmosPlaybackSupport.available, isTrue);
    expect(await AtmosPlaybackSupport.isJocFile('/tmp/true-joc.m4a'), isTrue);
    expect(await AtmosPlaybackSupport.isJocFile('/tmp/lossless.m4a'), isFalse);
  });

  test('missing plugin safely falls back to stereo', () async {
    expect(await AtmosPlaybackSupport.available, isFalse);
    expect(await AtmosPlaybackSupport.isJocFile('/tmp/file.m4a'), isFalse);
  });
}
