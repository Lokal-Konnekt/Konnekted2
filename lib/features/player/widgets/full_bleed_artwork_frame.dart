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
    this.topInset = 0,
    this.morphEnabled = true,
    this.controlsOpacity = 1,
  });

  final bool canvas;
  final double controlsOpacity;
  final bool morphEnabled;
  final Widget child;
  final double? bannerBottom;
  /// Extra space above still artwork, ignored by Canvas and thumbnails.
  final double topInset;

  @override
  Widget build(BuildContext context) {
    final progress = LokalPlayerMorph.progressOf(context).clamp(0.0, 1.0);
    Widget sleeve(double viewportHeight) => LokalPlayerArtwork(
      enabled: morphEnabled,
      expandedRadius: 0,
      child: CustomPaint(
        foregroundPainter: _ArtworkContrast(
          viewportHeight,
          progress * controlsOpacity,
        ),
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
        // Still covers start below the status bar and fade through the
        // artist row, without painting a dark contrast scrim over the cover.
        final inset = topInset * progress;
        return Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.only(top: inset),
            child: SizedBox(
              width: constraints.maxWidth,
              height: (height - inset).clamp(0.0, constraints.maxHeight),
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

/// Canvas-only contrast: still artwork retains its undimmed original colors.
/// This follows the video during the mini-player morph.
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
                    // Keep Canvas legible under controls without turning
                    // the artwork or album-colored backdrop almost black.
                    const Color(0x7D000000),
                    const Color(0x14000000),
                    const Color(0x20000000),
                    const Color(0x57000000),
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
