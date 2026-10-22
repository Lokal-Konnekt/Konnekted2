import 'package:flutter/material.dart';

/// Album sleeves occupy the top banner and dissolve into the player palette.
/// Spotify's portrait Canvas alone keeps the entire viewport.
class FullBleedArtworkFrame extends StatelessWidget {
  const FullBleedArtworkFrame({
    super.key,
    required this.canvas,
    required this.child,
    this.bannerBottom,
  });

  final bool canvas;
  final Widget child;
  final double? bannerBottom;

  @override
  Widget build(BuildContext context) {
    if (canvas) return SizedBox.expand(child: child);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Hero flights pass through the mini-player's square bounds.
        if (constraints.maxHeight <= constraints.maxWidth) return child;
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
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.white, Colors.white, Colors.transparent],
                stops: [0, .68, 1],
              ).createShader(rect),
              child: SizedBox.expand(child: child),
            ),
          ),
        );
      },
    );
  }
}
