/// Lazy artwork fallback for Discovery, ported from desktop Lokal
/// (`electron/discoveryArtwork.js`, `src/components/DiscoveryImage.jsx`).
///
/// Last.fm no longer serves artist pictures or most track covers, so a
/// recommendation often arrives without artwork, or with a URL that no longer
/// loads. In that case the cover is looked up, in desktop's order: a match in
/// your library, then Deezer, then iTunes. A lookup only ever changes the
/// picture, never which recording is recommended, and it needs the title and
/// the artist to match exactly, so another artist's cover never stands in.
///
/// Lookups only happen inside Discovery, which is already opt-in: it shows
/// nothing until you connect Last.fm (or sign in to YouTube Music).
library;

import 'dart:async';
import 'dart:collection';

import 'package:flick/features/konnekted/konnekted_data.dart';
import 'package:flick/models/song.dart';
import 'package:flick/widgets/common/cached_image_widget.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'discovery_http.dart';
import 'recommendation_match.dart';

enum DiscoveryArtworkKind { track, album, artist }

/// What a cover is wanted for. [exclude] is a URL that already failed to load.
@immutable
class DiscoveryArtworkRequest {
  const DiscoveryArtworkRequest({
    required this.kind,
    required this.artist,
    this.title = '',
    this.exclude = '',
  });

  final DiscoveryArtworkKind kind;
  final String title;
  final String artist;
  final String exclude;

  bool get isComplete =>
      artist.trim().isNotEmpty &&
      (kind == DiscoveryArtworkKind.artist || title.trim().isNotEmpty);

  String get cacheKey =>
      '${kind.name}\u0000${recommendationKey(artist)}\u0000'
      '${recommendationKey(title)}\u0000$exclude';

  @override
  bool operator ==(Object other) =>
      other is DiscoveryArtworkRequest &&
      other.kind == kind &&
      other.title == title &&
      other.artist == artist &&
      other.exclude == exclude;

  @override
  int get hashCode => Object.hash(kind, title, artist, exclude);
}

final _https = RegExp('^https://', caseSensitive: false);
final _insecure = RegExp('^http:', caseSensitive: false);
final _placeholder = RegExp(
  r'2a96cbd8|default_album|noimage|/artist//',
  caseSensitive: false,
);

/// Desktop's `imageUrl`: an https image that isn't a Last.fm placeholder, or
/// '' when there is none.
String discoveryImageUrl(String? value) {
  final url = (value ?? '').trim().replaceFirst(_insecure, 'https:');
  return _https.hasMatch(url) && !_placeholder.hasMatch(url) ? url : '';
}

class _Cached {
  const _Cached(this.image, this.at);
  final String image;
  final DateTime at;
}

/// Looks covers up on Deezer and iTunes, with desktop's limits: hits kept for
/// a day, misses for five minutes, at most 1000 entries, one request per
/// cover at a time and at most four lookups running together.
class DiscoveryArtworkResolver {
  DiscoveryArtworkResolver(this._http, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DiscoveryHttp _http;
  final DateTime Function() _now;

  static const maxEntries = 1000;
  static const maxConcurrent = 4;
  static const hitLifetime = Duration(hours: 24);
  static const missLifetime = Duration(minutes: 5);

  final _cache = <String, _Cached>{};
  final _pending = <String, Future<String>>{};
  final _waiting = Queue<Completer<void>>();
  int _running = 0;

  /// The cover for [request], or '' when none matches.
  Future<String> resolve(DiscoveryArtworkRequest request) {
    if (!request.isComplete) return Future.value('');
    final id = request.cacheKey;
    final cached = _cache[id];
    if (cached != null) {
      final lifetime = cached.image.isEmpty ? missLifetime : hitLifetime;
      if (_now().difference(cached.at) < lifetime) {
        return Future.value(cached.image);
      }
      _cache.remove(id);
    }
    return _pending[id] ??= _lookup(request)
        .then((image) {
          _cache[id] = _Cached(image, _now());
          while (_cache.length > maxEntries) {
            _cache.remove(_cache.keys.first);
          }
          return image;
        })
        .whenComplete(() {
          // A block body: returning the removed future would await itself.
          _pending.remove(id);
        });
  }

  Future<String> _lookup(DiscoveryArtworkRequest request) async {
    if (_running >= maxConcurrent) {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    }
    _running++;
    try {
      return await _remote(request);
    } catch (_) {
      return '';
    } finally {
      _running--;
      if (_waiting.isNotEmpty) _waiting.removeFirst().complete();
    }
  }

  Future<List<Map>> _rows(Uri url, String field) async {
    try {
      final data = (await _http.json(url))[field];
      return data is List ? data.whereType<Map>().toList() : const [];
    } catch (_) {
      return const [];
    }
  }

  Future<String> _remote(DiscoveryArtworkRequest request) async {
    String allowed(Object? value) {
      final image = discoveryImageUrl(value is String ? value : null);
      return image.isNotEmpty && image != request.exclude ? image : '';
    }

    String first(List<Object?> values) => values
        .map(allowed)
        .firstWhere((image) => image.isNotEmpty, orElse: () => '');

    bool same(Object? a, String b) =>
        recommendationKey(a is String ? a : '') == recommendationKey(b);

    String nameOf(Object? value) =>
        value is Map && value['name'] is String ? value['name'] as String : '';

    if (request.kind == DiscoveryArtworkKind.artist) {
      final artists = await _rows(
        Uri.https('api.deezer.com', '/search/artist', {
          'q': request.artist,
          'limit': '10',
        }),
        'data',
      );
      for (final row in artists) {
        final image = first([row['picture_xl'], row['picture_big']]);
        if (same(row['name'], request.artist) && image.isNotEmpty) {
          return image;
        }
      }
      final songs = await _rows(
        Uri.https('api.deezer.com', '/search', {
          'q': 'artist:"${request.artist}"',
          'limit': '10',
        }),
        'data',
      );
      for (final row in songs) {
        final artist = row['artist'] is Map ? row['artist'] as Map : const {};
        final album = row['album'] is Map ? row['album'] as Map : const {};
        final image = first([
          artist['picture_xl'],
          artist['picture_big'],
          album['cover_xl'],
          album['cover_big'],
        ]);
        if (same(artist['name'], request.artist) && image.isNotEmpty) {
          return image;
        }
      }
      return '';
    }

    final album = request.kind == DiscoveryArtworkKind.album;
    final deezer = await _rows(
      Uri.https('api.deezer.com', album ? '/search/album' : '/search', {
        'q': album
            ? 'artist:"${request.artist}" album:"${request.title}"'
            : 'artist:"${request.artist}" track:"${request.title}"',
        'limit': '15',
      }),
      'data',
    );
    for (final row in deezer) {
      final source = album ? row : (row['album'] is Map ? row['album'] : null);
      final cover = source is Map
          ? first([source['cover_xl'], source['cover_big']])
          : '';
      if (same(row['title'], request.title) &&
          same(nameOf(row['artist']), request.artist) &&
          cover.isNotEmpty) {
        return cover;
      }
    }

    final itunes = await _rows(
      Uri.https('itunes.apple.com', '/search', {
        'term': '${request.artist} ${request.title}',
        'entity': album ? 'album' : 'song',
        'limit': '15',
      }),
      'results',
    );
    for (final row in itunes) {
      final small = row['artworkUrl100'];
      final cover = allowed(
        small is String ? small.replaceFirst('100x100bb', '600x600bb') : null,
      );
      if (same(
            album ? row['collectionName'] : row['trackName'],
            request.title,
          ) &&
          same(row['artistName'], request.artist) &&
          cover.isNotEmpty) {
        return cover;
      }
    }
    return '';
  }
}

/// Your library's covers by normalised title and artist (or album and album
/// artist), so a recommendation you already own shows its own artwork.
class DiscoveryLocalArtwork {
  DiscoveryLocalArtwork(Iterable<Song> songs) : _covers = {} {
    for (final song in songs) {
      final art = song.albumArt?.trim() ?? '';
      if (art.isEmpty) continue;
      final artists = {
        recommendationKey(song.artist),
        if (song.albumArtist != null) recommendationKey(song.albumArtist),
      }..remove('');
      final title = recommendationKey(song.title);
      final album = recommendationKey(song.album);
      for (final artist in artists) {
        if (title.isNotEmpty) {
          _covers.putIfAbsent(
            _id(DiscoveryArtworkKind.track, artist, title),
            () => art,
          );
        }
        if (album.isNotEmpty) {
          _covers.putIfAbsent(
            _id(DiscoveryArtworkKind.album, artist, album),
            () => art,
          );
        }
      }
    }
  }

  static const empty = DiscoveryLocalArtwork._empty();
  const DiscoveryLocalArtwork._empty() : _covers = const {};

  final Map<String, String> _covers;

  static String _id(DiscoveryArtworkKind kind, String artist, String title) =>
      '${kind.name}\u0000$artist\u0000$title';

  /// The library cover for [request], or null. Artists have no library
  /// picture on mobile, so they always go online.
  String? lookup(DiscoveryArtworkRequest request) {
    if (!request.isComplete || request.kind == DiscoveryArtworkKind.artist) {
      return null;
    }
    final art =
        _covers[_id(
          request.kind,
          recommendationKey(request.artist),
          recommendationKey(request.title),
        )];
    return art == null || art == request.exclude ? null : art;
  }
}

/// One resolver for the app's lifetime, so its cache survives Home rebuilds.
final discoveryArtworkResolverProvider = Provider<DiscoveryArtworkResolver>((
  ref,
) {
  final client = http.Client();
  ref.onDispose(client.close);
  return DiscoveryArtworkResolver(
    DiscoveryHttp(client, timeout: const Duration(seconds: 6)),
  );
});

final discoveryLocalArtworkProvider =
    Provider.autoDispose<DiscoveryLocalArtwork>((ref) {
      final songs = ref.watch(konnektedLibraryProvider).value;
      return songs == null || songs.isEmpty
          ? DiscoveryLocalArtwork.empty
          : DiscoveryLocalArtwork(songs);
    });

/// Desktop's `DiscoveryImage`: shows [url], and when it is missing or fails to
/// load, looks a cover up and shows that, else [placeholder].
class DiscoveryArtwork extends StatelessWidget {
  const DiscoveryArtwork({
    super.key,
    required this.kind,
    required this.artist,
    this.title = '',
    this.url = '',
    required this.placeholder,
    this.width,
    this.height,
  });

  final DiscoveryArtworkKind kind;
  final String title;
  final String artist;
  final String url;
  final Widget placeholder;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final image = discoveryImageUrl(url);
    final fallback = _DiscoveryArtworkFallback(
      request: DiscoveryArtworkRequest(
        kind: kind,
        title: title,
        artist: artist,
        exclude: image,
      ),
      placeholder: placeholder,
      width: width,
      height: height,
    );
    if (image.isEmpty) return fallback;
    return CachedImageWidget(
      imagePath: image,
      width: width,
      height: height,
      placeholder: placeholder,
      errorWidget: fallback,
    );
  }
}

class _DiscoveryArtworkFallback extends ConsumerStatefulWidget {
  const _DiscoveryArtworkFallback({
    required this.request,
    required this.placeholder,
    this.width,
    this.height,
    this.skipLocal = false,
  });

  final DiscoveryArtworkRequest request;
  final Widget placeholder;
  final double? width;
  final double? height;
  final bool skipLocal;

  @override
  ConsumerState<_DiscoveryArtworkFallback> createState() =>
      _DiscoveryArtworkFallbackState();
}

class _DiscoveryArtworkFallbackState
    extends ConsumerState<_DiscoveryArtworkFallback> {
  Future<String>? _remote;

  @override
  void didUpdateWidget(covariant _DiscoveryArtworkFallback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request != widget.request) _remote = null;
  }

  Widget _image(String path, Widget onError) => CachedImageWidget(
    imagePath: path,
    width: widget.width,
    height: widget.height,
    placeholder: widget.placeholder,
    errorWidget: onError,
  );

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    if (!request.isComplete) return widget.placeholder;
    if (!widget.skipLocal) {
      final local = ref.watch(
        discoveryLocalArtworkProvider.select((index) => index.lookup(request)),
      );
      if (local != null) {
        return _image(
          local,
          _DiscoveryArtworkFallback(
            request: request,
            placeholder: widget.placeholder,
            width: widget.width,
            height: widget.height,
            skipLocal: true,
          ),
        );
      }
    }
    _remote ??= ref.read(discoveryArtworkResolverProvider).resolve(request);
    return FutureBuilder<String>(
      future: _remote,
      builder: (context, snapshot) {
        final image = snapshot.data ?? '';
        return image.isEmpty
            ? widget.placeholder
            : _image(image, widget.placeholder);
      },
    );
  }
}
