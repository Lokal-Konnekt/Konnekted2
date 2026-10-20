export 'spotify_models.dart' show SpotifyPlaylist, SpotifyTrack, SpotifyUnmatchedTrack;

import 'dart:async';

import 'package:flutter/material.dart';

import 'spotify_api.dart';
import 'spotify_models.dart';
import 'spotify_http.dart';
import 'spotify_oauth.dart';
import 'spotify_storage.dart';
import 'spotify_sync.dart';

/// Opt-in Spotify library bridge. It lists Spotify metadata and lets the user
/// explicitly import local matches or add matched Liked Songs to local
/// Favorites. Spotify metadata is never presented as playable local audio.
class SpotifyLibraryScreen extends StatefulWidget {
  const SpotifyLibraryScreen({
    super.key,
    this.api,
    this.oauth,
    this.settings,
    this.metadata,
    this.sync,
  });

  final SpotifyLibraryApi? api;
  final SpotifyOAuthService? oauth;
  final SpotifySettingsStore? settings;
  final SpotifyMetadataStore? metadata;
  final SpotifySyncService? sync;

  @override
  State<SpotifyLibraryScreen> createState() => _SpotifyLibraryScreenState();
}

class _SpotifyLibraryScreenState extends State<SpotifyLibraryScreen> {
  late final SpotifySettingsStore _settings;
  late final SpotifyOAuthService _oauth;
  late final SpotifyLibraryApi _api;
  late final SpotifyMetadataStore _metadata;
  late final SpotifySyncService _sync;
  SpotifyCancellation? _cancel;
  List<SpotifyPlaylist> _playlists = const [];
  String? _error;
  String? _status;
  String? _busyPlaylist;
  bool _loading = true;
  bool _connected = false;
  bool _discoveryEnabled = false;
  bool _signingIn = false;
  SpotifyLikedSongsSyncReport? _likedReport;
  SpotifyPlaylistImportReport? _importReport;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings ?? SpotifySettingsStore();
    final tokenStore = _settings.tokenStore;
    _oauth = widget.oauth ?? SpotifyOAuthService(
      tokenStore: tokenStore,
    );
    _api = widget.api ?? SpotifyApi(tokenStore: tokenStore, oauth: _oauth);
    _metadata = widget.metadata ?? SpotifyMetadataStore(_settings.preferences);
    _sync = widget.sync ?? SpotifySyncService(api: _api, metadata: _metadata);
    unawaited(_loadSettings());
  }

  Future<void> _loadSettings() async {
    try {
      final connected = await _oauth.isConnected;
      final discoveryEnabled = await _settings.loadDiscoveryEnabled();
      if (!mounted) return;
      setState(() {
        _connected = connected;
        _discoveryEnabled = discoveryEnabled;
        _loading = false;
      });
    } catch (error) {
      if (mounted) setState(() { _loading = false; _error = _message(error); });
    }
  }

  Future<void> _setDiscoveryEnabled(bool enabled) async {
    try {
      await _settings.saveDiscoveryEnabled(enabled);
      if (mounted) {
        setState(() {
          _discoveryEnabled = enabled;
          _status = enabled
              ? 'Spotify Discovery enabled on Home.'
              : 'Spotify Discovery disabled.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    }
  }

  Future<void> _signIn() async {
    setState(() { _signingIn = true; _error = null; _status = 'Opening Spotify sign-in…'; });
    try {
      await _oauth.signIn();
      if (!mounted) return;
      setState(() { _connected = true; _status = 'Spotify connected.'; });
      await _loadPlaylists();
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Future<void> _cancelOperation() async {
    _cancel?.cancel();
    _cancel = null;
    if (_signingIn) await _oauth.cancel();
    if (mounted) setState(() { _signingIn = false; _status = 'Cancelled.'; });
  }

  Future<void> _logout() async {
    await _oauth.logout();
    if (mounted) setState(() { _connected = false; _playlists = const []; _status = 'Disconnected.'; });
  }

  Future<void> _loadPlaylists() async {
    if (!_connected) return;
    final cancellation = SpotifyCancellation();
    _cancel = cancellation;
    setState(() { _status = 'Loading Spotify library…'; _error = null; });
    try {
      final playlists = await _sync.loadPlaylists(cancellation: cancellation, onProgress: (loaded) {
        if (mounted) setState(() => _status = 'Loading Spotify library: $loaded…');
      });
      cancellation.check();
      if (mounted) setState(() { _playlists = playlists; _status = null; });
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      _cancel = null;
    }
  }

  Future<void> _import(SpotifyPlaylist playlist) async {
    final cancellation = SpotifyCancellation();
    _cancel = cancellation;
    setState(() { _busyPlaylist = playlist.id; _error = null; _status = 'Matching “${playlist.name}”…'; });
    try {
      final report = await _sync.importPlaylist(playlist, cancellation: cancellation, onProgress: (loaded) {
        if (mounted) setState(() => _status = 'Matching “${playlist.name}”: $loaded…');
      });
      cancellation.check();
      if (mounted) setState(() { _importReport = report; _status = 'Saved ${report.matchedTracks} of ${report.totalTracks} tracks.'; });
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      _cancel = null;
      if (mounted) setState(() => _busyPlaylist = null);
    }
  }

  Future<void> _syncLiked() async {
    final cancellation = SpotifyCancellation();
    _cancel = cancellation;
    setState(() { _busyPlaylist = 'liked'; _error = null; _status = 'Matching Liked Songs…'; });
    try {
      final report = await _sync.syncLikedSongs(cancellation: cancellation, onProgress: (loaded) {
        if (mounted) setState(() => _status = 'Matching Liked Songs: $loaded…');
      });
      cancellation.check();
      if (mounted) {
        setState(() {
          _likedReport = report;
          _status = 'Added ${report.addedCount}; already liked ${report.alreadyLikedCount}; unmatched ${report.unmatchedTracks.length}.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      _cancel = null;
      if (mounted) setState(() => _busyPlaylist = null);
    }
  }

  String _message(Object error) => error.toString().replaceFirst('Exception: ', '');

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Spotify library'),
        actions: [
          if (_connected)
            IconButton(
              tooltip: 'Disconnect Spotify',
              onPressed: _logout,
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Connect with Spotify', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            const Text('Sign in through Spotify’s real page in this app. The web session is stored securely, and Spotify recordings remain metadata until matched to local audio.'),
            const SizedBox(height: 16),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Spotify Discovery'),
              subtitle: const Text(
                'Opt in to Quick Picks, Recently Played, Liked Songs and Fresh Finds on Home.',
              ),
              value: _discoveryEnabled,
              onChanged: _loading ? null : _setDiscoveryEnabled,
            ),
            const SizedBox(height: 8),
            Row(children: [
              if (!_connected)
                FilledButton.icon(
                  onPressed: _signingIn ? null : _signIn,
                  icon: const Icon(Icons.login),
                  label: Text(_signingIn ? 'Signing in…' : 'Connect'),
                )
              else
                FilledButton.icon(
                  onPressed: _cancel == null ? _loadPlaylists : null,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh library'),
                ),
              if (_cancel != null || _signingIn) ...[
                const SizedBox(width: 8),
                TextButton(onPressed: _cancelOperation, child: const Text('Cancel')),
              ],
            ]),
            if (_connected) ...[
              const Divider(height: 32),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Liked Songs'),
                subtitle: const Text('One-way sync to local Favorites; existing local likes are preserved.'),
                trailing: FilledButton(
                  onPressed: _busyPlaylist == null ? _syncLiked : null,
                  child: const Text('Sync likes'),
                ),
              ),
              if (_playlists.isEmpty && _status == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: Text('No Spotify playlists found.')),
                ),
              for (final playlist in _playlists.where((item) => item.id != 'liked'))
                Card(
                  child: ListTile(
                    leading: playlist.imageUrl == null
                        ? const CircleAvatar(child: Icon(Icons.queue_music))
                        : CircleAvatar(backgroundImage: NetworkImage(playlist.imageUrl!)),
                    title: Text(playlist.name),
                    subtitle: Text('${playlist.tracksTotal} tracks${playlist.owner == null ? '' : ' · ${playlist.owner}'}'),
                    trailing: FilledButton(
                      onPressed: _busyPlaylist == null ? () => _import(playlist) : null,
                      child: Text(_busyPlaylist == playlist.id ? 'Working…' : 'Import'),
                    ),
                  ),
                ),
            ],
            if (_status != null) ...[
              const SizedBox(height: 16),
              Semantics(liveRegion: true, child: Text(_status!)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            if (_importReport != null) _reportCard('Last playlist import', '${_importReport!.matchedTracks}/${_importReport!.totalTracks} matched; ${_importReport!.unmatchedTracks.length} explicitly unmatched.'),
            if (_likedReport != null) _reportCard('Last Liked Songs sync', '${_likedReport!.addedCount} added, ${_likedReport!.alreadyLikedCount} already local, ${_likedReport!.unmatchedTracks.length} unmatched; readback ${_likedReport!.readbackVerified ? 'verified' : 'failed'}.', error: !_likedReport!.readbackVerified),
          ],
        ),
      ),
    );
  }

  Widget _reportCard(String title, String message, {bool error = false}) => Card(
        color: error ? Theme.of(context).colorScheme.errorContainer : null,
        child: ListTile(title: Text(title), subtitle: Text(message)),
      );
}
