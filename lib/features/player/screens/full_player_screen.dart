import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/player/lokal_lyrics_subline.dart';
import 'package:flick/features/player/screens/classic_full_player_screen.dart';
import 'package:flick/features/player/widgets/audio_visualizer.dart';
import 'package:flick/features/player/widgets/song_stage_carousel.dart';
import 'package:flick/features/player/widgets/player_artwork_image.dart';
import 'package:flick/features/queue/screens/queue_screen.dart';
import 'package:flick/widgets/lokal/lokal_like_burst.dart';
import 'package:flick/widgets/lokal/lokal_player_artwork.dart';
import 'package:flick/widgets/lokal/lokal_pull_to_dismiss.dart';
import 'package:flick/widgets/lokal/lokal_quality.dart';
import 'package:flick/widgets/lokal/lokal_queue_reveal.dart';
import 'package:flick/features/player/widgets/loop_mode_sheet.dart';
import 'package:flick/features/player/widgets/online_lyrics_search_sheet.dart';
import 'package:flick/features/player/screens/lyrics_sync_screen.dart';
import 'package:flick/features/player/widgets/shuffle_mode_sheet.dart';
import 'package:flick/features/player/widgets/sleep_timer_bottom_sheet.dart';
import 'package:flick/features/player/widgets/pitch_bottom_sheet.dart';
import 'package:flick/features/konnekted/library/lokal_navigation.dart';
import 'package:flick/features/player/widgets/song_metadata_sheet.dart';
import 'package:flick/features/songs/widgets/song_actions_bottom_sheet.dart';
import 'package:flick/features/player/widgets/speed_bottom_sheet.dart';
import 'package:flick/features/settings/screens/casting_settings_screen.dart';
import 'package:flick/features/settings/screens/equalizer_screen.dart';
import 'package:flick/l10n/l10n.dart';
import 'package:flick/models/audio_output_diagnostics.dart';
import 'package:flick/models/shuffle_mode.dart';
import 'package:flick/models/song.dart';
import 'package:flick/providers/providers.dart';
import 'package:flick/services/favorites_service.dart';
import 'package:flick/services/lyrics_service.dart';
import 'package:flick/services/player_service.dart';
import 'package:flick/widgets/common/cached_image_widget.dart';
import 'package:flick/widgets/common/flick_artwork_placeholder.dart';
import 'package:flick/widgets/common/flick_dialog.dart';

const String _font = 'GoogleSansFlex';

/// Wave player: fluid artwork backdrop, big art, flowing lyrics, and labeled
/// action chips. The same constructor keeps the mini-player and navigation
/// entry points working with this player.
class FullPlayerScreen extends ConsumerStatefulWidget {
  final Object heroTag;
  const FullPlayerScreen({super.key, this.heroTag = 'album_art_hero'});

  @override
  ConsumerState<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends ConsumerState<FullPlayerScreen>
    with SingleTickerProviderStateMixin {
  final PlayerService _player = PlayerService();
  final FavoritesService _favorites = FavoritesService();
  final LyricsService _lyricsService = LyricsService();

  bool _showLyrics = false;
  bool _lyricsLoading = false;
  LyricsData? _lyrics;
  String? _lyricsForSongId;

  bool _isFav = false;
  String? _favForSongId;

  double _volume = 1.0;
  bool _draggingSeek = false;
  double _seekDrag = 0;
  bool _draggingVolume = false;

  bool _carouselDragging = false;
  final _carouselKey = GlobalKey<SongStageCarouselState>();

  /// The queue opens in place: the cover shrinks into a header row and the
  /// list rises under it, all off this one value (0 = player, 1 = queue).
  late final AnimationController _queueProgress = AnimationController(
    vsync: this,
  );
  late final LokalQueueRevealMotion _queue = LokalQueueRevealMotion(
    _queueProgress,
  )..addListener(_onQueueTargetChanged);

  int _burst = 0;
  bool _burstVisible = false;

  @override
  void initState() {
    super.initState();
    _volume = _player.currentVolume.clamp(0.0, _player.maxVolume).toDouble();
    _player.currentSongNotifier.addListener(_onSongChanged);
    _player.favoriteNotificationToggleNotifier.addListener(_refreshFavorite);
    _refreshFavorite();
    unawaited(LokalLyricsSubline.load());
  }

  @override
  void dispose() {
    _queue.dispose();
    _queueProgress.dispose();
    _player.currentSongNotifier.removeListener(_onSongChanged);
    _player.favoriteNotificationToggleNotifier.removeListener(_refreshFavorite);
    super.dispose();
  }

  void _onSongChanged() {
    _refreshFavorite();
    if (_showLyrics) _loadLyrics();
  }

  Future<void> _refreshFavorite() async {
    final song = _player.currentSongNotifier.value;
    if (song == null) return;
    final fav = await _favorites.isFavorite(song.id);
    if (!mounted) return;
    setState(() {
      _isFav = fav;
      _favForSongId = song.id;
    });
  }

  Future<void> _toggleFavorite() async {
    final song = _player.currentSongNotifier.value;
    if (song == null) return;
    HapticFeedback.selectionClick();
    final nowFav = await _favorites.toggleFavorite(song.id);
    if (!mounted) return;
    setState(() {
      _isFav = nowFav;
      _favForSongId = song.id;
    });
  }

  Future<void> _loadLyrics({bool force = false}) async {
    final song = _player.currentSongNotifier.value;
    if (song == null) return;
    if (!force && _lyricsForSongId == song.id && _lyrics != null) return;
    setState(() {
      _lyricsLoading = true;
      _lyrics = null;
      _lyricsForSongId = song.id;
    });
    LyricsData? data;
    try {
      data = await _lyricsService.loadLyricsForSong(
        song,
        forceRefresh: force,
        fetchOnline: ref.read(appPreferencesProvider).lyricsAutoFetch,
      );
    } catch (_) {
      data = null;
    }
    if (!mounted) return;
    if (_player.currentSongNotifier.value?.id != song.id) return;
    setState(() {
      _lyrics = data;
      _lyricsLoading = false;
    });
  }

  void _toggleLyrics() {
    // Lyrics take the queue's place outright rather than animating over it.
    if (!_showLyrics && _queue.isOpen) _queue.setOpen(false, animate: false);
    setState(() => _showLyrics = !_showLyrics);
    if (_showLyrics) _loadLyrics();
  }

  // ───────────────────────────── queue reveal ─────────────────────────────

  void _onQueueTargetChanged() {
    if (mounted) setState(() {});
  }

  bool get _animate => !MediaQuery.disableAnimationsOf(context);

  void _setQueueOpen(bool open) {
    if (open == _queue.isOpen) return;
    HapticFeedback.selectionClick();
    if (open && _showLyrics) setState(() => _showLyrics = false);
    _queue.setOpen(open, animate: _animate);
  }

  void _toggleQueue() => _setQueueOpen(!_queue.isOpen);

  void _releaseQueue(double upVelocity) {
    final was = _queue.isOpen;
    if (_queue.release(upVelocity, animate: _animate) != was) {
      HapticFeedback.selectionClick();
    }
  }

  void _close() => Navigator.of(context).pop();

  // ───────────────────────────── gestures ─────────────────────────────

  /// Double-tapping the artwork likes the song (never unlikes it), with a
  /// burst over the cover.
  void _likeFromArtwork() {
    HapticFeedback.mediumImpact();
    setState(() {
      _burst++;
      _burstVisible = true;
    });
    if (!_isFav) _toggleFavorite();
  }

  Future<void> _openVisualizer() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _NowPlayingVisualizerScreen(player: _player),
    ),
  );

  Future<void> _openEqualizer() => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const EqualizerScreen()));

  Future<void> _openCasting() => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const CastingSettingsScreen()),
  );

  /// The Now Playing menu retains only actions that aren't already surfaced
  /// as player controls or as taps on the track title, artist, and quality pill.
  void _openMore(Song song) {
    SongActionsBottomSheet.show(
      context,
      song,
      nowPlaying: true,
      extras: [
        LokalSongMenuAction(
          icon: Icons.graphic_eq_rounded,
          label: 'Pitch',
          onTap: () {
            if (mounted) PitchBottomSheet.show(context, _player);
          },
        ),
      ],
    );
  }

  Future<void> _openOutputPopup(Song song) {
    return showFlickDialog<void>(
      context: context,
      barrierLabel: 'Audio output',
      barrierColor: Colors.black.withValues(alpha: 0.38),
      builder: (_) => OutputDevicePopup(
        song: song,
        playerService: _player,
        deviceLabel: l10n.thisDevice,
      ),
    );
  }

  // ───────────────────────────── build ─────────────────────────────

  @override
  Widget build(BuildContext context) {
    final palette = ref.watch(albumPaletteSyncProvider);
    final dominant = ref.watch(albumDominantColorSyncProvider);
    final isCasting = ref.watch(isCastingProvider);
    final diagnostics = ref.watch(audioOutputDiagnosticsProvider);
    final colors = palette.length >= 2
        ? palette
        : [
            dominant ?? const Color(0xFF3B3B44),
            HSLColor.fromColor(dominant ?? const Color(0xFF3B3B44))
                .withLightness(0.3)
                .toColor(),
            const Color(0xFF14141A),
          ];

    return PopScope(
      // Back puts the queue or the lyrics away first, then closes the player.
      canPop: !_showLyrics && !_queue.isOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_queue.isOpen) {
          _setQueueOpen(false);
        } else if (_showLyrics) {
          _toggleLyrics();
        }
      },
      child: LokalPullToDismiss(
        onDismiss: _close,
        // Pulling up drags the queue in, following the finger.
        onPullUpUpdate: _showLyrics ? null : _queue.dragBy,
        onPullUpEnd: _showLyrics ? null : _releaseQueue,
        // While the queue is out, its header owns vertical drags.
        isBlocked: () => _carouselDragging || _queue.engaged,
        child: _scaffold(colors, isCasting, diagnostics),
      ),
    );
  }

  Widget _scaffold(
    List<Color> colors,
    bool isCasting,
    AudioOutputDiagnostics? diagnostics,
  ) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: ValueListenableBuilder<Song?>(
        valueListenable: _player.currentSongNotifier,
        builder: (context, song, _) {
          if (song == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return Stack(
            fit: StackFit.expand,
            children: [
              _FluidBackdrop(colors: colors, song: song),
              Container(color: Colors.black.withValues(alpha: 0.24)),
              SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    18,
                    0,
                    18,
                    14, // keeps the chip row clear of the system nav bar
                  ),
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final compact = c.maxHeight < 640;
                      return Column(
                        children: [
                          _topBar(song, isCasting, diagnostics),
                          Expanded(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 260),
                              child: _showLyrics
                                  ? _lyricsArea(song)
                                  : _artArea(song, compact),
                            ),
                          ),
                          _seekRow(),
                          SizedBox(height: compact ? 6 : 10),
                          _transport(compact),
                          SizedBox(height: compact ? 8 : 12),
                          if (!_showLyrics) ...[
                            _optionsStrip(),
                            SizedBox(height: compact ? 8 : 12),
                          ],
                          _chipRow(),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ───────────────────────────── top bar ─────────────────────────────

  Widget _topBar(
    Song song,
    bool isCasting,
    AudioOutputDiagnostics? diagnostics,
  ) {
    final label = diagnostics?.outputDeviceLabel.trim().isNotEmpty == true
        ? diagnostics!.outputDeviceLabel.trim()
        : diagnostics?.routeLabel.trim().isNotEmpty == true
        ? diagnostics!.routeLabel.trim()
        : l10n.thisDevice;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          _roundIcon(LucideIcons.chevronLeft, _close),
          const SizedBox(width: 8),
          Expanded(
            child: Align(
              alignment: Alignment.center,
              child: _pill(
                onTap: () => _openOutputPopup(song),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 190),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        LucideIcons.headphones,
                        size: 17,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: _font,
                            fontSize: 13,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _roundIcon(LucideIcons.cast, _openCasting, active: isCasting),
          const SizedBox(width: 4),
          _roundIcon(Icons.more_vert, () => _openMore(song)),
        ],
      ),
    );
  }

  Widget _roundIcon(IconData icon, VoidCallback onTap, {bool active = false}) {
    return Material(
      color: active ? Colors.white.withValues(alpha: 0.26) : Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 22, color: Colors.white),
        ),
      ),
    );
  }

  Widget _pill({
    required Widget child,
    VoidCallback? onTap,
    bool selected = false,
  }) {
    return Material(
      color: selected
          ? context.lokal.accent.withValues(alpha: 0.22)
          : Colors.white.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected
              ? context.lokal.accent.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.18),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: child,
        ),
      ),
    );
  }

  // ───────────────────────────── artwork / lyrics ─────────────────────────────

  Widget _artArea(Song song, bool compact) {
    final titleSize = compact ? 26.0 : 32.0;
    return LayoutBuilder(
      key: const ValueKey('art'),
      builder: (context, c) {
        // A finger travels about the cover's height for the whole reveal.
        _queue.travel = math.max(math.min(c.maxWidth, c.maxHeight) * .8, 200);
        return LokalQueueReveal(
          progress: _queueProgress,
          open: _queue.isOpen,
          artGap: compact ? 8 : 16,
          onHeaderTap: () => _setQueueOpen(false),
          onHeaderDragUpdate: _queue.dragBy,
          onHeaderDragEnd: _releaseQueue,
          artwork: (context, size, p) {
            final atRest = p == 0 && !_queue.isOpen;
            // Follows the finger; neighbours slide in beside the cover.
            return ValueListenableBuilder<List<Song>>(
              valueListenable: _player.upNextNotifier,
              builder: (context, _, __) => ValueListenableBuilder<int>(
                valueListenable: _player.currentIndexNotifier,
                builder: (context, _, __) => SongStageCarousel(
                  key: _carouselKey,
                  currentSong: song,
                  nextSong: _player.peekNext,
                  prevSong: _player.peekPrevious,
                  enabled: atRest,
                  onDragStateChanged: (v) => _carouselDragging = v,
                  onNext: _player.next,
                  onPrevious: _player.previousBySwipe,
                  stageBuilder: (s) => Align(
                    alignment: LokalQueueReveal.coverAlignment(p),
                    child: _artwork(
                      s,
                      size,
                      current: s.id == song.id,
                      progress: p,
                    ),
                  ),
                ),
              ),
            );
          },
          info: (context, p) => AnimatedSwitcher(
            duration: _animate
                ? const Duration(milliseconds: 420)
                : Duration.zero,
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topLeft,
              children: [...previous, if (current != null) current],
            ),
            child: Column(
              key: ValueKey(song.id),
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: _font,
                    fontSize: lerpDouble(titleSize, 18, p),
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: lerpDouble(2, 1, p)),
                InkWell(
                  onTap: song.artist.trim().isEmpty
                      ? null
                      : () => openLokalArtist(context, song: song),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: _font,
                        fontSize: lerpDouble(14, 13, p),
                        color: Colors.white.withValues(alpha: .72),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Tapping the quality tier opens the full song metadata sheet.
          badge: switch (LokalQualityTier.of(song)) {
            final tier? => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => SongMetadataSheet.show(context, song),
              child: LokalQualityPill(tier: tier),
            ),
            null => null,
          },
          queue: const QueueList(embedded: true),
        );
      },
    );
  }

  Widget _artwork(
    Song song,
    double side, {
    required bool current,
    double progress = 0,
  }) {
    final art = PlayerArtworkImage(
      song: song,
      radius: lerpDouble(28, 12, progress)!,
    );
    final shown = _burst;
    return GestureDetector(
      onDoubleTap: current && progress == 0 ? _likeFromArtwork : null,
      child: LokalPlayerArtwork(
        enabled: current,
        child: SizedBox(
          width: side,
          height: side,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: current
                    ? Hero(
                        tag: widget.heroTag,
                        createRectTween: (begin, end) =>
                            RectTween(begin: begin, end: end),
                        flightShuttleBuilder:
                            (
                              flightContext,
                              animation,
                              direction,
                              fromContext,
                              toContext,
                            ) => AnimatedBuilder(
                              animation: animation,
                              builder: (context, child) => ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  lerpDouble(
                                    21,
                                    28,
                                    Curves.easeInOutCubic.transform(
                                      animation.value,
                                    ),
                                  )!,
                                ),
                                child: child,
                              ),
                              child: CachedImageWidget(
                                imagePath: song.albumArt,
                                audioSourcePath: song.filePath,
                                fit: BoxFit.cover,
                                placeholder: ColoredBox(
                                  color: flightContext.lokal.surface3,
                                ),
                                errorWidget: ColoredBox(
                                  color: flightContext.lokal.surface3,
                                ),
                              ),
                            ),
                        child: art,
                      )
                    : art,
              ),
              if (current && _burstVisible)
                LokalLikeBurst(
                  key: ValueKey(_burst),
                  color: context.lokal.accent,
                  size: side * .28,
                  onDone: () {
                    if (mounted && shown == _burst) {
                      setState(() => _burstVisible = false);
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _lyricsArea(Song song) {
    final data = _lyrics;
    Widget body;
    if (_lyricsLoading) {
      body = const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: Colors.white70,
          ),
        ),
      );
    } else if (data == null || data.lines.isEmpty) {
      body = _noLyrics(song);
    } else if (!data.isSynchronized) {
      body = SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(0, 24, 0, 40),
        child: Text(
          data.lines.map((l) => l.text).join('\n'),
          style: const TextStyle(
            fontFamily: _font,
            fontSize: 26,
            height: 1.35,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      );
    } else {
      body = ValueListenableBuilder<bool>(
        valueListenable: LokalLyricsSubline.showTranslation,
        builder: (context, translate, _) => _FlowingLyrics(
          key: ValueKey('${song.id}|${data.lines.length}|$translate'),
          player: _player,
          lyrics: data,
          showTranslation: translate,
        ),
      );
    }

    return Column(
      key: const ValueKey('lyrics'),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Lyrics',
                style: TextStyle(
                  fontFamily: _font,
                  fontSize: 13,
                  letterSpacing: 0.6,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ),
            // Shown when the lyrics carry their own translation, as desktop.
            if (LokalLyricsSubline.hasTranslation(data))
              ValueListenableBuilder<bool>(
                valueListenable: LokalLyricsSubline.showTranslation,
                builder: (context, translate, _) => IconButton(
                  tooltip: translate ? 'Hide translation' : 'Show translation',
                  isSelected: translate,
                  icon: Icon(
                    LucideIcons.languages,
                    size: 20,
                    color: translate ? context.lokal.accent : Colors.white70,
                  ),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    LokalLyricsSubline.toggle();
                  },
                ),
              ),
            IconButton(
              tooltip: 'Search online',
              icon: const Icon(
                LucideIcons.search,
                size: 20,
                color: Colors.white70,
              ),
              onPressed: () => _searchOnline(song),
            ),
            IconButton(
              tooltip: 'Edit lyrics',
              icon: const Icon(
                LucideIcons.pencil,
                size: 20,
                color: Colors.white70,
              ),
              onPressed: () => _editLyrics(song),
            ),
          ],
        ),
        Expanded(
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (r) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black,
                Colors.black,
                Colors.transparent,
              ],
              stops: [0.0, 0.07, 0.9, 1.0],
            ).createShader(r),
            child: body,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: CachedImageWidget(
                    imagePath: song.albumArt,
                    audioSourcePath: song.filePath,
                    fit: BoxFit.cover,
                    placeholder: const FlickArtworkPlaceholder(),
                    errorWidget: const FlickArtworkPlaceholder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: _font,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: _font,
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _noLyrics(Song song) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'No lyrics found',
            style: TextStyle(
              fontFamily: _font,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.tonalIcon(
            onPressed: () => _searchOnline(song),
            icon: const Icon(LucideIcons.search, size: 18),
            label: const Text('Search online'),
          ),
        ],
      ),
    );
  }

  Future<void> _searchOnline(Song song) async {
    final result = await OnlineLyricsSearchSheet.show(
      context: context,
      song: song,
      lyricsService: _lyricsService,
    );
    if (result == true && mounted) await _loadLyrics(force: true);
  }

  Future<void> _editLyrics(Song song) async {
    final result = await LyricsSyncScreen.open(
      context: context,
      song: song,
      playerService: _player,
      lyricsService: _lyricsService,
      initialLyrics: _lyrics,
    );
    if (result != null && mounted) await _loadLyrics(force: true);
  }

  // ───────────────────────────── seek / transport ─────────────────────────────

  String _clock(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  Widget _seekRow() {
    const mono = TextStyle(
      fontFamily: 'monospace',
      fontSize: 11,
      color: Color(0xB3FFFFFF),
    );
    return ValueListenableBuilder<Duration>(
      valueListenable: _player.durationNotifier,
      builder: (context, duration, _) {
        final totalMs = math.max(duration.inMilliseconds, 1).toDouble();
        return ValueListenableBuilder<Duration>(
          valueListenable: _player.positionNotifier,
          builder: (context, position, _) {
            final live = (position.inMilliseconds / totalMs).clamp(0.0, 1.0);
            final value = _draggingSeek ? _seekDrag : live;
            return Column(
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3.5,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    overlayShape: SliderComponentShape.noOverlay,
                    activeTrackColor: context.lokal.accent,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.white,
                  ),
                  child: Slider(
                    value: value,
                    onChangeStart: (_) => setState(() => _draggingSeek = true),
                    onChanged: (v) => setState(() => _seekDrag = v),
                    onChangeEnd: (v) {
                      _player.seek(
                        Duration(milliseconds: (v * totalMs).round()),
                      );
                      setState(() => _draggingSeek = false);
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _clock(
                          Duration(milliseconds: (value * totalMs).round()),
                        ),
                        style: mono,
                      ),
                      Text(_clock(duration), style: mono),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _transport(bool compact) {
    Widget big({
      required int flex,
      required Color color,
      required VoidCallback onTap,
      required Widget child,
    }) {
      return Expanded(
        flex: flex,
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(28),
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: onTap,
            child: Center(child: child),
          ),
        ),
      );
    }

    final glass = Colors.white.withValues(alpha: 0.13);
    final tokens = context.lokal;
    return SizedBox(
      height: compact ? 66 : 82,
      child: Row(
        children: [
          big(
            flex: 10,
            color: glass,
            onTap: () =>
                _carouselKey.currentState?.animateToPrevious() ??
                _player.previous(),
            child: const Icon(
              Icons.skip_previous_rounded,
              size: 32,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          big(
            flex: 17,
            color: tokens.accent,
            onTap: () => _player.togglePlayPause(),
            child: ValueListenableBuilder<bool>(
              valueListenable: _player.isPlayingNotifier,
              builder: (_, playing, __) => AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  key: ValueKey(playing),
                  size: 40,
                  color: tokens.onAccent,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          big(
            flex: 10,
            color: glass,
            onTap: () =>
                _carouselKey.currentState?.animateToNext() ?? _player.next(),
            child: const Icon(
              Icons.skip_next_rounded,
              size: 32,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _optionsStrip() {
    final maxVol = _player.maxVolume;
    final sliderValue = (_draggingVolume ? _volume : _player.currentVolume)
        .clamp(0.0, maxVol)
        .toDouble();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Icon(
            sliderValue <= 0.001 ? LucideIcons.volumeX : LucideIcons.volume2,
            size: 19,
            color: Colors.white.withValues(alpha: 0.85),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3.5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: SliderComponentShape.noOverlay,
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
              ),
              child: Slider(
                value: sliderValue,
                min: 0,
                max: maxVol,
                onChangeStart: (_) => setState(() => _draggingVolume = true),
                onChanged: (v) {
                  setState(() => _volume = v);
                  _player.setVolume(v);
                },
                onChangeEnd: (_) => setState(() => _draggingVolume = false),
              ),
            ),
          ),
          Container(width: 1, height: 26, color: Colors.white24),
          const SizedBox(width: 6),
          ValueListenableBuilder<ShuffleMode>(
            valueListenable: _player.shuffleModeNotifier,
            builder: (_, mode, __) => _toggle(
              LucideIcons.shuffle,
              mode.isActive,
              () => _player.toggleShuffle(),
              onLong: () => ShuffleModeSheet.show(context, _player),
            ),
          ),
          ValueListenableBuilder<LoopMode>(
            valueListenable: _player.loopModeNotifier,
            builder: (_, mode, __) => _toggle(
              mode == LoopMode.one ? LucideIcons.repeat1 : LucideIcons.repeat,
              mode != LoopMode.off,
              () => _player.toggleLoopMode(),
              onLong: () => LoopModeSheet.show(context, _player),
            ),
          ),
          _toggle(
            _isFav ? Icons.favorite : Icons.favorite_border,
            _isFav,
            _toggleFavorite,
          ),
        ],
      ),
    );
  }

  Widget _toggle(
    IconData icon,
    bool on,
    VoidCallback onTap, {
    VoidCallback? onLong,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: on
            ? context.lokal.accent.withValues(alpha: 0.22)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          onLongPress: onLong,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(
              icon,
              size: 20,
              color: on ? context.lokal.accent : Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  // ───────────────────────────── chips ─────────────────────────────

  Widget _chipRow() {
    Widget chip(
      IconData icon,
      String label,
      VoidCallback onTap, {
      bool active = false,
    }) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: _pill(
          selected: active,
          onTap: onTap,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontFamily: _font,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          chip(
            LucideIcons.listMusic,
            l10n.queue,
            _toggleQueue,
            active: _queue.isOpen,
          ),
          chip(
            LucideIcons.messageSquareQuote,
            l10n.lyrics,
            _toggleLyrics,
            active: _showLyrics,
          ),
          ValueListenableBuilder<Duration?>(
            valueListenable: _player.sleepTimerRemainingNotifier,
            builder: (_, remaining, __) => chip(
              LucideIcons.moonStar,
              remaining == null ? l10n.sleepTimer : _clock(remaining),
              () => SleepTimerBottomSheet.show(context, _player),
              active: remaining != null,
            ),
          ),
          ValueListenableBuilder<double>(
            valueListenable: _player.playbackSpeedNotifier,
            builder: (_, speed, __) => chip(
              LucideIcons.gauge,
              (speed - 1.0).abs() < 0.01
                  ? l10n.speedUp
                  : '${speed.toStringAsFixed(2)}x',
              () => SpeedBottomSheet.show(context, _player),
              active: (speed - 1.0).abs() >= 0.01,
            ),
          ),
          chip(LucideIcons.slidersHorizontal, l10n.equalizer, _openEqualizer),
          chip(Icons.graphic_eq_rounded, 'Visualizer', _openVisualizer),
        ],
      ),
    );
  }
}

/// Focused visualizer view opened from Now Playing.
class _NowPlayingVisualizerScreen extends StatelessWidget {
  const _NowPlayingVisualizerScreen({required this.player});

  final PlayerService player;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07080C),
      body: Stack(
        fit: StackFit.expand,
        children: [
          AudioVisualizer(playerService: player),
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x9907080C),
                    Colors.transparent,
                    Colors.transparent,
                    Color(0xCC07080C),
                  ],
                  stops: [0, 0.22, 0.66, 1],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Back to Now Playing',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 30,
                          color: Colors.white,
                        ),
                      ),
                      const Expanded(
                        child: Text(
                          'Visualizer',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: _font,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                  const Spacer(),
                  ValueListenableBuilder<Song?>(
                    valueListenable: player.currentSongNotifier,
                    builder: (context, song, _) {
                      if (song == null) return const SizedBox.shrink();
                      return Column(
                        children: [
                          Text(
                            song.title,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: _font,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            song.artist,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: _font,
                              fontSize: 14,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Previous track',
                        onPressed: () => player.previous(),
                        icon: const Icon(
                          Icons.skip_previous_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 18),
                      ValueListenableBuilder<bool>(
                        valueListenable: player.isPlayingNotifier,
                        builder: (context, playing, _) => FilledButton(
                          onPressed: () => player.togglePlayPause(),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white.withValues(
                              alpha: .16,
                            ),
                            foregroundColor: Colors.white,
                            shape: const CircleBorder(),
                            padding: const EdgeInsets.all(17),
                          ),
                          child: Icon(
                            playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 30,
                          ),
                        ),
                      ),
                      const SizedBox(width: 18),
                      IconButton(
                        tooltip: 'Next track',
                        onPressed: () => player.next(),
                        icon: const Icon(
                          Icons.skip_next_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════ backdrop ═════════════════════════════

/// A continuous ping-pong drift of the actual artwork. The controller belongs
/// to this unkeyed background, so track and palette changes never reset phase.
class _FluidBackdrop extends StatefulWidget {
  const _FluidBackdrop({required this.colors, required this.song});
  final List<Color> colors;
  final Song song;
  @override
  State<_FluidBackdrop> createState() => _FluidBackdropState();
}

class _FluidBackdropState extends State<_FluidBackdrop>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _motion.stop();
    } else if (!_motion.isAnimating) {
      _motion.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: ClipRect(
      child: AnimatedBuilder(
        animation: _motion,
        child: RepaintBoundary(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: 48,
              sigmaY: 48,
              tileMode: TileMode.clamp,
            ),
            child: PlayerArtworkImage(
              song: widget.song,
              radius: 0,
              decodeWidth: 256,
              placeholder: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [widget.colors.first, widget.colors.last],
                  ),
                ),
              ),
            ),
          ),
        ),
        builder: (context, child) {
          final t = Curves.easeInOutSine.transform(_motion.value);
          final size = MediaQuery.sizeOf(context);
          return Transform.translate(
            offset: Offset(
              lerpDouble(-.08, .08, t)! * size.width,
              lerpDouble(.06, -.06, t)! * size.height,
            ),
            child: Transform.rotate(
              angle: lerpDouble(-.08, .08, t)!,
              child: Transform.scale(
                scale: lerpDouble(1.35, 1.5, t),
                child: child,
              ),
            ),
          );
        },
      ),
    ),
  );
}

// ═════════════════════════════ flowing lyrics ═════════════════════════════

class _Word {
  final String text;
  final int startMs;
  final int endMs;
  const _Word(this.text, this.startMs, this.endMs);
}

/// Continuously flowing synced lyrics.
///
/// * One 60 fps ticker drives everything; playback position is extrapolated
///   between the player's position updates so motion never steps.
/// * The scroll offset chases the active line with a critically damped spring
///   (slightly anticipating the next line), so lines glide instead of jumping.
/// * A second smoothed "focus" value drives per-line scale, opacity and blur,
///   so emphasis flows from line to line.
/// * The active line sweeps word by word (real word timing when the lyrics
///   have it, otherwise synthesised from the line's time window).
/// * Drag to browse (auto-follow resumes after 3 s), tap a line to seek.
class _FlowingLyrics extends StatefulWidget {
  final PlayerService player;
  final LyricsData lyrics;

  /// Each line's translation under it, when it has one.
  final bool showTranslation;
  const _FlowingLyrics({
    super.key,
    required this.player,
    required this.lyrics,
    this.showTranslation = false,
  });

  @override
  State<_FlowingLyrics> createState() => _FlowingLyricsState();
}

class _FlowingLyricsState extends State<_FlowingLyrics>
    with SingleTickerProviderStateMixin {
  static const double _gap = 26;
  static const double _anchor = 0.28;
  static const double _introHeight = 44;
  static const TextStyle _base = TextStyle(
    fontFamily: _font,
    fontSize: 31,
    height: 1.2,
    fontWeight: FontWeight.w800,
    color: Colors.white,
  );
  static const double _subGap = 6;
  static const TextStyle _sub = TextStyle(
    fontFamily: _font,
    fontSize: 18,
    height: 1.25,
    fontWeight: FontWeight.w600,
    color: Colors.white,
  );

  late final Ticker _ticker;
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  Duration _lastElapsed = Duration.zero;

  Duration _anchorPos = Duration.zero;
  DateTime _anchorAt = DateTime.now();

  late final List<LyricsLine> _lines = widget.lyrics.lines;
  late final List<int> _ts = [
    for (final l in widget.lyrics.lines) l.timestamp.inMilliseconds,
  ];
  late final List<List<_Word>?> _wordCache = List<List<_Word>?>.filled(
    _lines.length,
    null,
  );

  List<double> _heights = const [];
  List<double> _tops = const [];
  double _w = 0;
  double _h = 0;

  double _offset = 0;
  double _focus = -1;
  bool _needsJump = true;
  bool _following = true;
  Timer? _resume;
  int _active = -1;
  int _posMs = 0;

  @override
  void initState() {
    super.initState();
    _anchorPos = widget.player.positionNotifier.value;
    widget.player.positionNotifier.addListener(_onPosition);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _resume?.cancel();
    widget.player.positionNotifier.removeListener(_onPosition);
    _frame.dispose();
    super.dispose();
  }

  void _onPosition() {
    final v = widget.player.positionNotifier.value;
    // A big jump means the user sought: glide there instead of snapping.
    _anchorPos = v;
    _anchorAt = DateTime.now();
  }

  int _posNowMs() {
    final p = widget.player;
    if (!p.isPlayingNotifier.value) return _anchorPos.inMilliseconds;
    final speed = p.playbackSpeedNotifier.value;
    final elapsed = DateTime.now()
        .difference(_anchorAt)
        .inMilliseconds
        .clamp(0, 600);
    return _anchorPos.inMilliseconds + (elapsed * speed).round();
  }

  int _indexAt(int ms) {
    for (var i = _ts.length - 1; i >= 0; i--) {
      if (_ts[i] <= ms) return i;
    }
    return -1;
  }

  double _centerFor(int a) =>
      a < 0 ? -(_introHeight + _gap) : _tops[a.clamp(0, _tops.length - 1)];

  void _ensureLayout(double w, double h) {
    if ((w - _w).abs() < 0.5 &&
        (h - _h).abs() < 0.5 &&
        _heights.length == _lines.length) {
      return;
    }
    _w = w;
    _h = h;
    final hs = <double>[];
    final tops = <double>[];
    var y = 0.0;
    for (final l in _lines) {
      double lh;
      if (l.text.trim().isEmpty) {
        lh = 30;
      } else {
        final tp = TextPainter(
          text: TextSpan(text: l.text, style: _base),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: math.max(w, 40));
        lh = tp.height;
        if (_translationOf(l) case final sub?) {
          final sp = TextPainter(
            text: TextSpan(text: sub, style: _sub),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: math.max(w, 40));
          lh += _subGap + sp.height;
        }
      }
      tops.add(y);
      hs.add(lh);
      y += lh + _gap;
    }
    _heights = hs;
    _tops = tops;
    _needsJump = true;
  }

  String? _translationOf(LyricsLine line) {
    if (!widget.showTranslation) return null;
    final text = line.translation?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _lastElapsed).inMicroseconds / 1e6)
        .clamp(0.0, 0.05)
        .toDouble();
    _lastElapsed = elapsed;
    if (_heights.isEmpty || _heights.length != _lines.length) return;

    final ms = _posNowMs();
    final a = _indexAt(ms);
    final aScroll = _indexAt(ms + 280);
    final target = _following ? _centerFor(aScroll) : _offset;
    final playing = widget.player.isPlayingNotifier.value;

    if (_needsJump) {
      _offset = _centerFor(aScroll);
      _focus = a.toDouble();
      _needsJump = false;
    } else {
      if (_following) _offset += (target - _offset) * (1 - math.exp(-dt * 7.0));
      _focus += (a - _focus) * (1 - math.exp(-dt * 10.0));
    }

    final settled =
        !playing &&
        (target - _offset).abs() < 0.2 &&
        (a - _focus).abs() < 0.003 &&
        a == _active;
    _posMs = ms;
    _active = a;
    if (!settled) _frame.value++;
  }

  void _pauseFollow() {
    _following = false;
    _resume?.cancel();
    _resume = Timer(const Duration(seconds: 3), () => _following = true);
  }

  List<_Word> _wordsFor(int i) {
    final cached = _wordCache[i];
    if (cached != null) return cached;
    final l = _lines[i];
    List<_Word> out;
    final real = l.words;
    if (real != null && real.isNotEmpty) {
      out = [
        for (final w in real)
          _Word(w.text, w.start.inMilliseconds, w.end.inMilliseconds),
      ];
    } else {
      final start = _ts[i];
      final nextTs = i + 1 < _ts.length ? _ts[i + 1] : start + 4000;
      var window = (nextTs - start).clamp(600, 6000);
      window = (window * 0.92).round();
      final matches = RegExp(r'\S+\s*').allMatches(l.text).toList();
      final weights = [for (final m in matches) m.group(0)!.length + 2];
      final sum = weights.fold<int>(0, (a, b) => a + b);
      var used = 0;
      out = [];
      for (var k = 0; k < matches.length; k++) {
        final s = start + (window * used / math.max(sum, 1)).round();
        used += weights[k];
        final e = start + (window * used / math.max(sum, 1)).round();
        out.add(_Word(matches[k].group(0)!, s, e));
      }
    }
    _wordCache[i] = out;
    return out;
  }

  double _wordAlpha(_Word w, int ms) {
    if (ms >= w.endMs) return 1.0;
    if (ms <= w.startMs) return 0.42;
    final t = ((ms - w.startMs) / math.max(w.endMs - w.startMs, 1)).clamp(
      0.0,
      1.0,
    );
    return 0.42 + 0.58 * Curves.easeOut.transform(t);
  }

  Widget _line(int i) {
    final l = _lines[i];
    if (l.text.trim().isEmpty) return SizedBox(height: _heights[i]);
    final d = (i - _focus).abs();
    final op = d < 1
        ? 1 - 0.66 * d
        : 0.34 - 0.18 * ((d - 1) / 3).clamp(0.0, 1.0);
    final scale = 1 - 0.1 * math.min(d, 1.0);
    final blur = d < 1.0 ? 0.0 : math.min((d - 1) * 0.9, 2.8);

    final TextSpan span;
    if (i == _active) {
      span = TextSpan(
        style: _base,
        children: [
          for (final w in _wordsFor(i))
            TextSpan(
              text: w.text,
              style: TextStyle(
                color: Colors.white.withValues(alpha: _wordAlpha(w, _posMs)),
              ),
            ),
        ],
      );
    } else {
      span = TextSpan(
        text: l.text,
        style: _base.copyWith(color: Colors.white.withValues(alpha: op)),
      );
    }

    final sub = _translationOf(l);
    Widget child = Transform.scale(
      alignment: Alignment.centerLeft,
      scale: scale,
      child: sub == null
          ? Text.rich(span)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(span),
                const SizedBox(height: _subGap),
                Text(
                  sub,
                  style: _sub.copyWith(
                    color: Colors.white.withValues(
                      alpha: (i == _active ? .72 : op * .8),
                    ),
                  ),
                ),
              ],
            ),
    );
    if (blur > 0.3) {
      child = ImageFiltered(
        imageFilter: ImageFilter.blur(
          sigmaX: blur,
          sigmaY: blur,
          tileMode: TileMode.decal,
        ),
        child: child,
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _resume?.cancel();
        _following = true;
        widget.player.seek(Duration(milliseconds: _ts[i]));
      },
      child: child,
    );
  }

  Widget _introDots() {
    final firstMs = _ts.isEmpty ? 0 : _ts.first;
    final p = firstMs <= 0 ? 1.0 : (_posMs / firstMs).clamp(0.0, 1.0);
    final fade = (0 - _focus).clamp(0.0, 1.0).toDouble();
    return Opacity(
      opacity: fade,
      child: SizedBox(
        height: _introHeight,
        child: Row(
          children: [
            for (var k = 0; k < 3; k++)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(
                      alpha: 0.28 + 0.72 * (p * 3 - k).clamp(0.0, 1.0),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        _ensureLayout(c.maxWidth, c.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragStart: (_) => _pauseFollow(),
          onVerticalDragUpdate: (d) {
            _pauseFollow();
            _offset = (_offset - d.delta.dy)
                .clamp(
                  -(_introHeight + _gap + _h * 0.3),
                  math.max(_tops.isEmpty ? 0.0 : _tops.last, 0.0),
                )
                .toDouble();
            _frame.value++;
          },
          child: ClipRect(
            child: ValueListenableBuilder<int>(
              valueListenable: _frame,
              builder: (context, _, __) {
                if (_heights.length != _lines.length) {
                  return const SizedBox.expand();
                }
                final anchorY = _h * _anchor;
                final children = <Widget>[];
                final dotsTop = anchorY - (_introHeight + _gap) - _offset;
                if (dotsTop > -80 && dotsTop < _h) {
                  children.add(
                    Positioned(left: 0, top: dotsTop, child: _introDots()),
                  );
                }
                for (var i = 0; i < _lines.length; i++) {
                  final top = anchorY + _tops[i] - _offset;
                  if (top + _heights[i] < -80 || top > _h + 80) continue;
                  children.add(
                    Positioned(left: 0, right: 0, top: top, child: _line(i)),
                  );
                }
                return Stack(clipBehavior: Clip.hardEdge, children: children);
              },
            ),
          ),
        );
      },
    );
  }
}
