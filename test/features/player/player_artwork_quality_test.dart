import 'package:flutter_test/flutter_test.dart';
import 'package:flick/features/player/widgets/player_artwork_quality.dart';

void main() {
  group('full-player cover after Canvas is disabled', () {
    test('promotes Spotify 300px art to the same album hash at 640px', () {
      const old =
          'https://i.scdn.co/image/ab67616d00001e02abcdef0123456789';
      expect(PlayerArtworkQuality.candidates(old), [
        'https://i.scdn.co/image/ab67616d0000b273abcdef0123456789',
        old,
      ]);
    });

    test('also upgrades Spotify mini-player thumbnails without changing hash', () {
      for (final size in ['00004851', '000082c1']) {
        final old = 'https://i.scdn.co/image/ab67616d$size-abc';
        expect(
          PlayerArtworkQuality.candidates(old).first,
          'https://i.scdn.co/image/ab67616d0000b273-abc',
        );
      }
    });

    test('already large Spotify artwork is left intact', () {
      const old =
          'https://i.scdn.co/image/ab67616d0000b273abcdef0123456789';
      expect(PlayerArtworkQuality.candidates(old), [old]);
    });

    test('iTunes static cover requests 1200px with original fallback', () {
      const old =
          'https://is2-ssl.mzstatic.com/image/thumb/Music/covers/100x100bb.jpg';
      expect(PlayerArtworkQuality.candidates(old), [
        'https://is2-ssl.mzstatic.com/image/thumb/Music/covers/1200x1200bb.jpg',
        old,
      ]);
    });

    test('Deezer static cover requests full-resolution variant', () {
      const old =
          'https://e-cdns-images.dzcdn.net/images/cover/hash/250x250-000000-80-0-0.jpg';
      expect(PlayerArtworkQuality.candidates(old), [
        'https://e-cdns-images.dzcdn.net/images/cover/hash/1000x1000-000000-80-0-0.jpg',
        old,
      ]);
    });

    test('YouTube requests a max-resolution poster with safe fallback', () {
      const old = 'https://i.ytimg.com/vi/abc123/hqdefault.jpg';
      expect(PlayerArtworkQuality.candidates(old), [
        'https://i.ytimg.com/vi/abc123/maxresdefault.jpg',
        old,
      ]);
    });

    test('does not rewrite unknown CDNs, local files or unrelated hosts', () {
      expect(PlayerArtworkQuality.candidates('/data/app/full-cover.jpg'), [
        '/data/app/full-cover.jpg',
      ]);
      expect(PlayerArtworkQuality.candidates(null), isEmpty);
      const other = 'https://example.com/image/ab67616d00001e02xxx';
      expect(PlayerArtworkQuality.candidates(other), [other]);
    });

    test('keeps query parameters and original as a last resort', () {
      const old = 'https://is1-ssl.mzstatic.com/music/200x200bb.jpg?source=abc';
      expect(PlayerArtworkQuality.candidates(old), [
        'https://is1-ssl.mzstatic.com/music/1200x1200bb.jpg?source=abc',
        old,
      ]);
    });
  });
}
