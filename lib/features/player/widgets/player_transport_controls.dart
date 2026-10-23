import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flick/core/theme/lokal_appearance.dart';
import 'package:flick/l10n/l10n.dart';
import 'full_player_visuals.dart';

/// The icon morph, button widths and pressed feedback can reverse independently.
/// Panel resizing reads the same progress as the moving artwork.
class PlayerTransportControls extends ConsumerStatefulWidget {
  const PlayerTransportControls({
    super.key,
    required this.playing,
    required this.compact,
    this.tallerButtons = false,
    required this.lyricsProgress,
    required this.accent,
    required this.onAccent,
    required this.onPrevious,
    required this.onNext,
    required this.onPlayPause,
  });
  final bool playing, compact;
  /// Taller pads for the modern full player; lyrics pose stays compact.
  final bool tallerButtons;
  final double lyricsProgress;
  final Color accent, onAccent;
  final VoidCallback onPrevious, onNext, onPlayPause;
  @override
  ConsumerState<PlayerTransportControls> createState() =>
      _PlayerTransportControlsState();
}

class _PlayerTransportControlsState extends ConsumerState<PlayerTransportControls>
    with SingleTickerProviderStateMixin {
  late final AnimationController _icon = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: widget.playing ? 1 : 0,
  );
  @override
  void didUpdateWidget(PlayerTransportControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playing != widget.playing) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _icon.value = widget.playing ? 1 : 0;
      } else {
        _icon.animateTo(widget.playing ? 1 : 0, curve: Curves.easeInOutCubic);
      }
    }
  }

  @override
  void dispose() {
    _icon.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _icon,
    builder: (context, _) {
      final unboxed = ref.watch(lokalAppearanceProvider.select((a) => a.unboxedPlayerControls));
      final l = widget.lyricsProgress.clamp(0.0, 1.0);
      final height = lerpDouble(
        widget.tallerButtons
            ? (widget.compact ? 74.0 : 94.0)
            : (widget.compact ? 66.0 : 82.0),
        widget.compact ? 48 : 52,
        l,
      )!;
      final radius = lerpDouble(26, 23, l)!;
      // Balanced side buttons and a narrower central play pad.
      // Playback changes the icon, not the widths of the three buttons.
      final primaryShare = .36;
      return SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, c) {
            final available = c.maxWidth - 16;
            final primary = available * primaryShare;
            Widget skip(IconData icon, VoidCallback onTap, String label) =>
                Expanded(
                  child: _TransportButton(
                    color: unboxed ? Colors.transparent : FullPlayerVisuals.surface,
                    radius: radius,
                    onTap: onTap,
                    label: label,
                    child: Icon(
                      unboxed ? (icon == Icons.skip_previous_rounded ? Icons.skip_previous : Icons.skip_next) : icon,
                      size: unboxed ? lerpDouble(43, 34, l) : lerpDouble(29, 26, l),
                      color: FullPlayerVisuals.primaryText,
                    ),
                  ),
                );
            return Row(
              children: [
                skip(
                  Icons.skip_previous_rounded,
                  widget.onPrevious,
                  l10n.previousSong,
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: primary,
                  child: _TransportButton(
                    key: const ValueKey('player-play-button'),
                    color: unboxed ? Colors.transparent : widget.accent,
                    radius: radius,
                    onTap: widget.onPlayPause,
                    label: widget.playing ? l10n.pause : l10n.play,
                    child: unboxed
                        ? Icon(
                            widget.playing ? Icons.pause : Icons.play_arrow,
                            size: lerpDouble(62, 44, l),
                            color: FullPlayerVisuals.primaryText,
                          )
                        : AnimatedIcon(
                            icon: AnimatedIcons.play_pause,
                            progress: _icon,
                            size: lerpDouble(33, 29, l),
                            color: widget.onAccent,
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                skip(Icons.skip_next_rounded, widget.onNext, l10n.nextSong),
              ],
            );
          },
        ),
      );
    },
  );
}

class _TransportButton extends StatefulWidget {
  const _TransportButton({
    super.key,
    required this.color,
    required this.radius,
    required this.onTap,
    required this.label,
    required this.child,
  });
  final Color color;
  final double radius;
  final VoidCallback onTap;
  final String label;
  final Widget child;
  @override
  State<_TransportButton> createState() => _TransportButtonState();
}

class _TransportButtonState extends State<_TransportButton> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: widget.label,
    child: Tooltip(
      message: widget.label,
      child: AnimatedScale(
        scale: _pressed ? .94 : 1,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : Duration(milliseconds: _pressed ? 90 : 220),
        curve: _pressed ? Curves.easeOutCubic : Curves.easeOutBack,
        child: Material(
          color: widget.color,
          borderRadius: BorderRadius.circular(widget.radius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onHighlightChanged: (value) => setState(() => _pressed = value),
            onTap: widget.onTap,
            child: Center(child: widget.child),
          ),
        ),
      ),
    ),
  );
}
