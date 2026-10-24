import 'link/link_journal.dart';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flick/models/song.dart';
import 'package:flick/data/repositories/song_repository.dart';

/// Service for managing favorite songs.
/// Stores favorite song IDs in SharedPreferences for persistence.
abstract interface class RemoteFavoritesDelegate {
  Future<bool> isFavorite(String songId);
  Future<bool> toggleFavorite(String songId);
}

class FavoritesService {
  static RemoteFavoritesDelegate? remoteDelegate;
  static const String _favoritesKey = 'favorite_song_ids';
  static const String _onlineMetadataKey = 'favorite_online_song_metadata_v1';

  static bool _onlineSong(Song song) => song.isPending ||
      song.isExternal || (song.sourcePackage?.startsWith('konnekted.') ?? false);

  static Map<String, Object?> _capture(Song song) => {
    'id': song.id, 'title': song.title, 'artist': song.artist,
    'album': song.album, 'albumArt': song.albumArt,
    'durationMs': song.duration.inMilliseconds, 'codec': song.fileType,
    'resolution': song.resolution, 'sampleRate': song.sampleRate,
    'bitDepth': song.bitDepth, 'filePath': song.filePath,
    'sourcePackage': song.sourcePackage, 'remoteId': song.remoteId,
  };

  /// Preserve metadata for online songs, which are never inserted into
  /// SongRepository merely because they were streamed. Saving only their
  /// IDs made them invisible on the Liked library screen.
  Future<void> _rememberOnline(Song song) async {
    if (!_onlineSong(song)) return;
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> known = {};
    try {
      known = jsonDecode(prefs.getString(_onlineMetadataKey) ?? '{}') as Map<String, dynamic>;
    } catch (_) {}
    known[song.id] = _capture(song);
    await prefs.setString(_onlineMetadataKey, jsonEncode(known));
  }

  Future<void> _forgetOnline(String id) async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> known = {};
    try {
      known = jsonDecode(prefs.getString(_onlineMetadataKey) ?? '{}') as Map<String, dynamic>;
    } catch (_) {}
    if (known.remove(id) != null) {
      await prefs.setString(_onlineMetadataKey, jsonEncode(known));
    }
  }

  static Song? _restore(Object? raw) {
    if (raw is! Map || raw['id'] is! String ||
        raw['title'] is! String || raw['artist'] is! String) return null;
    final song = raw.cast<String, dynamic>();
    return Song(
      id: song['id'] as String,
      title: song['title'] as String,
      artist: song['artist'] as String,
      album: song['album'] as String?,
      albumArt: song['albumArt'] as String?,
      duration: Duration(milliseconds: (song['durationMs'] as num?)?.toInt() ?? 0),
      fileType: song['codec'] as String? ?? 'ONLINE',
      resolution: song['resolution'] as String?,
      sampleRate: (song['sampleRate'] as num?)?.toInt(),
      bitDepth: (song['bitDepth'] as num?)?.toInt(),
      filePath: song['filePath'] as String?,
      sourcePackage: song['sourcePackage'] as String?,
      remoteId: song['remoteId'] as String?,
      isExternal: true,
    );
  }

  final SongRepository _songRepository;

  // Cached set of favorite IDs for quick lookup
  Set<String> _favoriteIds = {};
  bool _isLoaded = false;

  FavoritesService({SongRepository? songRepository})
    : _songRepository = songRepository ?? SongRepository();

  /// Load favorites from SharedPreferences.
  Future<void> _ensureLoaded() async {
    if (_isLoaded) return;

    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_favoritesKey) ?? [];
    _favoriteIds = ids.toSet();
    _isLoaded = true;
  }

  /// Get all favorite songs.
  Future<List<Song>> getFavorites() async {
    await _ensureLoaded();

    if (_favoriteIds.isEmpty) return [];

    // Get all songs and filter by favorite IDs
    final allSongs = await _songRepository.getAllSongs();
    final liked = allSongs.where((song) => _favoriteIds.contains(song.id)).toList();
    final inLibrary = liked.map((song) => song.id).toSet();
    final prefs = await SharedPreferences.getInstance();
    try {
      final extras = jsonDecode(prefs.getString(_onlineMetadataKey) ?? '{}');
      if (extras is Map) {
        for (final id in _favoriteIds) {
          if (inLibrary.contains(id)) continue;
          final song = _restore(extras[id]);
          if (song != null) liked.add(song);
        }
      }
    } catch (_) {
      // Broken extra metadata must never hide local favorites.
    }
    return liked;
  }

  /// Check if a song is a favorite.
  Future<bool> isFavorite(String songId) async {
    if (songId.startsWith('desktop:'))
      return (await remoteDelegate?.isFavorite(songId)) ?? false;
    await _ensureLoaded();
    return _favoriteIds.contains(songId);
  }

  /// Add a song to favorites.
  Future<void> addFavorite(String songId, {Song? song}) async {
    if (songId.startsWith('desktop:')) {
      if (!await isFavorite(songId))
        await remoteDelegate?.toggleFavorite(songId);
      return;
    }
    await _ensureLoaded();

    if (song != null) await _rememberOnline(song);
    _favoriteIds.add(songId);
    await _saveFavorites();
  }

  /// Remove a song from favorites.
  Future<void> removeFavorite(String songId) async {
    if (songId.startsWith('desktop:')) {
      if (await isFavorite(songId))
        await remoteDelegate?.toggleFavorite(songId);
      return;
    }
    await _ensureLoaded();

    _favoriteIds.remove(songId);
    await _forgetOnline(songId);
    await _saveFavorites();
  }

  /// Toggle favorite status for a song.
  /// Returns true if the song is now a favorite, false otherwise.
  Future<bool> toggleFavorite(String songId, {Song? song}) async {
    if (songId.startsWith('desktop:')) {
      final remote = remoteDelegate;
      if (remote == null) throw StateError('Connect to your desktop first.');
      return remote.toggleFavorite(songId);
    }
    await _ensureLoaded();

    if (_favoriteIds.contains(songId)) {
      _favoriteIds.remove(songId);
      await _forgetOnline(songId);
      await _saveFavorites();
      return false;
    } else {
      if (song != null) await _rememberOnline(song);
      _favoriteIds.add(songId);
      await _saveFavorites();
      return true;
    }
  }

  /// Get the count of favorite songs.
  Future<int> getFavoritesCount() async {
    await _ensureLoaded();
    return _favoriteIds.length;
  }

  /// Save favorites to SharedPreferences.
  Future<void> _saveFavorites({bool captureLink = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favoritesKey, _favoriteIds.toList());
    if (captureLink) await LinkJournal.instance.captureFavorites(_favoriteIds);
  }

  /// Apply one winning remote intent without producing a new local operation.
  Future<void> setFromLink(String songId, bool liked) =>
      setManyFromLink({songId: liked});

  Future<void> setManyFromLink(Map<String, bool> changes) async {
    await _ensureLoaded();
    for (final entry in changes.entries) {
      entry.value
          ? _favoriteIds.add(entry.key)
          : _favoriteIds.remove(entry.key);
    }
    await _saveFavorites(captureLink: false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'lokal.link.favorites_snapshot',
      _favoriteIds.toList(),
    );
  }

  /// Clear all favorites.
  Future<void> clearFavorites() async {
    _favoriteIds.clear();
    await _saveFavorites();
  }
}
