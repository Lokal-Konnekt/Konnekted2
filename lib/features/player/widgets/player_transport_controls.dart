import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flick/l10n/l10n.dart';

/// The icon morph, button widths and pressed feedback can reverse independently.
/// Panel resizing reads the same progress as the moving artwork.
class PlayerTransportControls extends StatefulWidget {
  const PlayerTransportControls({
    super.key,
    required this.playing,
    required this.compact,
    required this.lyricsProgress,
    required this.accent,
    required this.onAccent,
    required this.onPrevious,
    required this.onNext,
    required this.onPlayPause,
  });
  final bool playing, compact;
  final double lyricsProgress;
  final Color accent, onAccent;
  final VoidCallback onPrevious, onNext, onPlayPause;
  @override
  State<PlayerTransportControls> createState() =>
      _PlayerTransportControlsState();
}

class _PlayerTransportControlsState extends State<PlayerTransportControls>
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
      final l = widget.lyricsProgress.clamp(0.0, 1.0);
      final height = lerpDouble(
        widget.compact ? 66 : 82,
        widget.compact ? 48 : 52,
        l,
      )!;
      final radius = lerpDouble(28, 24, l)!;
      final primaryShare = lerpDouble(
        lerpDouble(.46, .42, _icon.value),
        .36,
        l,
      )!;
      return SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, c) {
            final available = c.maxWidth - 20;
            final primary = available * primaryShare;
            Widget skip(IconData icon, VoidCallback onTap, String label) =>
                Expanded(
                  child: _TransportButton(
                    color: Colors.white.withValues(alpha: .13),
                    radius: radius,
                    onTap: onTap,
                    label: label,
                    child: Icon(
                      icon,
                      size: lerpDouble(32, 27, l),
                      color: Colors.white,
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
                const SizedBox(width: 10),
                SizedBox(
                  width: primary,
                  child: _TransportButton(
                    key: const ValueKey('player-play-button'),
                    color: widget.accent,
                    radius: radius,
                    onTap: widget.onPlayPause,
                    label: widget.playing ? l10n.pause : l10n.play,
                    child: AnimatedIcon(
                      icon: AnimatedIcons.play_pause,
                      progress: _icon,
                      size: lerpDouble(40, 32, l),
                      color: widget.onAccent,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
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
