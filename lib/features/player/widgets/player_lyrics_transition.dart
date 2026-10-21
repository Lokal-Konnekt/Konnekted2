import 'package:flutter/material.dart';

/// Keeps both views alive, so reversing a transition never resets lyric scroll.
/// Only the visible view ticks after the transition settles.
class PlayerLyricsTransition extends StatefulWidget {
  const PlayerLyricsTransition({
    super.key,
    required this.showLyrics,
    required this.cover,
    required this.lyrics,
  });
  final bool showLyrics;
  final Widget cover, lyrics;
  @override
  State<PlayerLyricsTransition> createState() => _PlayerLyricsTransitionState();
}

class _PlayerLyricsTransitionState extends State<PlayerLyricsTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
    value: widget.showLyrics ? 1 : 0,
  );
  @override
  void didUpdateWidget(PlayerLyricsTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showLyrics != widget.showLyrics) {
      final target = widget.showLyrics ? 1.0 : 0.0;
      if (MediaQuery.disableAnimationsOf(context)) {
        _motion.value = target;
      } else {
        _motion.animateTo(target, curve: Curves.easeInOutCubic);
      }
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _motion,
    builder: (context, _) {
      final t = _motion.value;
      Widget face(Widget child, double opacity, bool active, double offset) =>
          IgnorePointer(
            ignoring: !active,
            child: ExcludeSemantics(
              excluding: !active,
              child: TickerMode(
                enabled: opacity > 0,
                child: Opacity(
                  opacity: opacity,
                  child: Transform.translate(
                    offset: Offset(0, offset),
                    child: RepaintBoundary(child: child),
                  ),
                ),
              ),
            ),
          );
      return Stack(
        fit: StackFit.expand,
        children: [
          face(widget.cover, 1 - t, !widget.showLyrics, -12 * t),
          face(widget.lyrics, t, widget.showLyrics, 12 * (1 - t)),
        ],
      );
    },
  );
}
