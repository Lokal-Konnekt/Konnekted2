import 'dart:convert';

import 'package:flick/features/discovery/discovery_http.dart';
import 'package:flick/features/discovery/discovery_models.dart';
import 'package:flick/features/discovery/youtube_audio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _player(List<Map<String, dynamic>> formats) => {
  'playabilityStatus': {'status': 'OK'},
  'streamingData': {'adaptiveFormats': formats},
};

Map<String, dynamic> _format(
  int itag,
  String mime,
  int bitrate, {
  bool ciphered = false,
  String host = 'rr1---sn-abc.googlevideo.com',
}) => {
  'itag': itag,
  'mimeType': mime,
  'bitrate': bitrate,
  'contentLength': '${bitrate * 30}',
  if (ciphered)
    'signatureCipher': 's=abc&url=https%3A%2F%2F$host'
  else
    'url': 'https://$host/videoplayback?itag=$itag&expire=1',
};

void main() {
  final client = YoutubeAudio.clients.first;

  test('picks the best plain AAC audio', () {
    final audio = YoutubeAudio.pick(
      _player([
        _format(251, 'audio/webm; codecs="opus"', 160000),
        _format(141, 'audio/mp4; codecs="mp4a.40.2"', 256000, ciphered: true),
        _format(140, 'audio/mp4; codecs="mp4a.40.2"', 130000),
        _format(139, 'audio/mp4; codecs="mp4a.40.5"', 48000),
        _format(137, 'video/mp4; codecs="avc1"', 4000000),
        _format(
          999,
          'audio/mp4; codecs="mp4a.40.2"',
          900000,
          host: 'evil.example',
        ),
      ]),
      client,
    );
    expect(audio.url.queryParameters['itag'], '140');
    expect(audio.length, 130000 * 30);
    expect(audio.headers['User-Agent'], client.userAgent);
  });

  test('says why YouTube refused', () {
    expect(
      () => YoutubeAudio.pick({
        'playabilityStatus': {'status': 'LOGIN_REQUIRED'},
      }, client),
      throwsA(
        isA<DiscoveryException>().having(
          (e) => e.message,
          'message',
          contains('age-restricted'),
        ),
      ),
    );
    expect(
      () => YoutubeAudio.pick(
        _player([_format(251, 'audio/webm; codecs="opus"', 160000)]),
        client,
      ),
      throwsA(isA<DiscoveryException>()),
    );
  });

  test('asks as visionOS first, then the Quest app', () async {
    final asked = <String>[];
    final http.Client fake = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final name = body['context']['client']['clientName'] as String;
      asked.add(name);
      expect(body['videoId'], 'dQw4w9WgXcQ');
      expect(request.url.host, 'www.youtube.com');
      expect(request.headers['X-YouTube-Client-Name'], isNotEmpty);
      return http.Response(
        jsonEncode(
          name == 'VISIONOS'
              ? {
                  'playabilityStatus': {'status': 'UNPLAYABLE'},
                }
              : _player([_format(140, 'audio/mp4; codecs="mp4a"', 130000)]),
        ),
        200,
      );
    });
    addTearDown(fake.close);
    final audio = await YoutubeAudio(DiscoveryHttp(fake))
        .resolve('dQw4w9WgXcQ');
    expect(asked, ['VISIONOS', 'ANDROID_VR']);
    expect(audio.headers['User-Agent'], YoutubeAudio.clients.last.userAgent);
    expect(
      () => YoutubeAudio(DiscoveryHttp(fake)).resolve('not a video id'),
      throwsA(isA<DiscoveryException>()),
    );
  });
}
