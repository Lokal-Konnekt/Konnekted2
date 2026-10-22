import 'dart:convert';

import 'package:flick/features/discovery/discovery_artwork.dart';
import 'package:flick/features/discovery/discovery_http.dart';
import 'package:flick/models/song.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  late List<Uri> requests;
  late Map<String, Object> responses;
  late DateTime now;

  DiscoveryArtworkResolver resolver({
    Future<String?> Function(String)? artistPortrait,
  }) {
    final client = MockClient((request) async {
      requests.add(request.url);
      final key = '${request.url.host}${request.url.path}';
      final body = responses[key];
      return body == null ? http.Response('', 404) : _json(body);
    });
    return DiscoveryArtworkResolver(
      DiscoveryHttp(client),
      now: () => now,
      artistPortrait: artistPortrait,
    );
  }

  setUp(() {
    requests = [];
    responses = {};
    now = DateTime(2026, 10, 20, 12);
  });

  test(
    'uses a real portrait fallback when Deezer has no artist picture',
    () async {
      final image =
          await resolver(
            artistPortrait: (name) async {
              expect(name, 'Artist');
              return 'https://cdn.test/portrait.jpg';
            },
          ).resolve(
            const DiscoveryArtworkRequest(
              kind: DiscoveryArtworkKind.artist,
              artist: 'Artist',
            ),
          );
      expect(image, 'https://cdn.test/portrait.jpg');
    },
  );

  test('matches remaster and guest-credit differences without selecting a remix cover', () async {
    responses['api.deezer.com/search'] = {
      'data': [
        {
          'title': 'Song (Remix)',
          'artist': {'name': 'Artist'},
          'album': {'cover_xl': 'https://cdn.test/remix.jpg'},
        },
        {
          'title': 'Song (2020 Remaster)',
          'artist': {'name': 'Artist'},
          'album': {'cover_xl': 'https://cdn.test/original.jpg'},
        },
      ],
    };
    final image = await resolver().resolve(
      const DiscoveryArtworkRequest(
        kind: DiscoveryArtworkKind.track,
        title: 'Song',
        artist: 'Artist feat. Guest',
      ),
    );
    expect(image, 'https://cdn.test/original.jpg');
  });

  group('discoveryImageUrl', () {
    test('rejects Last.fm placeholders and non-https images', () {
      expect(
        discoveryImageUrl(
          'https://lastfm.freetls.fastly.net/i/u/300x300/2a96cbd8b46e442fc41c2b86b821562f.png',
        ),
        '',
      );
      expect(discoveryImageUrl('https://x.test/default_album.png'), '');
      expect(discoveryImageUrl('https://x.test/noimage/a.png'), '');
      expect(discoveryImageUrl('https://api.deezer.com/artist//image'), '');
      expect(discoveryImageUrl('ftp://x.test/a.png'), '');
      expect(discoveryImageUrl(''), '');
      expect(
        discoveryImageUrl('http://x.test/cover.jpg'),
        'https://x.test/cover.jpg',
      );
    });
  });

  group('DiscoveryArtworkResolver', () {
    test('takes a Deezer track cover only on an exact match', () async {
      responses['api.deezer.com/search'] = {
        'data': [
          {
            'title': 'Halo (Remix)',
            'artist': {'name': 'Beyoncé'},
            'album': {'cover_xl': 'https://cdn.test/remix.jpg'},
          },
          {
            'title': 'Halo',
            'artist': {'name': 'Beyonce'},
            'album': {
              'cover_xl': 'https://cdn.test/2a96cbd8.jpg',
              'cover_big': 'https://cdn.test/halo.jpg',
            },
          },
        ],
      };
      final image = await resolver().resolve(
        const DiscoveryArtworkRequest(
          kind: DiscoveryArtworkKind.track,
          title: 'Halo',
          artist: 'Beyoncé',
        ),
      );
      expect(image, 'https://cdn.test/halo.jpg');
      expect(
        requests.single.queryParameters['q'],
        'artist:"Beyoncé" track:"Halo"',
      );
    });

    test('falls back to iTunes albums with a 600px cover', () async {
      responses['api.deezer.com/search/album'] = {
        'data': [
          {
            'title': 'Other',
            'artist': {'name': 'Air'},
            'cover_xl': 'https://cdn.test/other.jpg',
          },
        ],
      };
      responses['itunes.apple.com/search'] = {
        'results': [
          {
            'collectionName': 'Moon Safari',
            'artistName': 'Air',
            'artworkUrl100': 'https://is1.test/a/100x100bb.jpg',
          },
        ],
      };
      final image = await resolver().resolve(
        const DiscoveryArtworkRequest(
          kind: DiscoveryArtworkKind.album,
          title: 'Moon Safari',
          artist: 'Air',
        ),
      );
      expect(image, 'https://is1.test/a/600x600bb.jpg');
      expect(requests.last.queryParameters['entity'], 'album');
    });

    test('finds artists on Deezer and skips the failed URL', () async {
      responses['api.deezer.com/search/artist'] = {
        'data': [
          {'name': 'Daft Punk', 'picture_xl': 'https://cdn.test/broken.jpg'},
          {'name': 'Daft Punk', 'picture_big': 'https://cdn.test/dp.jpg'},
        ],
      };
      final image = await resolver().resolve(
        const DiscoveryArtworkRequest(
          kind: DiscoveryArtworkKind.artist,
          artist: 'Daft Punk',
          exclude: 'https://cdn.test/broken.jpg',
        ),
      );
      expect(image, 'https://cdn.test/dp.jpg');
    });

    test('caches hits for a day and misses for five minutes', () async {
      final subject = resolver();
      const hit = DiscoveryArtworkRequest(
        kind: DiscoveryArtworkKind.artist,
        artist: 'Air',
      );
      responses['api.deezer.com/search/artist'] = {
        'data': [
          {'name': 'Air', 'picture_xl': 'https://cdn.test/air.jpg'},
        ],
      };
      expect(await subject.resolve(hit), 'https://cdn.test/air.jpg');
      now = now.add(const Duration(hours: 23));
      expect(await subject.resolve(hit), 'https://cdn.test/air.jpg');
      expect(requests, hasLength(1));
      now = now.add(const Duration(hours: 2));
      await subject.resolve(hit);
      expect(requests, hasLength(2));

      requests.clear();
      const miss = DiscoveryArtworkRequest(
        kind: DiscoveryArtworkKind.track,
        title: 'Nothing',
        artist: 'Nobody',
      );
      expect(await subject.resolve(miss), '');
      final missRequests = requests.length;
      now = now.add(const Duration(minutes: 4));
      expect(await subject.resolve(miss), '');
      expect(requests, hasLength(missRequests));
      now = now.add(const Duration(minutes: 2));
      await subject.resolve(miss);
      expect(requests.length, greaterThan(missRequests));
    });

    test(
      'dedupes concurrent lookups and ignores incomplete requests',
      () async {
        final subject = resolver();
        const request = DiscoveryArtworkRequest(
          kind: DiscoveryArtworkKind.track,
          title: 'Song',
          artist: 'Band',
        );
        await Future.wait([subject.resolve(request), subject.resolve(request)]);
        // One Deezer and one iTunes request, not two of each.
        expect(requests, hasLength(2));
        expect(
          await subject.resolve(
            const DiscoveryArtworkRequest(
              kind: DiscoveryArtworkKind.track,
              artist: 'Band',
            ),
          ),
          '',
        );
        expect(requests, hasLength(2));
      },
    );
  });

  group('DiscoveryLocalArtwork', () {
    final library = DiscoveryLocalArtwork([
      const Song(
        id: '1',
        title: 'Café',
        artist: 'Feat Artist',
        albumArtist: 'Sigur Rós',
        album: 'Ágætis byrjun',
        albumArt: '/art/agaetis.jpg',
        duration: Duration(minutes: 3),
        filePath: '/music/cafe.flac',
        fileType: 'flac',
      ),
    ]);

    test('matches tracks and albums by normalised title and artist', () {
      expect(
        library.lookup(
          const DiscoveryArtworkRequest(
            kind: DiscoveryArtworkKind.track,
            title: 'cafe',
            artist: 'Sigur Ros',
          ),
        ),
        '/art/agaetis.jpg',
      );
      expect(
        library.lookup(
          const DiscoveryArtworkRequest(
            kind: DiscoveryArtworkKind.album,
            title: 'ÁGÆTIS byrjun',
            artist: 'sigur rós',
          ),
        ),
        '/art/agaetis.jpg',
      );
      expect(
        library.lookup(
          const DiscoveryArtworkRequest(
            kind: DiscoveryArtworkKind.track,
            title: 'Café',
            artist: 'Someone Else',
          ),
        ),
        isNull,
      );
      expect(
        library.lookup(
          const DiscoveryArtworkRequest(
            kind: DiscoveryArtworkKind.artist,
            artist: 'Sigur Rós',
          ),
        ),
        isNull,
      );
    });
  });
}
