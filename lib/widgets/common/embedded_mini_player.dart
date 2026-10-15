import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flick/core/utils/navigation_helper.dart';
import 'package:flick/features/player/widgets/audio_visualizer.dart';
import 'package:flick/providers/providers.dart';
import 'package:flick/providers/mini_player_config_provider.dart';
import 'package:flick/widgets/common/mini_player_bar.dart';

class EmbeddedMiniPlayer extends ConsumerStatefulWidget {
  final bool collapsed;
  final bool separated;

  const EmbeddedMiniPlayer({
    super.key,
    this.collapsed = false,
    this.separated = false,
  });

  @override
  ConsumerState<EmbeddedMiniPlayer> createState() => _EmbeddedMiniPlayerState();
}

class _EmbeddedMiniPlayerState extends ConsumerState<EmbeddedMiniPlayer> {
  bool _showVisualizer = false;
  int _songChangeDirection = 0;
  int _transitionDirection = 0;
  String? _currentSongId;

  void _onHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() <= 300) return;
    if (ref.read(appPreferencesProvider).miniPlayerSwipeAction ==
        'switchSongs') {
      if (velocity < 0) {
        _songChangeDirection = -1;
        ref.read(playerProvider.notifier).next();
      } else {
        _songChangeDirection = 1;
        ref.read(playerProvider.notifier).previous(allowRestart: false);
      }
    } else {
      setState(() => _showVisualizer = !_showVisualizer);
    }
  }

  @override
  Widget build(BuildContext context) {
    final song = ref.watch(currentSongProvider);
    if (song == null) return const SizedBox.shrink();
    if (_currentSongId != song.id) {
      _currentSongId = song.id;
      _transitionDirection = _songChangeDirection;
      _songChangeDirection = 0;
    }
    final prefs = ref.watch(appPreferencesProvider);
    final config = ref.watch(miniPlayerConfigProvider);
    return MiniPlayerBar(
      config: config,
      songId: song.id,
      title: song.title,
      artist: song.artist,
      albumArt: song.albumArt,
      audioSourcePath: song.filePath,
      isPlaying: ref.watch(isPlayingProvider),
      progressOverlay: Consumer(
        builder: (context, ref, _) =>
            MiniPlayerProgress(progress: ref.watch(progressProvider)),
      ),
      separated: widget.separated,
      collapsed: widget.collapsed,
      songChangeDirection: _transitionDirection,
      onHorizontalDragEnd: _onHorizontalDragEnd,
      onOpen: () async {
        FocusScope.of(context).unfocus();
        final result = await NavigationHelper.navigateToFullPlayer(
          context,
          heroTag: 'mini_player_art',
        );
        if (result != null && context.mounted) {
          ref.read(navigationIndexProvider.notifier).setIndex(result);
        }
      },
      onPlayPause: () => ref.read(playerProvider.notifier).togglePlayPause(),
      onPrevious: () {
        _songChangeDirection = 1;
        ref.read(playerProvider.notifier).previous(allowRestart: false);
      },
      onNext: () {
        _songChangeDirection = -1;
        ref.read(playerProvider.notifier).next();
      },
      visualizer: _showVisualizer
          ? SizedBox.expand(
              key: const ValueKey('mini_player_visualizer'),
              child: AudioVisualizer(
                playerService: ref.read(playerServiceProvider),
                animationStyle: prefs.visualizerAnimationStyle,
                frequencyMode: prefs.visualizerFrequencyMode,
                movementMode: prefs.visualizerMovementMode,
                albumColor: ref.watch(albumDominantColorSyncProvider),
                enabled:
                    prefs.visualizerEnabled &&
                    !MediaQuery.disableAnimationsOf(context),
              ),
            )
          : null,
    );
  }
}
