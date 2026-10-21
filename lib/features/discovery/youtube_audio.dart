import 'dart:async';
import 'package:http/http.dart' as net;

import 'discovery_http.dart';
import 'discovery_models.dart';
import 'discovery_sources.dart';
import 'youtube_music_account.dart';
import 'youtube_music_store.dart';

/// A YouTube recording's audio, looked up with one request to YouTube's own
/// player API, as desktop Lokal does before it falls back to yt-dlp
/// (`electron/online/youtubeFast.js`). The phone has no player script to run,
/// so it asks as the apps YouTube serves plain links to: visionOS first (no
/// proof-of-origin token needed), then the Quest app.
class YoutubeAudio {
  YoutubeAudio(this.http, {this.session});

  final DiscoveryHttp http;

  /// Existing browser sign-in is reused when available. Anonymous playback
  /// still tries the public clients, and cookie material is only sent to
  /// YouTube Music itself.
  final YoutubeMusicSession? session;
  Future<YoutubeMusicSession?>? _sessionFuture;
  Future<String?>? _webRemixVersionFuture;

  Future<YoutubeMusicSession?> _loadSession() => _sessionFuture ??= _readSession();

  /// YouTube rotates WEB_REMIX versions; use the version from the live shell
  /// rather than relying on the stale version shipped in this app.
  Future<String?> _liveWebRemixVersion() =>
      _webRemixVersionFuture ??= _readLiveWebRemixVersion();

  Future<String?> _readLiveWebRemixVersion() async {
    try {
      final response = await http.client
          .get(
            Uri.https('music.youtube.com', '/'),
            headers: {
              'User-Agent': clients.last.userAgent,
              'Accept-Language': 'en-US,en;q=0.9',
            },
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;
      return RegExp(r'"INNERTUBE_CLIENT_VERSION"\s*:\s*"([^"]+)"')
          .firstMatch(response.body)
          ?.group(1);
    } catch (_) {
      // The live version is an optimization. Keep the last known working
      // client version when YouTube's landing page cannot be reached.
      return null;
    }
  }

  Future<YoutubeMusicSession?> _readSession() async {
    final provided = session;
    if (provided != null && provided.signedIn) return provided;
    try {
      return await YoutubeMusicSessionStore().read();
    } catch (_) {
      return null;
    }
  }

  /// Prefer clients which can return directly fetchable media URLs. YouTube
  /// periodically retires player versions and changes which clients need
  /// BotGuard/PO tokens, so one client's refusal must not imply the video is
  /// region-blocked or age-restricted.
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
    YoutubeClient(
      name: 'ANDROID',
      id: 3,
      version: '20.10.38',
      userAgent: 'com.google.android.youtube/20.10.38 (Linux; U; Android 14; en_US; Pixel 7 Pro Build/UQ1A.240205.004) gzip',
      extra: {
        'deviceMake': 'Google',
        'deviceModel': 'Pixel 7 Pro',
        'androidSdkVersion': 34,
        'osName': 'Android',
        'osVersion': '14',
      },
    ),
    YoutubeClient(
      name: 'IOS',
      id: 5,
      version: '20.10.4',
      userAgent: 'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_0 like Mac OS X;)',
      extra: {
        'deviceMake': 'Apple',
        'deviceModel': 'iPhone16,2',
        'osName': 'iOS',
        'osVersion': '18.0',
      },
    ),
    YoutubeClient(
      name: 'WEB_EMBEDDED_PLAYER',
      id: 56,
      version: '1.20260115.01.00',
      userAgent: 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36',
      embedUrl: 'https://www.youtube.com/',
    ),
    YoutubeClient(
      name: 'WEB_REMIX',
      id: 67,
      version: '1.20260114.03.00',
      host: 'music.youtube.com',
      userAgent: 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36',
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
    final signedInSession = await _loadSession();
    final signedInHeaders = signedInSession == null
        ? null
        : youtubeMusicHeaders(signedInSession);
    for (final client in clients) {
      try {
        final useSignedInMusicClient =
            client.name == 'WEB_REMIX' && signedInHeaders != null;
        final liveVersion = client.name == 'WEB_REMIX'
            ? await _liveWebRemixVersion()
            : null;
        final version = liveVersion ??
            (useSignedInMusicClient
                ? signedInSession!.clientVersion
                : null) ??
            client.version;
        final requestClient = useSignedInMusicClient
            ? YoutubeClient(
                name: client.name,
                id: client.id,
                version: version,
                userAgent: signedInSession!.userAgent,
                extra: client.extra,
                host: client.host,
                embedUrl: client.embedUrl,
              )
            : YoutubeClient(
                name: client.name,
                id: client.id,
                version: version,
                userAgent: client.userAgent,
                extra: client.extra,
                host: client.host,
                embedUrl: client.embedUrl,
              );
        final response = await http.json(
          Uri.https(client.host, '/youtubei/v1/player', {
            'prettyPrint': 'false',
          }),
          headers: {
            'User-Agent': requestClient.userAgent,
            'Origin': 'https://${client.host}',
            'X-YouTube-Client-Name': '${client.id}',
            'X-YouTube-Client-Version': version,
            if (useSignedInMusicClient) ...signedInHeaders!,
          },
          body: {
            'context': {
              'client': {
                'clientName': client.name,
                'clientVersion': version,
                'userAgent': requestClient.userAgent,
                ...client.extra,
                'hl': 'en',
                if (useSignedInMusicClient &&
                    signedInSession!.visitorData != null)
                  'visitorData': signedInSession.visitorData!,
              },
              if (client.embedUrl != null)
                'thirdParty': {'embedUrl': client.embedUrl},
            },
            'videoId': videoId,
            'contentCheckOk': true,
            'racyCheckOk': true,
          },
          cancel: cancel,
        );
        final audio = pick(response, requestClient);
        // A player response can say OK while its URL is already dead or is
        // bound to a different client identity. Verify actual media access
        // before handing the link to the downloader; a 403 from one client
        // must not prevent the next client from being tried.
        await _probeMedia(audio, cancel: cancel);
        return audio;
      } on DiscoveryException catch (error) {
        if (error.message == 'Request cancelled.') rethrow;
        failure = error;
      }
    }
    throw failure ??
        const DiscoveryException('YouTube didn’t give this song’s audio.');
  }

  Future<void> _probeMedia(
    ResolvedDiscoveryAudio audio, {
    Future<void>? cancel,
  }) async {
    final abort = Completer<void>();
    var timedOut = false;
    var cancelled = false;
    final timer = Timer(const Duration(seconds: 7), () {
      timedOut = true;
      if (!abort.isCompleted) abort.complete();
    });
    if (cancel != null) {
      unawaited(
        cancel.then((_) {
          cancelled = true;
          if (!abort.isCompleted) abort.complete();
        }),
      );
    }
    final request = net.AbortableRequest(
      'GET',
      audio.url,
      abortTrigger: abort.future,
    )
      ..followRedirects = true
      ..headers.addAll({
        'Accept': '*/*',
        'Range': 'bytes=0-16383',
        ...audio.headers,
      });
    StreamIterator<List<int>>? chunks;
    try {
      if (abort.isCompleted) {
        throw const DiscoveryException('Request cancelled.');
      }
      final pending = http.client.send(request).then((response) {
        if (abort.isCompleted) {
          unawaited(response.stream.listen(null).cancel());
          throw const DiscoveryException('Request cancelled.');
        }
        return response;
      });
      final response = await Future.any([
        pending,
        abort.future.then<net.StreamedResponse>(
          (_) => throw const DiscoveryException('Request cancelled.'),
        ),
      ]);
      if (response.statusCode != 200 && response.statusCode != 206) {
        unawaited(response.stream.listen(null).cancel());
        throw DiscoveryException(
          'YouTube refused the media URL (HTTP ${response.statusCode}).',
        );
      }
      final contentType = response.headers['content-type']?.toLowerCase();
      if (contentType != null &&
          contentType.isNotEmpty &&
          !contentType.startsWith('audio/') &&
          !contentType.startsWith('video/') &&
          !contentType.contains('octet-stream')) {
        unawaited(response.stream.listen(null).cancel());
        throw const DiscoveryException(
          'YouTube returned a non-audio response for this recording.',
        );
      }
      chunks = StreamIterator(response.stream);
      final hasChunk = await Future.any([
        chunks.moveNext().timeout(const Duration(seconds: 5)),
        abort.future.then<bool>(
          (_) => throw const DiscoveryException('Request cancelled.'),
        ),
      ]);
      if (!hasChunk || chunks.current.isEmpty || _looksLikeHtml(chunks.current)) {
        throw const DiscoveryException(
          'YouTube returned no playable audio bytes for this recording.',
        );
      }
    } catch (error) {
      if (timedOut) {
        throw const DiscoveryException('YouTube media verification timed out.');
      }
      if (cancelled) throw const DiscoveryException('Request cancelled.');
      if (error is DiscoveryException) rethrow;
      throw const DiscoveryException(
        'Could not verify the YouTube media URL. Trying another player client.',
      );
    } finally {
      timer.cancel();
      if (!abort.isCompleted) abort.complete();
      await chunks?.cancel();
    }
  }

  static bool _looksLikeHtml(List<int> bytes) {
    final prefix = String.fromCharCodes(bytes.take(96)).trimLeft().toLowerCase();
    return prefix.startsWith('<!doctype html') ||
        prefix.startsWith('<html') ||
        prefix.startsWith('<?xml');
  }

  /// The best AAC audio in a player [response]: the player plays MP4 audio,
  /// not WebM, so Opus formats are skipped.
  static ResolvedDiscoveryAudio pick(
    Map<String, dynamic> response,
    YoutubeClient client,
  ) {
    final status = response['playabilityStatus'];
    if (status is! Map || status['status'] != 'OK') {
      throw DiscoveryException(_playabilityMessage(status));
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

String _playabilityMessage(Object? value) {
  if (value is! Map) {
    return 'YouTube returned no playback status. Try again or choose another source.';
  }
  final status = '${value['status'] ?? 'UNKNOWN'}';
  final rawReason = value['reason'];
  final reason = rawReason is String ? rawReason.trim() : '';
  final lower = reason.toLowerCase();
  if (status == 'AGE_CHECK_REQUIRED' ||
      status == 'AGE_VERIFICATION_REQUIRED' ||
      lower.contains('age-restricted') ||
      lower.contains('age restricted') ||
      lower.contains('age verification')) {
    return 'YouTube requires age verification for this recording.';
  }
  if (lower.contains('not available in your country') ||
      lower.contains('not available in your region') ||
      lower.contains('geographic')) {
    return 'YouTube reports that this recording is unavailable in your region.';
  }
  if (status == 'LOGIN_REQUIRED' ||
      lower.contains('sign in to confirm') ||
      lower.contains('confirm you’re not a bot') ||
      lower.contains("confirm you're not a bot")) {
    return 'YouTube requires additional verification before this recording can play. Try again or use another source.';
  }
  if (status == 'UNPLAYABLE' || status == 'ERROR') {
    return 'YouTube refused playback ($status)${reason.isEmpty ? '' : ': $reason'}';
  }
  return 'YouTube refused playback ($status)${reason.isEmpty ? '' : ': $reason'}';
}

class YoutubeClient {
  const YoutubeClient({
    required this.name,
    required this.id,
    required this.version,
    required this.userAgent,
    this.extra = const {},
    this.host = 'www.youtube.com',
    this.embedUrl,
  });

  final String name;
  final int id;
  final String version;
  final String userAgent;
  final Map<String, Object> extra;
  final String host;
  final String? embedUrl;
}
