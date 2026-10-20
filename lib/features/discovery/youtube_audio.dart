import 'discovery_http.dart';
import 'discovery_models.dart';
import 'discovery_sources.dart';

/// A YouTube recording's audio, looked up with one request to YouTube's own
/// player API, as desktop Lokal does before it falls back to yt-dlp
/// (`electron/online/youtubeFast.js`). The phone has no player script to run,
/// so it asks as the apps YouTube serves plain links to: visionOS first (no
/// proof-of-origin token needed), then the Quest app.
class YoutubeAudio {
  YoutubeAudio(this.http);

  final DiscoveryHttp http;

  /// The clients tried in turn, from yt-dlp's list of what YouTube serves.
  static const clients = [
    YoutubeClient(
      name: 'VISIONOS',
      id: 101,
      version: '1.02',
      userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15',
      extra: {
        'deviceMake': 'Apple',
        'deviceModel': 'RealityDevice17,1',
        'osName': 'visionOS',
        'osVersion': '26.5.23O471',
      },
    ),
    YoutubeClient(
      name: 'ANDROID_VR',
      id: 28,
      version: '1.65.10',
      userAgent: 'com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
      extra: {
        'deviceMake': 'Oculus',
        'deviceModel': 'Quest 3',
        'androidSdkVersion': 32,
        'osName': 'Android',
        'osVersion': '12L',
      },
    ),
  ];

  static final _videoId = RegExp(r'^[\w-]{11}$');

  /// The audio for [videoId], ready for `DiscoveryPlaybackCache.prepare`.
  Future<ResolvedDiscoveryAudio> resolve(
    String videoId, {
    Future<void>? cancel,
  }) async {
    if (!_videoId.hasMatch(videoId)) {
      throw const DiscoveryException('This isn’t a YouTube recording.');
    }
    DiscoveryException? failure;
    for (final client in clients) {
      try {
        final response = await http.json(
          Uri.https('www.youtube.com', '/youtubei/v1/player', {
            'prettyPrint': 'false',
          }),
          headers: {
            'User-Agent': client.userAgent,
            'Origin': 'https://www.youtube.com',
            'X-YouTube-Client-Name': '${client.id}',
            'X-YouTube-Client-Version': client.version,
          },
          body: {
            'context': {
              'client': {
                'clientName': client.name,
                'clientVersion': client.version,
                'userAgent': client.userAgent,
                ...client.extra,
                'hl': 'en',
                'gl': 'US',
              },
            },
            'videoId': videoId,
            'contentCheckOk': true,
            'racyCheckOk': true,
          },
          cancel: cancel,
        );
        return pick(response, client);
      } on DiscoveryException catch (error) {
        if (error.message == 'Request cancelled.') rethrow;
        failure = error;
      }
    }
    throw failure ??
        const DiscoveryException('YouTube didn’t give this song’s audio.');
  }

  /// The best AAC audio in a player [response]: the player plays MP4 audio,
  /// not WebM, so Opus formats are skipped.
  static ResolvedDiscoveryAudio pick(
    Map<String, dynamic> response,
    YoutubeClient client,
  ) {
    final status = response['playabilityStatus'];
    if (status is! Map || status['status'] != 'OK') {
      throw const DiscoveryException(
        'YouTube won’t play this song here. It may be age-restricted or blocked in your country.',
      );
    }
    final data = response['streamingData'];
    final formats = data is Map ? data['adaptiveFormats'] : null;
    final usable = <({Uri url, int length, int bitrate})>[];
    for (final format in formats is List ? formats : const []) {
      if (format is! Map) continue;
      final mime = '${format['mimeType'] ?? ''}';
      final url = Uri.tryParse('${format['url'] ?? ''}');
      final length = int.tryParse('${format['contentLength'] ?? ''}') ?? 0;
      // A ciphered link needs the player script, which the phone hasn't got.
      if (!mime.startsWith('audio/mp4') ||
          url == null ||
          url.scheme != 'https' ||
          !url.host.endsWith('.googlevideo.com') ||
          length <= 0) {
        continue;
      }
      final bitrate = format['bitrate'];
      usable.add((
        url: url,
        length: length,
        bitrate: bitrate is num ? bitrate.toInt() : 0,
      ));
    }
    if (usable.isEmpty) {
      throw const DiscoveryException(
        'YouTube didn’t give this song’s audio in a format the player plays.',
      );
    }
    usable.sort((a, b) => b.bitrate.compareTo(a.bitrate));
    final best = usable.first;
    return ResolvedDiscoveryAudio(
      best.url,
      length: best.length,
      headers: {'User-Agent': client.userAgent},
    );
  }
}

class YoutubeClient {
  const YoutubeClient({
    required this.name,
    required this.id,
    required this.version,
    required this.userAgent,
    this.extra = const {},
  });

  final String name;
  final int id;
  final String version;
  final String userAgent;
  final Map<String, Object> extra;
}
