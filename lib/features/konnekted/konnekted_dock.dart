import 'package:flick/models/song.dart';
import 'package:flick/providers/player_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'konnekted_home.dart';
import 'konnekted_style.dart';

enum KonnektedTab {
  listen('Listen', Icons.headphones_rounded),
  explore('Explore', Icons.explore_rounded),
  library('Library', Icons.library_music_rounded),
  settings('Settings', Icons.tune_rounded);

  const KonnektedTab(this.label, this.icon);

  final String label;
  final IconData icon;
}

class KonnektedDock extends StatelessWidget {
  const KonnektedDock({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.miniPlayer,
  });

  final KonnektedTab selected;
  final ValueChanged<KonnektedTab> onSelect;
  final Widget miniPlayer;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    minimum: const EdgeInsets.fromLTRB(12, 6, 12, 8),
    child: Center(
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: KonnektedGlass(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              miniPlayer,
              Padding(
                padding: const EdgeInsets.all(6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final tab in KonnektedTab.values)
                      Expanded(
                        child: _TabButton(
                          tab: tab,
                          selected: tab == selected,
                          onTap: () => onSelect(tab),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final KonnektedTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    label: tab.label,
    onTap: onTap,
    child: Tooltip(
      message: tab.label,
      excludeFromSemantics: true,
      child: InkWell(
        onTap: onTap,
        excludeFromSemantics: true,
        borderRadius: BorderRadius.circular(22),
        child: ExcludeSemantics(
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? KonnektedStyle.coral.withValues(alpha: .13)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  tab.icon,
                  size: 23,
                  color: selected ? KonnektedStyle.coral : KonnektedStyle.muted,
                ),
                const SizedBox(height: 4),
                Text(
                  tab.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? KonnektedStyle.coral
                        : KonnektedStyle.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Only the transport adapter subscribes to playback. Position ticks rebuild a
/// three-pixel progress strip, not the home shelves or the navigator.
class KonnektedMiniPlayer extends ConsumerWidget {
  const KonnektedMiniPlayer({
    super.key,
    required this.onOpen,
    required this.onQueue,
  });

  final VoidCallback onOpen;
  final VoidCallback onQueue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(currentSongProvider);
    if (song == null) return const SizedBox.shrink();
    return KonnektedMiniPlayerContent(
      song: song,
      isPlaying: ref.watch(isPlayingProvider),
      onOpen: onOpen,
      onQueue: onQueue,
      onPlayPause: () => _transport(
        context,
        () => ref.read(playerProvider.notifier).togglePlayPause(),
      ),
      onNext: () =>
          _transport(context, () => ref.read(playerProvider.notifier).next()),
      progress: Consumer(
        builder: (context, ref, _) {
          final value = ref.watch(progressProvider);
          return LinearProgressIndicator(
            value: value.isFinite ? value.clamp(0.0, 1.0) : 0,
            minHeight: 2,
            backgroundColor: Colors.white.withValues(alpha: .06),
            color: KonnektedStyle.coral,
            semanticsLabel: 'Track progress',
          );
        },
      ),
    );
  }

  Future<void> _transport(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Playback couldn’t be changed. Please try again.'),
          ),
        );
      }
    }
  }
}

class KonnektedMiniPlayerContent extends StatelessWidget {
  const KonnektedMiniPlayerContent({
    super.key,
    required this.song,
    required this.isPlaying,
    required this.onOpen,
    required this.onPlayPause,
    required this.onNext,
    required this.onQueue,
    required this.progress,
  });

  final Song song;
  final bool isPlaying;
  final VoidCallback onOpen;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onQueue;
  final Widget progress;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth < 360 ||
              MediaQuery.textScalerOf(context).scale(14) > 23;
          return Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    button: true,
                    label:
                        'Open player for ${song.title} by ${song.artist}. Lyrics and playback controls.',
                    onTap: onOpen,
                    child: InkWell(
                      onTap: onOpen,
                      excludeFromSemantics: true,
                      borderRadius: BorderRadius.circular(16),
                      child: ExcludeSemantics(
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Row(
                            children: [
                              KonnektedArtwork(song: song, size: 44),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      song.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      song.artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: KonnektedStyle.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: isPlaying ? 'Pause' : 'Play',
                  onPressed: onPlayPause,
                  icon: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 30,
                  ),
                ),
                if (!compact)
                  IconButton(
                    tooltip: 'Next track',
                    onPressed: onNext,
                    icon: const Icon(Icons.skip_next_rounded),
                  ),
                IconButton(
                  tooltip: 'Open queue',
                  onPressed: onQueue,
                  icon: const Icon(Icons.queue_music_rounded, size: 23),
                ),
              ],
            ),
          );
        },
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: progress,
      ),
    ],
  );
}
