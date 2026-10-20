import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'lastfm_discovery.dart';

const _origin = 'https://music.youtube.com';
const _fallbackClientVersion = '1.20250901.03.00';
const _fallbackUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36';
final _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');
final _clock = RegExp(r'^(?:\d+:)?\d{1,2}:\d{2}$');

/// Account cookies and page context captured after interactive sign-in.
class YoutubeMusicSession {
  const YoutubeMusicSession({
    required this.cookies,
    this.userAgent = _fallbackUserAgent,
    this.sessionIndex,
    this.delegatedSessionId,
    this.visitorData,
    this.clientVersion,
  });

  final Map<String, String> cookies;
  final String userAgent;
  final String? sessionIndex;
  final String? delegatedSessionId;
  final String? visitorData;
  final String? clientVersion;

  static const identityCookies = [
    'SID',
    '__Secure-1PSID',
    '__Secure-3PSID',
    'SAPISID',
    '__Secure-1PAPISID',
    '__Secure-3PAPISID',
    'LOGIN_INFO',
  ];

  String? get _sapisid {
    for (final name in [
      'SAPISID',
      '__Secure-3PAPISID',
      '__Secure-1PAPISID',
    ]) {
      final value = cookies[name];
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  bool get signedIn => _sapisid != null;

  /// Non-reversible account identity for caches; raw cookies aren't cache keys.
  String get accountKey => sha256
      .convert(utf8.encode([
        for (final name in identityCookies)
          name + '=' + (cookies[name] ?? ''),
      ].join(';')))
      .toString()
      .substring(0, 24);

  YoutubeMusicSession withCookies(Map<String, String> updated) =>
      YoutubeMusicSession(
        cookies: {...cookies, ...updated},
        userAgent: userAgent,
        sessionIndex: sessionIndex,
        delegatedSessionId: delegatedSessionId,
        visitorData: visitorData,
        clientVersion: clientVersion,
      );

  static Map<String, String> parseCookieHeader(String header) => {
    for (final part in header.split(';'))
      if (part.indexOf('=') case final at when at > 0)
        part.substring(0, at).trim(): part.substring(at + 1).trim(),
  };

  Map<String, Object?> toJson() => {
    'version': 1,
    'cookies': cookies,
    'userAgent': userAgent,
    'sessionIndex': sessionIndex,
    'delegatedSessionId': delegatedSessionId,
    'visitorData': visitorData,
    'clientVersion': clientVersion,
  };

  static YoutubeMusicSession? fromJson(Object? value) {
    if (value is! Map || value['version'] != 1 || value['cookies'] is! Map) {
      return null;
    }
    String? text(Object? item) =>
        item is String && item.trim().isNotEmpty ? item.trim() : null;
    return YoutubeMusicSession(
      cookies: {
        for (final MapEntry(:key, :value) in (value['cookies'] as Map).entries)
          if (key is String && value is String) key: value,
      },
      userAgent: text(value['userAgent']) ?? _fallbackUserAgent,
      sessionIndex: text(value['sessionIndex']),
      delegatedSessionId: text(value['delegatedSessionId']),
      visitorData: text(value['visitorData']),
      clientVersion: text(value['clientVersion']),
    );
  }
}

/// Builds the signed request headers. [now] is injectable for deterministic tests.
Map<String, String>? youtubeMusicHeaders(
  YoutubeMusicSession session, {
  DateTime? now,
}) {
  final sapisid = session._sapisid;
  if (sapisid == null) return null;
  final timestamp = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
  String signed(String scheme, String value) {
    final digest = sha1.convert(utf8.encode(
      timestamp.toString() + ' ' + value + ' ' + _origin,
    ));
    return scheme + ' ' + timestamp.toString() + '_' + digest.toString();
  }

  final authorization = [signed('SAPISIDHASH', sapisid)];
  for (final entry in [
    ('SAPISID1PHASH', '__Secure-1PAPISID'),
    ('SAPISID3PHASH', '__Secure-3PAPISID'),
  ]) {
    final value = session.cookies[entry.$2];
    if (value != null && value.isNotEmpty) {
      authorization.add(signed(entry.$1, value));
    }
  }
  final cookies = {...session.cookies};
  cookies.putIfAbsent('SAPISID', () => sapisid);
  return {
    'Content-Type': 'application/json',
    'Origin': _origin,
    'Referer': _origin + '/',
    'User-Agent': session.userAgent,
    'Cookie': [
      for (final MapEntry(:key, :value) in cookies.entries) key + '=' + value,
    ].join('; '),
    'Authorization': authorization.join(' '),
    'X-Origin': _origin,
    'X-YouTube-Client-Name': '67',
    'X-YouTube-Client-Version':
        session.clientVersion ?? _fallbackClientVersion,
    'X-Goog-AuthUser': session.sessionIndex ?? '0',
    if (session.visitorData != null) 'X-Goog-Visitor-Id': session.visitorData!,
    if (session.delegatedSessionId != null)
      'X-Goog-PageId': session.delegatedSessionId!,
  };
}

List<Object?> _list(Object? value) => value is List ? value : const [];

Object? _at(Object? value, List<Object> path) {
  var node = value;
  for (final step in path) {
    if (step is int) {
      if (node is! List || step < 0 || step >= node.length) return null;
      node = node[step];
    } else {
      if (node is! Map) return null;
      node = node[step];
    }
  }
  return node;
}

String _text(Object? value) {
  if (value is String) return value;
  if (value is! Map) return '';
  if (value['simpleText'] != null) return value['simpleText'].toString();
  return [
    for (final run in _list(value['runs']))
      if (run is Map) (run['text'] ?? '').toString(),
  ].join();
}

String _thumbnail(Object? value) {
  final urls = <String>[];
  void visit(Object? node, int depth) {
    if (depth > 14) return;
    if (node is Map) {
      if (node['url'] is String &&
          node['width'] is num &&
          node['height'] is num) {
        urls.add(node['url'] as String);
      }
      for (final child in node.values) {
        visit(child, depth + 1);
      }
    } else if (node is List) {
      for (final child in node) {
        visit(child, depth + 1);
      }
    }
  }

  visit(value, 0);
  if (urls.isEmpty) return '';
  return urls.last.replaceFirst(RegExp(r'=w\d+-h\d+[^&?]*$'), '=w544-h544-l90-rj');
}

String _pageType(Object? endpoint) => (_at(endpoint, [
  'browseEndpointContextSupportedConfigs',
  'browseEndpointContextMusicConfig',
  'pageType',
]) ?? '').toString();

Duration? _duration(Object? raw) {
  final value = _text(raw).trim();
  if (!_clock.hasMatch(value)) return null;
  final parts = value.split(':').map(int.tryParse).toList();
  if (parts.any((part) => part == null)) return null;
  if (parts.skip(1).any((part) => part! >= 60)) return null;
  return Duration(seconds: parts.fold<int>(0, (n, p) => n * 60 + p!));
}

void _walk(Object? root, void Function(Map node) visit, {int maxNodes = 40000}) {
  var count = 0;
  void walk(Object? value, int depth) {
    if (++count > maxNodes || depth > 45) return;
    if (value is Map) {
      visit(value);
      for (final child in value.values) {
        walk(child, depth + 1);
      }
    } else if (value is List) {
      for (final child in value) {
        walk(child, depth + 1);
      }
    }
  }

  walk(root, 0);
}

typedef _Metadata = ({
  String artist,
  String album,
  Duration? duration,
  String? kind,
});

_Metadata _metadata(Iterable<Object?> rawRuns) {
  final artists = <String>[];
  final loose = <String>[];
  String? album;
  Duration? duration;
  String? kind;
  for (final run in rawRuns) {
    final text = _text(run).trim();
    if (text.isEmpty || text == '•') continue;
    final browse = _at(run, ['navigationEndpoint', 'browseEndpoint']);
    final type = _pageType(browse);
    final id = (_at(browse, ['browseId']) ?? '').toString();
    if (type.endsWith('_ARTIST') ||
        type.endsWith('_USER_CHANNEL') ||
        id.startsWith('UC')) {
      artists.add(text);
    } else if (type.endsWith('_ALBUM') || id.startsWith('MPRE')) {
      album = text;
    } else if (_duration(text) case final length?) {
      duration = length;
    } else if (!RegExp(
      r'\b(views|plays|listeners|subscribers)$',
      caseSensitive: false,
    ).hasMatch(text)) {
      loose.add(text);
    }
  }
  if (loose.isNotEmpty &&
      RegExp(r'^(song|video|episode)$', caseSensitive: false)
          .hasMatch(loose.first)) {
    kind = loose.removeAt(0).toLowerCase();
  }
  if (artists.isEmpty && loose.isNotEmpty) artists.add(loose.removeAt(0));
  album ??= loose.where((text) => !artists.contains(text)).firstOrNull;
  return (
    artist: artists.toSet().join(', '),
    album: album ?? '',
    duration: duration,
    kind: kind,
  );
}

List<Object?> _columnRuns(Map renderer, int index) =>
    _list(_at(renderer, [
      'flexColumns',
      index,
      'musicResponsiveListItemFlexColumnRenderer',
      'text',
      'runs',
    ]));

List<Object?> _bylineRuns(Object? byline) {
  final runs = _list(_at(byline, ['runs']));
  if (runs.any((run) => run is Map && run['navigationEndpoint'] != null)) {
    return runs;
  }
  return [for (final line in _text(byline).split('•')) {'text': line}];
}

LokalDiscoveryTrack? _listItem(Map renderer) {
  final titleRuns = _columnRuns(renderer, 0);
  final watch = _at(titleRuns.firstOrNull, [
        'navigationEndpoint',
        'watchEndpoint',
      ]) ??
      _at(renderer, ['navigationEndpoint', 'watchEndpoint']);
  final rawId = _at(renderer, ['playlistItemData', 'videoId']) ??
      _at(watch, ['videoId']);
  final id = rawId?.toString() ?? '';
  if (!_videoId.hasMatch(id)) return null;
  final columns = _list(renderer['flexColumns']);
  final runs = <Object?>[
    for (var i = 1; i < columns.length; i++) ..._columnRuns(renderer, i),
    for (final column in _list(renderer['fixedColumns']))
      ..._list(_at(column, [
        'musicResponsiveListItemFixedColumnRenderer',
        'text',
        'runs',
      ])),
  ];
  final meta = _metadata(runs);
  if (meta.kind == 'episode') return null;
  return _track(
    id,
    titleRuns.map(_text).join().trim(),
    meta.artist,
    meta.album,
    meta.duration,
    _thumbnail(renderer['thumbnail']),
  );
}

LokalDiscoveryTrack? _panelItem(Map panel) {
  final id = (panel['videoId'] ?? '').toString();
  if (!_videoId.hasMatch(id)) return null;
  final meta = _metadata(
    _bylineRuns(panel['longBylineText'] ?? panel['shortBylineText']),
  );
  return _track(
    id,
    _text(panel['title']),
    meta.artist,
    meta.album,
    _duration(panel['lengthText']) ?? meta.duration,
    _thumbnail(panel['thumbnail']),
  );
}

LokalDiscoveryTrack? _trackCard(Map renderer) {
  final endpoints = [
    renderer['navigationEndpoint'],
    renderer['onTap'],
    for (final run in _list(_at(renderer, ['title', 'runs'])))
      _at(run, ['navigationEndpoint']),
  ];
  if (endpoints.any((endpoint) =>
      _at(endpoint, ['watchPlaylistEndpoint']) != null ||
      (_at(endpoint, ['browseEndpoint', 'browseId']) ?? '').toString().startsWith('VL'))) {
    return null;
  }
  final id = endpoints
      .map((endpoint) => (_at(endpoint, ['watchEndpoint', 'videoId']) ?? '').toString())
      .firstWhere(_videoId.hasMatch, orElse: () => '');
  final title = _text(renderer['title']);
  if (id.isEmpty || title.isEmpty) return null;
  final meta = _metadata(_bylineRuns(renderer['subtitle']));
  if (meta.kind == 'episode') return null;
  return _track(
    id,
    title,
    meta.artist.isEmpty ? 'Unknown Artist' : meta.artist,
    meta.album,
    meta.duration,
    _thumbnail(renderer['thumbnailRenderer'] ?? renderer['thumbnail']),
  );
}

LokalDiscoveryTrack _track(
  String id,
  String title,
  String artist,
  String album,
  Duration? duration,
  String artwork,
) => LokalDiscoveryTrack(
  title: title,
  artist: artist,
  album: album,
  artworkUrl: artwork,
  url: _origin + '/watch?v=' + id,
  videoId: id,
  duration: duration,
);

/// Parses songs from account shelves and playlist pages, preserving order.
List<LokalDiscoveryTrack> parseYoutubeMusicTracks(
  Object? root, {
  int limit = 100,
}) {
  final tracks = <LokalDiscoveryTrack>[];
  final seen = <String>{};
  _walk(root, (node) {
    if (tracks.length >= limit) return;
    final row = node['musicResponsiveListItemRenderer'];
    final panel = node['playlistPanelVideoRenderer'];
    final card = node['musicTwoRowItemRenderer'];
    final track = row is Map
        ? _listItem(row)
        : panel is Map
            ? _panelItem(panel)
            : card is Map
                ? _trackCard(card)
                : null;
    if (track == null || track.title.isEmpty || track.videoId == null) return;
    if (seen.add(track.videoId!)) tracks.add(track);
  });
  return tracks;
}

/// Parses playlist cards, including provider-owned radio mixes.
List<LokalDiscoveryMix> parseYoutubeMusicPlaylists(
  Object? root, {
  int limit = 100,
}) {
  final playlists = <String, LokalDiscoveryMix>{};
  _walk(root, (node) {
    if (playlists.length >= limit) return;
    final renderer = node['gridPlaylistRenderer'] ?? node['musicTwoRowItemRenderer'];
    if (renderer is! Map) return;
    final endpoints = <Object?>[
      for (final run in _list(_at(renderer, ['title', 'runs'])))
        _at(run, ['navigationEndpoint']),
      renderer['navigationEndpoint'],
      renderer['onTap'],
    ];
    final browse = endpoints
        .map((endpoint) => _at(endpoint, ['browseEndpoint']))
        .whereType<Map>()
        .firstOrNull;
    final type = _pageType(browse);
    final rawId = renderer['playlistId'] ??
        _at(browse, ['browseId']) ??
        endpoints
            .map((endpoint) =>
                _at(endpoint, ['watchPlaylistEndpoint', 'playlistId']) ??
                _at(endpoint, ['watchEndpoint', 'playlistId']))
            .firstWhere((value) => value != null, orElse: () => null);
    var id = rawId?.toString() ?? '';
    if (id.startsWith('VL')) id = id.substring(2);
    if (id.isEmpty ||
        id.startsWith('UC') ||
        id.startsWith('MPRE') ||
        id.startsWith('FE') ||
        (type.isNotEmpty && !type.endsWith('_PLAYLIST') && !id.startsWith('RD')) ||
        (id.startsWith('RD') && id.length < 8)) {
      return;
    }
    final title = _text(renderer['title']);
    if (title.isEmpty) return;
    playlists.putIfAbsent(id, () => LokalDiscoveryMix(
      id: id,
      title: title,
      author: _text(renderer['shortBylineText'] ?? renderer['subtitle']),
      artworkUrl: _thumbnail(renderer['thumbnailRenderer'] ?? renderer['thumbnail']),
    ));
  });
  return playlists.values.toList();
}

final _mixTitle = RegExp(
  r'^(mixed for you|mixes for you|your mixes)$',
  caseSensitive: false,
);

String _shelfTitle(Map shelf) => _text(
  _at(shelf, ['header', 'musicCarouselShelfBasicHeaderRenderer', 'title']) ??
      _at(shelf, ['header', 'musicShelfHeaderRenderer', 'title']) ??
      shelf['title'],
).trim();

List<LokalDiscoveryMix> parseYoutubeMusicMixes(Object? root) {
  final mixes = <String, LokalDiscoveryMix>{};
  _walk(root, (node) {
    final shelf = node['musicCarouselShelfRenderer'] ?? node['musicShelfRenderer'];
    if (shelf is! Map) return;
    final named = _mixTitle.hasMatch(_shelfTitle(shelf));
    for (final mix in parseYoutubeMusicPlaylists(shelf['contents'], limit: 200)) {
      if (named || mix.id.startsWith('RDTMAK')) {
        mixes.putIfAbsent(mix.id, () => mix);
      }
    }
  });
  return mixes.values.toList();
}

List<LokalDiscoveryArtist> parseYoutubeMusicArtists(Object? root) {
  final artists = <String, LokalDiscoveryArtist>{};
  _walk(root, (node) {
    final row = node['musicTwoRowItemRenderer'] ?? node['musicResponsiveListItemRenderer'];
    if (row is! Map) return;
    final titleRuns = _columnRuns(row, 0);
    final endpoint = _at(row, ['navigationEndpoint', 'browseEndpoint']) ??
        _at(titleRuns.firstOrNull, ['navigationEndpoint', 'browseEndpoint']);
    final id = (_at(endpoint, ['browseId']) ?? '').toString();
    final title = _text(row['title']).isNotEmpty
        ? _text(row['title'])
        : titleRuns.map(_text).join();
    if (title.isEmpty ||
        (!_pageType(endpoint).endsWith('_ARTIST') && !id.startsWith('UC'))) {
      return;
    }
    artists.putIfAbsent(id, () => LokalDiscoveryArtist(
      name: title,
      image: _thumbnail(row['thumbnailRenderer'] ?? row['thumbnail']),
    ));
  });
  return artists.values.take(30).toList();
}

bool youtubeMusicLoggedOut(Map<String, dynamic> json) {
  final context = json['responseContext'];
  if (context is! Map) return false;
  final web = context['mainAppWebResponseContext'];
  if (web is Map && web['loggedOut'] == true) return true;
  for (final service in _list(context['serviceTrackingParams'])) {
    if (service is! Map) continue;
    for (final param in _list(service['params'])) {
      if (param is Map && param['key'] == 'logged_in' &&
          (param['value'] ?? '').toString() == '0') {
        return true;
      }
    }
  }
  return false;
}

bool _confirmsSignedIn(Map<String, dynamic> json) {
  final context = json['responseContext'];
  if (context is! Map) return false;
  final web = context['mainAppWebResponseContext'];
  if (web is Map && web['loggedOut'] == false) return true;
  for (final service in _list(context['serviceTrackingParams'])) {
    if (service is! Map) continue;
    for (final param in _list(service['params'])) {
      if (param is Map && param['key'] == 'logged_in' &&
          (param['value'] ?? '').toString() == '1') {
        return true;
      }
    }
  }
  return false;
}

class YoutubeMusicSignedOut implements Exception {
  const YoutubeMusicSignedOut([
    this.message = 'YouTube Music rejected the saved session. Sign in again in Integrations.',
  ]);
  final String message;
  @override
  String toString() => message;
}

class YoutubeMusicAccountData {
  const YoutubeMusicAccountData({
    required this.liked,
    required this.home,
    required this.homePlaylists,
    required this.mixes,
    required this.history,
    required this.artists,
    this.homeError,
    this.mixError,
  });

  final List<LokalDiscoveryTrack>? liked;
  final List<LokalDiscoveryTrack> home;
  final List<LokalDiscoveryMix> homePlaylists;
  final List<LokalDiscoveryMix> mixes;
  final List<LokalDiscoveryTrack>? history;
  final List<LokalDiscoveryArtist> artists;
  final String? homeError;
  final String? mixError;
}

List<String> _continuations(Object? root) {
  final tokens = <String>{};
  _walk(root, (node) {
    for (final item in _list(node['continuations'])) {
      final token = _at(item, ['nextContinuationData', 'continuation']);
      if (token is String && token.isNotEmpty) tokens.add(token);
    }
    final token = _at(node, ['continuationEndpoint', 'continuationCommand', 'token']);
    if (token is String && token.isNotEmpty) tokens.add(token);
    for (final item in _list(node['contents'] ?? node['items'] ?? node['continuationItems'])) {
      final next = _at(item, [
        'continuationItemRenderer',
        'continuationEndpoint',
        'continuationCommand',
        'token',
      ]);
      if (next is String && next.isNotEmpty) tokens.add(next);
    }
  });
  return tokens.toList();
}

/// Makes signed-in account requests and persists rotated non-identity cookies.
class YoutubeMusicAccount {
  YoutubeMusicAccount(
    this.client,
    this.session, {
    this.onSessionChanged,
    this.timeout = const Duration(seconds: 12),
  });

  final http.Client client;
  YoutubeMusicSession session;
  final void Function(YoutubeMusicSession session)? onSessionChanged;
  final Duration timeout;

  Future<Map<String, dynamic>> request(
    String endpoint,
    Map<String, Object?> body, {
    String? continuation,
    Duration? timeout,
  }) async {
    final headers = youtubeMusicHeaders(session);
    if (headers == null) {
      throw const YoutubeMusicSignedOut('Sign in to YouTube Music in Integrations.');
    }
    final uri = Uri.https('music.youtube.com', '/youtubei/v1/' + endpoint, {
      'prettyPrint': 'false',
      if (continuation != null) 'continuation': continuation,
      if (continuation != null) 'ctoken': continuation,
    });
    final response = await client.post(
      uri,
      headers: headers,
      body: jsonEncode({
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': session.clientVersion ?? _fallbackClientVersion,
            'hl': 'en',
            if (session.visitorData != null) 'visitorData': session.visitorData,
          },
          'user': {
            if (session.delegatedSessionId != null)
              'onBehalfOfUser': session.delegatedSessionId,
          },
        },
        ...body,
        if (continuation != null) 'continuation': continuation,
      }),
    ).timeout(timeout ?? this.timeout);
    _keepCookies(response.headers['set-cookie']);
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const YoutubeMusicSignedOut();
    }
    if (response.statusCode != 200) {
      throw LokalDiscoveryFailure(
        'YouTube Music account request failed (' + response.statusCode.toString() + ').',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const LokalDiscoveryFailure('YouTube Music returned an unreadable answer.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const LokalDiscoveryFailure('YouTube Music returned an unreadable answer.');
    }
    if (youtubeMusicLoggedOut(decoded)) throw const YoutubeMusicSignedOut();
    return decoded;
  }

  Future<Map<String, dynamic>> browse(
    String browseId, {
    String? params,
    String? continuation,
    Duration? timeout,
  }) => request(
    'browse',
    {'browseId': browseId, if (params != null) 'params': params},
    continuation: continuation,
    timeout: timeout,
  );

  Future<Map<String, dynamic>> _firstPage(String browseId) =>
      browse(browseId, timeout: const Duration(seconds: 10));

  void _keepCookies(String? header) {
    if (header == null || header.isEmpty) return;
    final updated = <String, String>{};
    for (final raw in header.split(RegExp(r',(?=\s*[\w.-]+=)'))) {
      final pair = raw.split(';').first;
      final at = pair.indexOf('=');
      if (at <= 0) continue;
      final name = pair.substring(0, at).trim();
      final value = pair.substring(at + 1).trim();
      if (value.isEmpty || YoutubeMusicSession.identityCookies.contains(name)) {
        continue;
      }
      if (session.cookies[name] != value) updated[name] = value;
    }
    if (updated.isNotEmpty) {
      session = session.withCookies(updated);
      onSessionChanged?.call(session);
    }
  }

  Future<({List<Object?> pages, String? error})> _pages(
    String browseId,
    Object? first, {
    bool stopAtMixShelf = false,
  }) async {
    final pages = <Object?>[first];
    final seen = <String>{};
    final pending = _continuations(first);
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (pending.isNotEmpty && pages.length < 10) {
      if (stopAtMixShelf && parseYoutubeMusicMixes(pages).isNotEmpty) break;
      final token = pending.removeAt(0);
      if (!seen.add(token)) continue;
      final left = deadline.difference(DateTime.now());
      if (left <= Duration.zero) {
        return (pages: pages, error: 'YouTube Music loading timed out. Refresh to retry.');
      }
      try {
        final page = await browse(
          browseId,
          continuation: token,
          timeout: left < const Duration(seconds: 5) ? left : const Duration(seconds: 5),
        );
        pages.add(page);
        pending.addAll(_continuations(page).where((value) => !seen.contains(value)));
      } on YoutubeMusicSignedOut {
        rethrow;
      } catch (_) {
        return (pages: pages, error: 'Some YouTube Music recommendations could not be loaded.');
      }
    }
    return (pages: pages, error: null);
  }

  Future<YoutubeMusicAccountData> fetch({int limit = 100}) async {
    final errors = <Object>[];
    Future<Map<String, dynamic>?> attempt(String id) async {
      try {
        return await _firstPage(id);
      } catch (error) {
        errors.add(error);
        return null;
      }
    }

    final results = await Future.wait([
      attempt('VLLM'),
      attempt('FEmusic_home'),
      attempt('FEmusic_history'),
    ]);
    final liked = results[0];
    final home = results[1];
    final history = results[2];
    final answered = results.whereType<Map<String, dynamic>>().toList();
    if (!answered.any(_confirmsSignedIn)) {
      final signedOut = errors.whereType<YoutubeMusicSignedOut>().firstOrNull;
      if (signedOut != null || answered.isNotEmpty) {
        throw signedOut ?? const YoutubeMusicSignedOut();
      }
      throw LokalDiscoveryFailure(
        errors.isEmpty ? 'YouTube Music did not answer.' : _message(errors.first),
      );
    }

    var homePages = <Object?>[];
    String? mixError;
    if (home != null) {
      final result = await _pages('FEmusic_home', home, stopAtMixShelf: true);
      homePages = result.pages;
      mixError = result.error;
    }
    final mixes = <String, LokalDiscoveryMix>{
      for (final mix in parseYoutubeMusicMixes(homePages)) mix.id: mix,
    };
    final likedTracks = liked == null ? null : parseYoutubeMusicTracks(liked, limit: limit);
    final homeTracks = parseYoutubeMusicTracks(homePages, limit: limit);
    final historyTracks = history == null
        ? null
        : parseYoutubeMusicTracks(history, limit: limit);
    return YoutubeMusicAccountData(
      liked: likedTracks,
      home: homeTracks,
      homePlaylists: parseYoutubeMusicPlaylists(homePages),
      mixes: mixes.values.toList(),
      history: historyTracks,
      artists: parseYoutubeMusicArtists(homePages),
      homeError: home == null && errors.isNotEmpty ? _message(errors.first) : null,
      mixError: mixError,
    );
  }

  Future<List<LokalDiscoveryTrack>> playlist(String id) async {
    final root = id.startsWith('RD')
        ? await request('next', {
            'playlistId': id,
            'enablePersistentPlaylistPanel': true,
            'isAudioOnly': true,
            'tunerSettingValue': 'AUTOMIX_SETTING_NORMAL',
          })
        : await browse('VL' + id);
    return parseYoutubeMusicTracks(root, limit: 500);
  }
}

String _message(Object error) => switch (error) {
  YoutubeMusicSignedOut(:final message) => message,
  LokalDiscoveryFailure(:final message) => message,
  TimeoutException() => 'YouTube Music took too long to answer.',
  _ => 'YouTube Music couldn’t be reached. Check your connection.',
};

class _Cached {
  const _Cached(this.at, this.data);
  final DateTime at;
  final YoutubeMusicAccountData data;
}

final _cache = <String, _Cached>{};
final _playlistCache = <String, List<LokalDiscoveryTrack>>{};

void forgetYoutubeMusicAccount() {
  _cache.clear();
  _playlistCache.clear();
}

Future<LokalDiscovery> loadYoutubeMusicDiscovery(
  YoutubeMusicAccount account, {
  int page = 0,
  bool force = false,
  DateTime? now,
}) async {
  final at = now ?? DateTime.now();
  final key = account.session.accountKey;
  final cached = _cache[key];
  final YoutubeMusicAccountData data;
  if (!force &&
      cached != null &&
      !at.isBefore(cached.at) &&
      at.difference(cached.at) < const Duration(minutes: 5)) {
    data = cached.data;
  } else {
    data = await account.fetch();
    _cache.remove(key);
    _cache[key] = _Cached(at, data);
    while (_cache.length > 4) {
      _cache.remove(_cache.keys.first);
    }
  }

  final warnings = <String>[];
  final picks = <LokalDiscoveryTrack>[];
  final playlists = data.homePlaylists;
  if (playlists.isNotEmpty) {
    final start = (page * 2) % playlists.length;
    final selected = <LokalDiscoveryMix>{
      playlists[start],
      playlists[(start + 1) % playlists.length],
    };
    for (final mix in selected) {
      final cacheKey = key + ':' + mix.id;
      try {
        picks.addAll(_playlistCache[cacheKey] ??=
            await account.playlist(mix.id));
      } on YoutubeMusicSignedOut {
        rethrow;
      } catch (error) {
        warnings.add(mix.title + ': ' + _message(error));
      }
    }
  }
  final seen = <String>{};
  final candidates = [
    for (final track in [...data.home, ...picks])
      if (track.title.isNotEmpty &&
          track.artist.isNotEmpty &&
          seen.add(track.key))
        track,
  ];
  final artists = <String, LokalDiscoveryArtist>{
    for (final artist in data.artists) artist.name.toLowerCase(): artist,
  };
  for (final track in candidates) {
    if (artists.length >= 30) break;
    final name = track.artist.split(',').first.trim();
    if (name.isNotEmpty) {
      artists.putIfAbsent(name.toLowerCase(), () => LokalDiscoveryArtist(name: name));
    }
  }
  if (data.homeError != null) warnings.add(data.homeError!);
  return LokalDiscovery(
    account: key,
    page: page,
    warnings: warnings,
    mixes: data.mixes,
    mixError: data.mixError,
    liked: data.liked?.take(30).toList(),
    history: data.history,
    artists: artists.values.take(30).toList(),
    freshFinds: candidates.take(30).toList(),
    candidates: candidates,
  );
}

Future<List<LokalDiscoveryTrack>> youtubeMusicMix(
  YoutubeMusicAccount account,
  String id,
) async => _playlistCache[account.session.accountKey + ':' + id] ??=
    await account.playlist(id);
