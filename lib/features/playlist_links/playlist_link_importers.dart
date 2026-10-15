import 'dart:convert';

import 'playlist_link_http.dart';
import 'playlist_link_models.dart';

abstract interface class PlaylistLinkImporter {
  Future<RemotePlaylistSnapshot> fetch(
    ParsedPlaylistLink link, {
    PlaylistLinkCancellationToken? cancellation,
  });
}

class PublicPlaylistImporter implements PlaylistLinkImporter {
  final PlaylistLinkTransport transport;
  final SpotifyPlaylistImporter spotify;
  final YoutubePlaylistImporter youtube;

  PublicPlaylistImporter({PlaylistLinkTransport? transport})
    : this._(transport ?? BoundedPlaylistLinkTransport());

  PublicPlaylistImporter._(this.transport)
    : spotify = SpotifyPlaylistImporter(transport),
      youtube = YoutubePlaylistImporter(transport);

  @override
  Future<RemotePlaylistSnapshot> fetch(
    ParsedPlaylistLink link, {
    PlaylistLinkCancellationToken? cancellation,
  }) {
    switch (link.source) {
      case PlaylistLinkSource.spotify:
        return spotify.fetch(link, cancellation: cancellation);
      case PlaylistLinkSource.youtube:
        return youtube.fetch(link, cancellation: cancellation);
    }
  }

  void close() {
    transport.close();
  }
}

/// Public Spotify playlist semantics deliberately use only the embed page.
/// That page may stop at a prefix of a playlist; the result is always marked
/// partial so a refresh can never delete or reorder based on missing rows.
class SpotifyPlaylistImporter implements PlaylistLinkImporter {
  static const int maxResponseBytes = 4 * 1024 * 1024;
  static const Duration requestTimeout = Duration(seconds: 15);
  static const int embedEntryCap = 100;

  final PlaylistLinkTransport transport;

  const SpotifyPlaylistImporter(this.transport);

  @override
  Future<RemotePlaylistSnapshot> fetch(
    ParsedPlaylistLink link, {
    PlaylistLinkCancellationToken? cancellation,
  }) async {
    final response = await transport.request(
      'GET',
      Uri.parse('https://open.spotify.com/embed/playlist/${link.remoteId}'),
      headers: const {
        'Accept': 'text/html,application/xhtml+xml',
        'User-Agent': 'Mozilla/5.0 Konnekted playlist importer',
      },
      maxBytes: maxResponseBytes,
      timeout: requestTimeout,
      cancellation: cancellation,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PlaylistLinkHttpException(
        'Spotify did not return a public playlist (HTTP ${response.statusCode}).',
      );
    }

    cancellation?.throwIfCancelled();
    final jsonText = _nextDataScript(response.body);
    if (jsonText == null) {
      throw const PlaylistLinkHttpException(
        'Spotify did not expose public playlist metadata. The playlist may be private.',
      );
    }

    final root = _decodeJson(jsonText);
    final entity = _spotifyEntity(root);
    if (entity == null) {
      throw const PlaylistLinkHttpException(
        'Spotify public playlist metadata is unavailable.',
      );
    }

    final rawEntries = _spotifyEntries(entity);
    final entries = <RemotePlaylistEntry>[];
    for (final raw in rawEntries.take(embedEntryCap)) {
      if (raw is! Map) continue;
      final track = raw['track'] is Map ? raw['track'] : raw;
      if (track is! Map) continue;
      final title = _string(track['title']) ?? _string(track['name']);
      if (title == null || title.trim().isEmpty) continue;
      final artist = _spotifyArtist(track);
      final album = _spotifyAlbum(track);
      entries.add(
        RemotePlaylistEntry(
          title: title.trim(),
          artist: artist,
          album: album,
          duration: _duration(track['duration_ms'] ?? track['durationMs']),
          remoteId: _string(track['uri']) ?? _string(track['id']),
        ),
      );
    }
    if (entries.isEmpty) {
      throw const PlaylistLinkHttpException(
        'No public Spotify tracks were found.',
      );
    }

    final title =
        _string(entity['name']) ??
        _string(entity['title']) ??
        'Imported Spotify Playlist';
    final total =
        _number(entity['totalTracks'])?.toInt() ??
        (entity['tracks'] is Map
            ? _number((entity['tracks'] as Map)['total'])?.toInt()
            : null);
    final partialMessage = total != null && total > entries.length
        ? 'Spotify embed exposed ${entries.length} of $total tracks.'
        : 'Spotify public embed data is a partial listing; account/API access is not used.';

    return RemotePlaylistSnapshot(
      title: title.trim().isEmpty ? 'Imported Spotify Playlist' : title.trim(),
      description: _string(entity['description']),
      thumbnailUrl: _spotifyImage(entity),
      entries: entries,
      totalEntries: total ?? entries.length,
      complete: false,
      truncationReason: partialMessage,
    );
  }

  static String? _nextDataScript(String html) {
    final match = RegExp(
      r'''<script[^>]*id=["']__NEXT_DATA__["'][^>]*>(.*?)</script>''',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(html);
    return match?.group(1);
  }

  static Map<String, dynamic> _decodeJson(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Use a stable message instead of returning page content to the UI.
    }
    throw const PlaylistLinkHttpException(
      'Spotify returned invalid playlist metadata.',
    );
  }

  static Map<String, dynamic>? _spotifyEntity(Map<String, dynamic> root) {
    final props = _map(root['props']);
    final pageProps = _map(props?['pageProps']);
    final state = _map(pageProps?['state']);
    final data = _map(state?['data']);
    return _map(data?['entity']) ?? _map(pageProps?['entity']);
  }

  static List<dynamic> _spotifyEntries(Map<String, dynamic> entity) {
    final direct = entity['trackList'];
    if (direct is List) return direct;
    final tracks = entity['tracks'];
    if (tracks is List) return tracks;
    if (tracks is Map && tracks['items'] is List) {
      return tracks['items'] as List;
    }
    return const [];
  }

  static String _spotifyArtist(Map track) {
    final subtitle = _string(track['subtitle']);
    if (subtitle != null && subtitle.trim().isNotEmpty) return subtitle.trim();
    final artists = track['artists'];
    if (artists is List) {
      final names = artists
          .whereType<Map>()
          .map((artist) => _string(artist['name']))
          .whereType<String>()
          .where((name) => name.trim().isNotEmpty)
          .map((name) => name.trim())
          .toList();
      if (names.isNotEmpty) return names.join(', ');
    }
    final artist = track['artist'];
    if (artist is Map) return _string(artist['name'])?.trim() ?? '';
    return _string(artist)?.trim() ?? '';
  }

  static String? _spotifyAlbum(Map track) {
    final album = track['album'];
    if (album is Map) return _string(album['name'])?.trim();
    return _string(album)?.trim();
  }

  static String? _spotifyImage(Map<String, dynamic> entity) {
    final coverArt = entity['coverArt'];
    if (coverArt is Map && coverArt['sources'] is List) {
      for (final source in coverArt['sources'] as List) {
        if (source is Map) {
          final url = _string(source['url']);
          if (url != null && url.isNotEmpty) return url;
        }
      }
    }
    final images = entity['images'];
    if (images is List && images.isNotEmpty && images.first is Map) {
      return _string((images.first as Map)['url']);
    }
    return null;
  }
}

/// Public YouTube Music browse semantics mirrored from the reference
/// YtMusicRepository: use `VL<id>`, read the playlist shelf only, and follow its
/// continuation token until it ends or a hard safety cap is reached.
class YoutubePlaylistImporter implements PlaylistLinkImporter {
  static const int maxPages = 10;
  static const int maxEntries = 1000;
  static const int maxResponseBytes = 2 * 1024 * 1024;
  static const Duration requestTimeout = Duration(seconds: 15);
  static const String clientVersion = '1.20250101.01.00';

  final PlaylistLinkTransport transport;

  const YoutubePlaylistImporter(this.transport);

  @override
  Future<RemotePlaylistSnapshot> fetch(
    ParsedPlaylistLink link, {
    PlaylistLinkCancellationToken? cancellation,
  }) async {
    var page = await _browse(
      body: {'browseId': 'VL${link.remoteId}'},
      cancellation: cancellation,
    );
    final first = _parsePage(page);
    final entries = <RemotePlaylistEntry>[...first.entries];
    var title = first.title ?? 'Imported YouTube Playlist';
    var description = first.description;
    var continuation = first.continuation;
    var pageCount = 1;
    String? truncationReason;
    final seenTokens = <String>{};
    if (entries.length > maxEntries) {
      truncationReason = 'YouTube entry cap reached ($maxEntries tracks).';
    }

    while (continuation != null) {
      cancellation?.throwIfCancelled();
      if (pageCount >= maxPages) {
        truncationReason =
            'YouTube continuation page cap reached ($maxPages pages).';
        break;
      }
      if (!seenTokens.add(continuation)) {
        truncationReason = 'YouTube returned a repeated continuation token.';
        break;
      }
      if (entries.length >= maxEntries) {
        truncationReason = 'YouTube entry cap reached ($maxEntries tracks).';
        break;
      }
      try {
        page = await _browse(
          body: {'continuation': continuation},
          cancellation: cancellation,
        );
        final next = _parsePage(page);
        final remaining = maxEntries - entries.length;
        if (next.entries.length > remaining) {
          entries.addAll(next.entries.take(remaining));
          truncationReason = 'YouTube entry cap reached ($maxEntries tracks).';
          break;
        }
        entries.addAll(next.entries);
        continuation = next.continuation;
        pageCount += 1;
      } catch (error) {
        if (entries.isEmpty) rethrow;
        truncationReason =
            'YouTube continuation failed after $pageCount page(s).';
        break;
      }
    }
    if (entries.length > maxEntries) {
      entries.removeRange(maxEntries, entries.length);
    }
    if (entries.isEmpty) {
      throw const PlaylistLinkHttpException(
        'No public YouTube playlist tracks were found.',
      );
    }
    if (continuation != null && truncationReason == null) {
      truncationReason =
          'YouTube playlist pagination ended before all entries were read.';
    }

    return RemotePlaylistSnapshot(
      title: title,
      description: description,
      entries: entries,
      totalEntries: null,
      complete: truncationReason == null,
      truncationReason: truncationReason,
    );
  }

  Future<Map<String, dynamic>> _browse({
    required Map<String, String> body,
    PlaylistLinkCancellationToken? cancellation,
  }) async {
    final requestBody = <String, dynamic>{
      'context': {
        'client': {
          'clientName': 'WEB_REMIX',
          'clientVersion': clientVersion,
          'hl': 'en',
          'gl': 'US',
        },
      },
      ...body,
    };
    final response = await transport.request(
      'POST',
      Uri.parse(
        'https://music.youtube.com/youtubei/v1/browse?prettyPrint=false',
      ),
      headers: const {
        'Accept': 'application/json',
        'Origin': 'https://music.youtube.com',
        'X-YouTube-Client-Name': '67',
        'X-YouTube-Client-Version': clientVersion,
      },
      body: jsonEncode(requestBody),
      maxBytes: maxResponseBytes,
      timeout: requestTimeout,
      cancellation: cancellation,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PlaylistLinkHttpException(
        'YouTube Music returned HTTP ${response.statusCode}.',
      );
    }
    return decodePlaylistJson(response.body);
  }

  static _YoutubePage _parsePage(Map<String, dynamic> root) {
    final shelf = _findFirstMap(root, const {
      'musicPlaylistShelfRenderer',
      'musicPlaylistShelfContinuation',
    });
    if (shelf == null) {
      throw const PlaylistLinkHttpException(
        'YouTube Music returned an unsupported playlist response.',
      );
    }
    final entries = <RemotePlaylistEntry>[];
    final contents = shelf['contents'];
    if (contents is List) {
      for (final content in contents) {
        if (content is! Map) continue;
        final renderer = content['musicResponsiveListItemRenderer'];
        if (renderer is Map) {
          final entry = _parseEntry(renderer);
          if (entry != null) entries.add(entry);
        }
      }
    }
    final title = _findPlaylistTitle(root);
    final description = _findPlaylistDescription(root);
    return _YoutubePage(
      entries: entries,
      continuation: _findContinuation(shelf),
      title: title,
      description: description,
    );
  }

  static RemotePlaylistEntry? _parseEntry(Map renderer) {
    final playlistItemData = renderer['playlistItemData'];
    final remoteId = playlistItemData is Map
        ? _string(playlistItemData['videoId'])
        : _findPathString(renderer, const [
            'overlay',
            'musicItemThumbnailOverlayRenderer',
            'content',
            'musicPlayButtonRenderer',
            'playNavigationEndpoint',
            'watchEndpoint',
            'videoId',
          ]);
    final columns = renderer['flexColumns'];
    if (remoteId == null || columns is! List || columns.isEmpty) return null;
    final title = _columnText(columns.first);
    if (title == null || title.trim().isEmpty) return null;
    final subtitle = columns.length > 1 ? _columnText(columns[1]) ?? '' : '';
    final parts = subtitle
        .split(' • ')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    final duration = _parseClock(
      parts.firstWhere(_looksLikeClock, orElse: () => ''),
    );
    final metadata = parts.where((part) => !_looksLikeClock(part)).toList();
    final artist = metadata.isEmpty ? '' : metadata.first;
    final album = metadata.length > 1 ? metadata[1] : null;
    return RemotePlaylistEntry(
      title: title.trim(),
      artist: artist,
      album: album,
      duration: duration,
      remoteId: remoteId,
    );
  }

  static String? _findPlaylistTitle(Map<String, dynamic> root) {
    for (final key in const [
      'musicImmersiveHeaderRenderer',
      'musicDetailHeaderRenderer',
      'musicEditablePlaylistDetailHeaderRenderer',
    ]) {
      final renderer = _findFirstMap(root, {key});
      final title = renderer == null ? null : _text(renderer['title']);
      if (title != null && title.trim().isNotEmpty) return title.trim();
    }
    return null;
  }

  static String? _findPlaylistDescription(Map<String, dynamic> root) {
    final header = _findFirstMap(root, const {
      'musicImmersiveHeaderRenderer',
      'musicDetailHeaderRenderer',
    });
    final description = header == null ? null : _text(header['description']);
    return description?.trim().isEmpty == true ? null : description?.trim();
  }

  static String? _findContinuation(Map shelf) {
    final modern = _findFirstMap(shelf, {'continuationItemRenderer'});
    final modernToken = modern == null
        ? null
        : _findPathString(modern, const [
            'continuationEndpoint',
            'continuationCommand',
            'token',
          ]);
    if (modernToken != null && modernToken.isNotEmpty) return modernToken;
    final older = _findFirstMap(shelf, {'nextContinuationData'});
    final olderToken = older == null ? null : _string(older['continuation']);
    return olderToken?.isNotEmpty == true ? olderToken : null;
  }

  static Map<String, dynamic>? _findFirstMap(Object? value, Set<String> keys) {
    var nodes = 0;
    Map<String, dynamic>? walk(Object? node, int depth) {
      if (++nodes > 30000 || depth > 50) return null;
      if (node is Map) {
        for (final key in keys) {
          final candidate = node[key];
          if (candidate is Map) return Map<String, dynamic>.from(candidate);
        }
        for (final child in node.values) {
          final found = walk(child, depth + 1);
          if (found != null) return found;
        }
      } else if (node is List) {
        for (final child in node) {
          final found = walk(child, depth + 1);
          if (found != null) return found;
        }
      }
      return null;
    }

    return walk(value, 0);
  }

  static String? _findPathString(Object? value, List<String> path) {
    var current = value;
    for (final key in path) {
      if (current is! Map) return null;
      current = current[key];
    }
    return _string(current);
  }

  static String? _columnText(Object? column) {
    if (column is! Map) return null;
    final renderer = column['musicResponsiveListItemFlexColumnRenderer'];
    return _text(renderer is Map ? renderer['text'] : null);
  }

  static String? _text(Object? value) {
    if (value is String) return value;
    if (value is Map) {
      final simple = _string(value['simpleText']);
      if (simple != null) return simple;
      final runs = value['runs'];
      if (runs is List) {
        return runs
            .whereType<Map>()
            .map((run) => _string(run['text']) ?? '')
            .join();
      }
    }
    return null;
  }

  static bool _looksLikeClock(String value) =>
      RegExp(r'^\d{1,3}:\d{2}(?::\d{2})?$').hasMatch(value);

  static Duration? _parseClock(String value) {
    if (!_looksLikeClock(value)) return null;
    final parts = value.split(':').map(int.parse).toList();
    if (parts.skip(1).any((part) => part >= 60)) return null;
    final seconds = parts.length == 2
        ? parts[0] * 60 + parts[1]
        : parts[0] * 3600 + parts[1] * 60 + parts[2];
    return Duration(seconds: seconds);
  }

  static String? _string(Object? value) => value is String ? value : null;
}

class _YoutubePage {
  final List<RemotePlaylistEntry> entries;
  final String? continuation;
  final String? title;
  final String? description;

  const _YoutubePage({
    required this.entries,
    required this.continuation,
    required this.title,
    required this.description,
  });
}

String? _string(Object? value) => value is String ? value : null;

num? _number(Object? value) => value is num ? value : null;

Duration? _duration(Object? value) {
  final millis = _number(value)?.toInt();
  return millis == null || millis <= 0 ? null : Duration(milliseconds: millis);
}

Map<String, dynamic>? _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;
