import 'package:flick/l10n/l10n.dart';
import 'package:flutter/material.dart';

import 'package:flick/core/theme/lokal_tokens.dart';

/// The Lokal logo, whose sticker takes the accent colour like desktop's.
///
/// Desktop draws the logo, then the accent through a mask cut to the
/// sticker's shape (`lokal-icon-sticker.png`). This does the same, and
/// cross-fades the sticker when the accent changes.
class LokalLogo extends StatelessWidget {
  const LokalLogo({super.key, this.size = 28});

  static const asset = 'assets/branding/lokal_icon.png';

  /// White, with the sticker's shape in its alpha.
  static const stickerAsset = 'assets/branding/lokal_icon_sticker.png';

  final double size;

  @override
  Widget build(BuildContext context) {
    final accent = context.lokal.accent;
    return Semantics(
      image: true,
      label: lokalText('Lokal'),
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              asset,
              filterQuality: FilterQuality.medium,
              excludeFromSemantics: true,
            ),
            TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: accent),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOutCubic,
              builder: (context, color, _) => Image.asset(
                stickerAsset,
                color: color ?? accent,
                colorBlendMode: BlendMode.srcIn,
                filterQuality: FilterQuality.medium,
                excludeFromSemantics: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
