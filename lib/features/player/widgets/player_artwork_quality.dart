/// Full-player-only artwork URL upgrades.
///
/// Canvas can hide a low-resolution search/mini-player thumbnail until motion
/// is disabled. Promote only well-known, same-image CDN sizing conventions;
/// the caller must retry the original URL if the larger rendition is absent.
class PlayerArtworkQuality {
  const PlayerArtworkQuality._();

  static List<String> candidates(String? original) {
    if (original == null || original.isEmpty) return const [];
    final uri = Uri.tryParse(original);
    if (uri == null ||
        !{'https', 'http'}.contains(uri.scheme.toLowerCase())) {
      return [original];
    }
    final host = uri.host.toLowerCase();
    String? upgraded;

    // Spotify album art is the *same image hash* across these sizes.
    // 640px (b273) is substantially clearer than the 64/160/300px tiles.
    if (host == 'i.scdn.co' && uri.path.startsWith('/image/')) {
      final updated = uri.path.replaceFirst(
        RegExp(r'ab67616d(?:00004851|000082c1|00001e02)'),
        'ab67616d0000b273',
      );
      if (updated != uri.path) upgraded = uri.replace(path: updated).toString();
    }

    // Apple / iTunes artwork URLs encode the requested size in their suffix.
    if (upgraded == null &&
        (host == 'is1-ssl.mzstatic.com' ||
            host == 'is2-ssl.mzstatic.com' ||
            host == 'is3-ssl.mzstatic.com' ||
            host == 'is4-ssl.mzstatic.com' ||
            host == 'is5-ssl.mzstatic.com' ||
            host == 'a1.mzstatic.com')) {
      final updated = uri.path.replaceFirst(
        RegExp(r'/\d{2,4}x\d{2,4}bb\.'),
        '/1200x1200bb.',
      );
      if (updated != uri.path) upgraded = uri.replace(path: updated).toString();
    }

    // Deezer track sleeves include their dimensions after the cover hash.
    if (upgraded == null &&
        host.endsWith('.dzcdn.net') &&
        uri.path.startsWith('/images/cover/')) {
      final updated = uri.path.replaceFirst(
        RegExp(r'/\d{2,4}x\d{2,4}-'),
        '/1000x1000-',
      );
      if (updated != uri.path) upgraded = uri.replace(path: updated).toString();
    }

    // Tidal serves each album hash in independently sized images.
    if (upgraded == null && host == 'resources.tidal.com' &&
        uri.path.startsWith('/images/')) {
      final updated = uri.path.replaceFirst(
        RegExp(r'/\\d{2,4}x\\d{2,4}\\.jpg
    // original remains an explicit fallback.
    if (upgraded == null &&
        (host == 'i.ytimg.com' || host == 'img.youtube.com')) {
      final updated = uri.path.replaceFirst(
        RegExp(r'/(?:default|mqdefault|hqdefault|sddefault)\.jpg$'),
        '/maxresdefault.jpg',
      );
      if (updated != uri.path) upgraded = uri.replace(path: updated).toString();
    }
    return upgraded == null ? [original] : [upgraded, original];
  }
}
),
        '/1280x1280.jpg',
      );
      if (updated != uri.path) upgraded = uri.replace(path: updated).toString();
    }

    // YouTube artwork's max-res rendition is not always uploaded, so the
    // original remains an explicit fallback.
    if (upgraded == null &&
        (host == 'i.ytimg.com' || host == 'img.youtube.com')) {
      final updated = uri.path.replaceFirst(
        RegExp(r'/(?:default|mqdefault|hqdefault|sddefault)\.jpg$'),
        '/maxresdefault.jpg',
      );
      if (updated != uri.path) upgraded = uri.replace(path: updated).toString();
    }
    return upgraded == null ? [original] : [upgraded, original];
  }
}
