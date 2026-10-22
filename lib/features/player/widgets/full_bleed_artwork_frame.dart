import 'package:flick/widgets/lokal/lokal_player_artwork.dart';
import 'package:flutter/material.dart';

/// Album sleeves occupy the top banner and dissolve into the player palette.
/// Spotify's portrait Canvas alone keeps the entire viewport.
class FullBleedArtworkFrame extends StatelessWidget {
  const FullBleedArtworkFrame({
    super.key,
    required this.canvas,
    required this.child,
    this.bannerBottom,
    this.morphEnabled = true,
  });

  final bool canvas;
  final bool morphEnabled;
  final Widget child;
  final double? bannerBottom;

  @override
  Widget build(BuildContext context) {
    final progress = LokalPlayerMorph.progressOf(context).clamp(0.0, 1.0);
    Widget sleeve(double viewportHeight) => LokalPlayerArtwork(
      enabled: morphEnabled,
      expandedRadius: 0,
      child: CustomPaint(
        foregroundPainter: _ArtworkContrast(viewportHeight, progress),
        child: child,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (canvas)
          return SizedBox.expand(child: sleeve(constraints.maxHeight));
        // Hero flights pass through the mini-player's square bounds.
        if (constraints.maxHeight <= constraints.maxWidth)
          return sleeve(constraints.maxHeight);
        final height =
            (bannerBottom ??
                    constraints.maxWidth +
                        MediaQuery.paddingOf(context).top +
                        56)
                .clamp(0.0, constraints.maxHeight);
        // The transparent tail reveals the existing palette backdrop.
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: constraints.maxWidth,
            height: height,
            child: LokalPlayerArtwork(
              enabled: morphEnabled,
              expandedRadius: 0,
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (rect) => LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white,
                    Colors.white,
                    Colors.white.withValues(alpha: 1 - progress),
                  ],
                  stops: [0, .68, 1],
                ).createShader(rect),
                child: CustomPaint(
                  foregroundPainter: _ArtworkContrast(
                    constraints.maxHeight,
                    progress,
                  ),
                  child: SizedBox.expand(child: child),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Matches the full player's scrim in viewport coordinates. It travels with
/// the real artwork, fading away at the mini-player endpoint. Painting the
/// scrim behind the sleeve separately keeps the exposed palette consistent.
class _ArtworkContrast extends CustomPainter {
  const _ArtworkContrast(this.viewportHeight, this.progress);
  final double viewportHeight, progress;
  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Rect.fromLTWH(0, 0, size.width, viewportHeight);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors:
              [
                    const Color(0x99000000),
                    const Color(0x26000000),
                    const Color(0xB3000000),
                    const Color(0xF0000000),
                  ]
                  .map((color) => color.withValues(alpha: color.a * progress))
                  .toList(),
          stops: const [0, .28, .66, 1],
        ).createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(_ArtworkContrast oldDelegate) =>
      viewportHeight != oldDelegate.viewportHeight ||
      progress != oldDelegate.progress;
}
