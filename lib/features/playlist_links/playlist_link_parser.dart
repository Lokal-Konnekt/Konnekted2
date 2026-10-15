import 'playlist_link_models.dart';

class PlaylistLinkFormatException implements Exception {
  final String message;

  const PlaylistLinkFormatException(this.message);

  @override
  String toString() => message;
}

class PlaylistLinkParser {
  static const _spotifyHosts = {
    'spotify.com',
    'www.spotify.com',
    'open.spotify.com',
  };
  static const _youtubeHosts = {
    'youtube.com',
    'www.youtube.com',
    'music.youtube.com',
    'm.youtube.com',
  };
  static final _spotifyId = RegExp(r'^[A-Za-z0-9]{22}$');
  static final _youtubeId = RegExp(r'^[A-Za-z0-9_-]{10,100}$');

  static ParsedPlaylistLink parse(String input) {
    final value = input.trim();
    if (value.isEmpty) {
      throw const PlaylistLinkFormatException(
        'Paste a Spotify or YouTube playlist link.',
      );
    }

    final spotifyUri = _parseSpotifyUri(value);
    if (spotifyUri != null) return spotifyUri;
    final youtubeUri = _parseYoutubeUri(value);
    if (youtubeUri != null) return youtubeUri;

    throw const PlaylistLinkFormatException(
      'That is not a supported public Spotify or YouTube playlist link.',
    );
  }

  static ParsedPlaylistLink? _parseSpotifyUri(String value) {
    final uriMatch = RegExp(
      r'^spotify:playlist:([A-Za-z0-9]{22})(?:\?.*)?$',
      caseSensitive: false,
    ).firstMatch(value);
    if (uriMatch != null) {
      final id = uriMatch.group(1)!;
      return ParsedPlaylistLink(
        source: PlaylistLinkSource.spotify,
        remoteId: id,
        canonicalUrl: 'https://open.spotify.com/playlist/$id',
      );
    }

    final uri = Uri.tryParse(value);
    if (uri == null ||
        !_isWebUri(uri) ||
        !_spotifyHosts.contains(uri.host.toLowerCase())) {
      return null;
    }
    if (uri.userInfo.isNotEmpty || uri.hasPort) return null;
    final segments = uri.pathSegments;
    final playlistIndex = segments.lastIndexOf('playlist');
    if (playlistIndex < 0 ||
        playlistIndex + 1 >= segments.length ||
        playlistIndex + 2 != segments.length) {
      return null;
    }
    final id = segments[playlistIndex + 1];
    if (!_spotifyId.hasMatch(id)) return null;
    return ParsedPlaylistLink(
      source: PlaylistLinkSource.spotify,
      remoteId: id,
      canonicalUrl: 'https://open.spotify.com/playlist/$id',
    );
  }

  static ParsedPlaylistLink? _parseYoutubeUri(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !_isWebUri(uri) ||
        !_youtubeHosts.contains(uri.host.toLowerCase())) {
      return null;
    }
    if (uri.userInfo.isNotEmpty || uri.hasPort) return null;
    final listValues = uri.queryParametersAll['list'];
    if (listValues == null || listValues.length != 1) return null;
    final id = listValues.single;
    if (!_youtubeId.hasMatch(id)) return null;
    final path = uri.path.toLowerCase();
    if (path != '/playlist' && path != '/watch' && path != '/') return null;
    return ParsedPlaylistLink(
      source: PlaylistLinkSource.youtube,
      remoteId: id,
      canonicalUrl: 'https://www.youtube.com/playlist?list=$id',
    );
  }

  static bool _isWebUri(Uri uri) =>
      uri.scheme.toLowerCase() == 'http' || uri.scheme.toLowerCase() == 'https';
}
