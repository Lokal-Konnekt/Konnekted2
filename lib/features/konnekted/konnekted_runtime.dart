import 'package:flick/features/spotify/spotify_likes_sync_service.dart';
import 'package:flick/services/queue_pre_resolver.dart';
import 'package:flick/services/local_metadata_repair.dart';
import 'package:flick/services/lokal_launcher_icon.dart';
import 'package:flick/features/library_jobs/artist_metadata.dart';

import 'konnekted_data.dart';

import 'package:flick/features/library_jobs/library_jobs.dart';
import 'package:flick/widgets/lokal/lokal_status_snack.dart';
import 'package:flick/l10n/l10n.dart';
import 'package:flick/providers/app_build_info_provider.dart';

import 'dart:async';

import 'package:flick/core/utils/app_log.dart';
import 'package:flick/core/utils/dev_log.dart';
import 'package:flick/core/utils/navigation_helper.dart';
import 'package:flick/features/whats_new/widgets/whats_new_bottom_sheet.dart';
import 'package:flick/providers/equalizer_provider.dart';
import 'package:flick/providers/providers.dart';
import 'package:flick/services/library_scanner_service.dart';
import 'package:flick/services/player_service.dart';
import 'package:flick/services/discord_presence_service.dart';
import 'package:flick/services/widget_intent_handler.dart';
import 'package:flick/services/widget_sync_service.dart';
import 'package:flick/widgets/common/floating_scan_progress.dart';
import 'package:flick/widgets/uac2/usb_bit_perfect_prompt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Non-visual responsibilities formerly owned by MainShell. Mount exactly once,
/// after onboarding and native/bootstrap initialization, inside a Scaffold.
class KonnektedRuntime extends ConsumerStatefulWidget {
  const KonnektedRuntime({
    super.key,
    required this.child,
    required this.onOpenPlayer,
    required this.onOpenQueue,
  });

  final Widget child;
  final VoidCallback onOpenPlayer;
  final VoidCallback onOpenQueue;

  @override
  ConsumerState<KonnektedRuntime> createState() => _KonnektedRuntimeState();
}

class _KonnektedRuntimeState extends ConsumerState<KonnektedRuntime>
    with WidgetsBindingObserver {
  late final PlayerService _player;
  late final WidgetIntentHandler _widgetIntents;
  late final ProviderSubscription<PlayerState> _widgetSync;
  late final _jobProgress = LokalStatusSnack(
    () => mounted ? ScaffoldMessenger.maybeOf(context) : null,
  );
  late final _playbackProgress = LokalStatusSnack(
    () => mounted ? ScaffoldMessenger.maybeOf(context) : null,
  );
  void _onPreparationStatus() {
    if (!mounted) return;
    final message = QueuePreResolver.shared.status.value;
    if (message == null) {
      _playbackProgress.clear();
    } else {
      _playbackProgress.update(message);
    }
  }

  bool _backgrounded = false;
  bool _showingWhatsNew = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SpotifyLikesSyncService.instance.resume();
    ref.listenManual(libraryJobsProvider, (previous, next) {
      _updateIconBusy();
      if (next.running)
        _jobProgress.update(next.message);
      else if (previous?.running == true)
        _jobProgress.fail(next.message);
    });
    ref.listenManual(konnektedLibraryProvider, (_, next) {
      final songs = next.value;
      if (songs != null) {
        ref.read(artistMetadataProvider.notifier).warm(songs);
        LocalMetadataRepair.instance.warm(songs);
      }
    }, fireImmediately: true);
    _player = ref.read(playerServiceProvider);
    _player.isPlayingNotifier.addListener(_updateIconBusy);
    _player.isNetworkLoadingNotifier.addListener(_updateIconBusy);
    _updateIconBusy();
    _run(
      'Discord presence',
      () => DiscordPresenceService.instance.start(_player),
    );
    ref.read(equalizerProvider);
    ref.read(updateCheckProvider.notifier);
    _widgetSync = installWidgetSync(ref);
    _widgetIntents = WidgetIntentHandler(
      ref,
      onOpenQueue: () {
        if (mounted) widget.onOpenQueue();
      },
    );
    _run('Widget intent attachment', _widgetIntents.attach);
    _player.playbackDesyncedNotifier.addListener(_onPlaybackDesync);
    _player.onlinePlaybackError.addListener(_onOnlinePlaybackError);
    QueuePreResolver.shared.status.addListener(_onPreparationStatus);

    ref.listenManual(appPreferencesProvider, (_, _) => _maybeShowWhatsNew());
    ref.listenManual(appBuildInfoProvider, (_, _) => _maybeShowWhatsNew());

    ref.listenManual(currentSongProvider, (_, _) => _maybeOpenExternalPlayer());
    ref.listenManual(isPlayingProvider, (_, _) => _maybeOpenExternalPlayer());
    // Songs a scan added still need their details (sample rate, disc,
    // album artist) read in the background. That is not part of the scan:
    // start it straight away and silently, instead of a snackbar per batch
    // (they queued up and read as a scan that never ended).
    ref.listenManual<AsyncValue<int>>(libraryWarmupProvider, (previous, next) {
      final count = next.value ?? 0;
      if (!mounted || count <= (previous?.value ?? 0)) return;
      final service = ref.read(backgroundMetadataServiceProvider);
      if (service != null) {
        _run('Metadata warmup', service.extractPendingMetadata);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _maybeOpenExternalPlayer();
      ref.read(autoLibrarySyncServiceProvider);
      ref.read(updateCheckProvider.notifier).refreshIfOnline();
      _run('Library deletion refresh', () async {
        await LibraryScannerService().refreshDeletions();
        if (!mounted) return;
        ref.invalidate(songsProvider);
        ref.invalidate(musicFoldersProvider);
      });
    });
  }

  void _run(String label, FutureOr<void> Function() operation) {
    unawaited(
      Future<void>.sync(operation).catchError((Object error, StackTrace stack) {
        devLog('$label failed: $error');
      }),
    );
  }

  void _maybeOpenExternalPlayer() {
    if (!mounted) return;
    final song = ref.read(currentSongProvider);
    if (song?.isExternal != true || !ref.read(isPlayingProvider)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || NavigationHelper.isFullPlayerOpen) return;
      if (ref.read(currentSongProvider)?.id == song!.id &&
          ref.read(isPlayingProvider)) {
        widget.onOpenPlayer();
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _updateIconBusy() => unawaited(
    LokalLauncherIcon.setBusy(
      _player.isPlayingNotifier.value ||
          _player.isNetworkLoadingNotifier.value ||
          ref.read(libraryJobsProvider).running,
    ),
  );

  void _maybeShowWhatsNew() {
    if (!mounted ||
        _showingWhatsNew ||
        !ref.read(onboardingCompletedProvider)) {
      return;
    }
    final notifier = ref.read(whatsNewProvider.notifier);
    notifier.evaluate();
    final entry = ref.read(whatsNewProvider).pendingEntry;
    if (entry == null) return;
    _showingWhatsNew = true;
    _run('What’s new', () async {
      try {
        await notifier.markCurrentVersionSeen();
        if (mounted) await WhatsNewBottomSheet.show(context, entry: entry);
      } finally {
        _showingWhatsNew = false;
      }
    });
  }

  void _onOnlinePlaybackError() {
    final message = _player.onlinePlaybackError.value;
    if (!mounted || message == null) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  void _onPlaybackDesync() {
    if (!mounted || !_player.playbackDesyncedNotifier.value) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(lokalText('Playback needs to be synchronized')),
        action: SnackBarAction(
          label: lokalText('Sync'),
          onPressed: () => _run('Playback sync', _player.syncNow),
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _run('Persist playback', _player.persistLastPlayed);
      _run('Widget shutdown sync', WidgetSyncService.instance.pushKilled);
      // Match MainShell: this also deactivates the Android floating overlay.
      _run('Detached player cleanup', _player.onAppResumed);
      _run('Flush app log', AppLog.instance.flushToDisk);
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (_backgrounded) return;
      _backgrounded = true;
      SpotifyLikesSyncService.instance.pause();
      ref.read(autoLibrarySyncServiceProvider).notifyPaused();
      _run('Persist playback', _player.persistLastPlayed);
      _run('Widget background sync', WidgetSyncService.instance.pushPaused);
      _run('Pause app lifecycle', _player.onAppPaused);
      _run('Flush app log', AppLog.instance.flushToDisk);
      _finishPausedScrobble();
    } else if (state == AppLifecycleState.resumed) {
      SpotifyLikesSyncService.instance.resume();
      _backgrounded = false;
      _run('Resume app lifecycle', _player.onAppResumed);
      ref.read(updateCheckProvider.notifier).refreshIfOnline();
      _run('Last.fm queue flush', ref.read(lastFmScrobbleQueueProvider).flush);
      _run(
        'ListenBrainz queue flush',
        ref.read(listenbrainzScrobbleQueueProvider).flush,
      );
      ref.read(autoLibrarySyncServiceProvider).notifyResumed();
    }
  }

  void _finishPausedScrobble() {
    final state = ref.read(playerProvider);
    final song = state.currentSong;
    if (song == null || song.isExternal || state.isPlaying) return;
    final seconds = ref.read(playerProvider.notifier).accumulatedListenSeconds;
    _run(
      'Last.fm paused scrobble',
      () => ref
          .read(lastFmScrobbleProvider.notifier)
          .onTrackEnded(
            artist: song.artist,
            track: song.title,
            album: song.album,
            albumArtist: null,
            listenedSeconds: seconds,
            trackDurationSeconds: state.duration.inSeconds,
          ),
    );
    _run(
      'ListenBrainz paused scrobble',
      () => ref
          .read(listenBrainzScrobbleProvider.notifier)
          .onTrackEnded(
            artist: song.artist,
            track: song.title,
            album: song.album,
            albumArtist: null,
            listenedSeconds: seconds,
            trackDurationSeconds: state.duration.inSeconds,
          ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SpotifyLikesSyncService.instance.pause();
    _player.playbackDesyncedNotifier.removeListener(_onPlaybackDesync);
    _player.onlinePlaybackError.removeListener(_onOnlinePlaybackError);
    QueuePreResolver.shared.status.removeListener(_onPreparationStatus);
    _playbackProgress.dispose();
    _player.isPlayingNotifier.removeListener(_updateIconBusy);
    _player.isNetworkLoadingNotifier.removeListener(_updateIconBusy);
    _jobProgress.dispose();
    _widgetSync.close();
    _run('Widget intent detach', _widgetIntents.detach);
    _run('Discord presence shutdown', DiscordPresenceService.instance.stop);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Positioned.fill(child: widget.child),
      const Positioned.fill(child: FloatingScanProgress()),
      const UsbBitPerfectPrompt(),
    ],
  );
}
