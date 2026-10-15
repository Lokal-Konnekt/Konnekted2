import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../services/player_service.dart';
import 'discovery_controller.dart';
import 'discovery_http.dart';
import 'discovery_models.dart';
import 'discovery_playback.dart';
import 'discovery_registry.dart';
import 'discovery_settings.dart';
import 'source_settings_screen.dart';

export 'source_settings_screen.dart' show SourceSettingsScreen;

/// Shell entry point. No network traffic before the listener opts in and types
/// a search (or explicitly runs the settings health check).
class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({super.key, this.client, this.settingsStore});

  /// Optional seams for host tests. An injected client remains caller-owned.
  final http.Client? client;
  final DiscoverySettingsStore? settingsStore;

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  late final http.Client _client;
  late final DiscoveryHttp _http;
  late final DiscoveryController _search;
  late final DiscoveryPlaybackCache _cache;
  late final DiscoverySettingsStore _store;
  final _query = TextEditingController();
  DiscoverySettings _settings = const DiscoverySettings();
  bool _loadingSettings = true;
  String? _settingsError;
  String? _playStatus;
  String? _playError;
  String? _busyKey;
  Completer<void>? _cancel;

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? http.Client();
    _http = DiscoveryHttp(_client);
    _store = widget.settingsStore ?? DiscoverySettingsStore();
    _search = DiscoveryController(
      search: (q) => searchDiscovery(_http, _settings, q),
    );
    _cache = DiscoveryPlaybackCache(
      http: _http,
      protectedPaths: () {
        final player = PlayerService();
        return {
          if (player.currentSongNotifier.value?.filePath case final String path)
            path,
          ...player.queue.map((s) => s.filePath).whereType<String>(),
          ...player.upNext.map((s) => s.filePath).whereType<String>(),
        };
      },
    );
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _store.load();
      if (!mounted) return;
      setState(() => _settings = settings);
    } catch (error) {
      if (mounted) {
        setState(
          () => _settingsError = error is DiscoveryException
              ? error.message
              : 'Could not read secure source settings. Online discovery remains off.',
        );
      }
    } finally {
      if (mounted) setState(() => _loadingSettings = false);
    }
  }

  void _cancelPreparation() {
    if (_cancel != null && !_cancel!.isCompleted) _cancel!.complete();
  }

  Future<void> _configure() async {
    _cancelPreparation();
    final settings = await Navigator.of(context).push<DiscoverySettings>(
      MaterialPageRoute(
        builder: (_) => SourceSettingsScreen(
          initial: _settings,
          store: _store,
          client: _client,
        ),
      ),
    );
    if (!mounted || settings == null) return;
    setState(() {
      _settings = settings;
      _settingsError = null;
      _playStatus = null;
      _playError = null;
    });
    _search.configure((q) => searchDiscovery(_http, settings, q));
  }

  Future<void> _openCatalog(DiscoveryTrack track) async {
    try {
      if (track.sourceUrl == null ||
          !await launchUrl(
            track.sourceUrl!,
            mode: LaunchMode.externalApplication,
          )) {
        throw const DiscoveryException(
          'No application could open the YouTube Music URL.',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _playError = discoveryError(error));
    }
  }

  Future<void> _play(DiscoveryTrack track) async {
    if (_busyKey != null) return;
    final cancellation = Completer<void>();
    _cancel = cancellation;
    setState(() {
      _busyKey = track.key;
      _playStatus = 'Resolving ${track.title}…';
      _playError = null;
    });
    try {
      final audio = await DiscoverySourceRegistry(
        _http,
        _settings,
      ).resolve(track, cancel: cancellation.future);
      if (cancellation.isCompleted || !mounted) return;
      var lastMiB = -1;
      final song = await _cache.prepare(
        track,
        audio,
        cancel: cancellation.future,
        onProgress: (bytes) {
          final mib = bytes ~/ (1024 * 1024);
          if (!mounted || cancellation.isCompleted || mib == lastMiB) return;
          lastMiB = mib;
          setState(
            () => _playStatus =
                'Downloading ${track.title}: $mib MiB / 128 MiB maximum…',
          );
        },
      );
      if (cancellation.isCompleted || !mounted) return;
      setState(() {
        _cancel =
            null; // Preparation has ended; playback now belongs to the player.
        _playStatus =
            'Starting ${song.title} (${song.fileType}, ${song.sampleRate} Hz)…';
      });
      final player = PlayerService();
      await player.play(song, playlist: [song]);
      if (!mounted || cancellation.isCompleted) return;
      // PlayerService currently swallows some queued startup exceptions, so
      // do not report success solely because its Future completed.
      setState(() {
        _playStatus = null;
        if (player.currentSongNotifier.value?.id == song.id &&
            player.isPlayingNotifier.value) {
          _playStatus =
              'Playing ${song.title}. Use the app player for playback controls.';
        } else {
          _playError =
              'Audio was verified and sent to the player, but playback has not started. Check the player and audio output.';
        }
      });
    } catch (error) {
      if (mounted && !cancellation.isCompleted) {
        setState(() {
          _playError = discoveryError(error);
          _playStatus = null;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busyKey = null;
          if (cancellation.isCompleted) _playStatus = 'Preparation cancelled.';
        });
      }
      if (identical(_cancel, cancellation)) _cancel = null;
    }
  }

  @override
  void dispose() {
    _cancelPreparation();
    _search.dispose();
    _query.dispose();
    if (widget.client == null) _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Discover'),
      actions: [
        IconButton(
          onPressed: _loadingSettings ? null : _configure,
          tooltip: 'Online sources',
          icon: const Icon(Icons.tune),
        ),
      ],
    ),
    body: SafeArea(
      child: _loadingSettings
          ? const Center(child: CircularProgressIndicator())
          : AnimatedBuilder(
              animation: _search,
              builder: (context, _) => Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: TextField(
                      controller: _query,
                      enabled: _settings.hasSource,
                      maxLength: 200,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        labelText: 'Search songs and artists',
                        counterText: '',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _query.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _query.clear();
                                  _search.updateQuery('');
                                },
                              ),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: _search.updateQuery,
                      onSubmitted: (q) =>
                          _search.updateQuery(q, immediate: true),
                    ),
                  ),
                  if (_settings.hasSource)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          [
                            if (_settings.youtubeEnabled)
                              'YouTube Music · catalog only',
                            if (_settings.activeAddons.isNotEmpty)
                              '${_settings.activeAddons.length} enabled addon(s) · cached playback',
                          ].join('  /  '),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                  if (_search.loading && _settings.hasSource)
                    const LinearProgressIndicator(),
                  if (_playStatus != null || _playError != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _playError ?? _playStatus!,
                              style: _playError == null
                                  ? null
                                  : TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                            ),
                          ),
                          if (_busyKey != null && _cancel != null)
                            TextButton(
                              onPressed: _cancelPreparation,
                              child: const Text('Cancel'),
                            ),
                        ],
                      ),
                    ),
                  Expanded(child: _body(context)),
                ],
              ),
            ),
    ),
  );

  Widget _body(BuildContext context) {
    if (!_settings.hasSource) {
      return _empty(
        Icons.travel_explore,
        'Online discovery is off',
        _settingsError ??
            'Enable public YouTube Music catalog search or connect your own HTTPS music addon.',
        action: FilledButton(
          onPressed: _configure,
          child: const Text('Choose sources'),
        ),
      );
    }
    if (_search.query.isEmpty) {
      return _empty(
        Icons.music_note_outlined,
        'Find your next recording',
        'Search your enabled sources. YouTube results open externally; addon recordings can play here after download and verification.',
      );
    }
    if (_search.loading) {
      return _empty(
        Icons.search,
        'Searching…',
        'Waiting for your enabled sources.',
      );
    }
    final results = _search.results;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        for (final error in results.errors)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(error),
                  TextButton(
                    onPressed: () =>
                        _search.updateQuery(_query.text, immediate: true),
                    child: const Text('Retry search'),
                  ),
                ],
              ),
            ),
          ),
        if (results.tracks.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              results.errors.isEmpty
                  ? 'No recordings found. Try a different title or artist.'
                  : 'No results available from the enabled sources.',
              textAlign: TextAlign.center,
            ),
          ),
        for (final track in results.tracks)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      track.artist,
                      if (track.album != null) track.album!,
                      if (track.duration != null)
                        '${track.duration!.inMinutes}:${(track.duration!.inSeconds % 60).toString().padLeft(2, '0')}',
                    ].join(' · '),
                  ),
                  const SizedBox(height: 8),
                  if (track.source == DiscoverySource.youtubeMusic)
                    OutlinedButton.icon(
                      onPressed: () => _openCatalog(track),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Open in YouTube Music'),
                    )
                  else
                    FilledButton.tonalIcon(
                      onPressed: _busyKey == null ? () => _play(track) : null,
                      icon: _busyKey == track.key
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_arrow),
                      label: Text(
                        _busyKey == track.key
                            ? 'Preparing audio…'
                            : 'Play from ${track.sourceName ?? 'Music addon'}',
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _empty(IconData icon, String title, String text, {Widget? action}) =>
      Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 44),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(text, textAlign: TextAlign.center),
              if (action != null) ...[const SizedBox(height: 20), action],
            ],
          ),
        ),
      );
}
