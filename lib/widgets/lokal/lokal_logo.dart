import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flick/core/theme/lokal_appearance.dart';
import 'package:flick/core/theme/lokal_tokens.dart';

/// The Lokal logo, tinted by the accent like desktop's sidebar logo.
///
/// With "Tint App Logo" on, desktop greys the PNG, screens a 135°
/// accent→accentDim gradient over it at 38 %, masked to the logo's own
/// shape, and sits it on a tile with a 10 % accent fill, a 20 % accent
/// border and a soft accent glow. This draws the same recipe, and animates
/// between accents with the theme.
class LokalLogo extends ConsumerWidget {
  const LokalLogo({super.key, this.size = 28, this.tile = true});

  static const asset = 'assets/branding/lokal_icon.png';

  final double size;

  /// Draws desktop's rounded tile behind a tinted logo.
  final bool tile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.lokal;
    final tinted = ref.watch(lokalAppearanceProvider.select((a) => a.tintLogo));
    final radius = BorderRadius.circular(size * .28);

    Widget logo = Image.asset(
      asset,
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
      semanticLabel: 'Lokal',
    );

    if (tinted) {
      logo = _TintedLogo(size: size, accent: t.accent, accentDim: t.accentDim);
    }

    if (!tile || !tinted) {
      return ClipRRect(borderRadius: radius, child: logo);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: t.accentTile,
        borderRadius: radius,
        border: Border.all(color: t.accentTileBorder),
        boxShadow: [BoxShadow(color: t.accentTile, blurRadius: 12)],
      ),
      child: ClipRRect(borderRadius: radius, child: logo),
    );
  }
}

class _TintedLogo extends StatefulWidget {
  const _TintedLogo({
    required this.size,
    required this.accent,
    required this.accentDim,
  });

  final double size;
  final Color accent;
  final Color accentDim;

  @override
  State<_TintedLogo> createState() => _TintedLogoState();
}

class _TintedLogoState extends State<_TintedLogo> {
  ImageStream? _stream;
  ImageInfo? _info;
  late final _listener = ImageStreamListener((info, _) {
    if (mounted) setState(() => _info = info);
  });

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final stream = const AssetImage(LokalLogo.asset)
        .resolve(createLocalImageConfiguration(context));
    if (stream.key != _stream?.key) {
      _stream?.removeListener(_listener);
      _stream = stream..addListener(_listener);
    }
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'Lokal',
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: widget.accent),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
        builder: (context, accent, _) => TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: widget.accentDim),
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOutCubic,
          builder: (context, dim, _) => CustomPaint(
            size: Size.square(widget.size),
            painter: _info == null
                ? null
                : LokalLogoTintPainter(
                    image: _info!.image,
                    accent: accent ?? widget.accent,
                    accentDim: dim ?? widget.accentDim,
                  ),
          ),
        ),
      ),
    );
  }
}

/// Paints desktop's tinted logo: grey logo, then the accent gradient
/// screened over it at [strength], kept inside the logo's alpha.
///
/// Also used to render launcher icons, so it takes a plain [ui.Image].
class LokalLogoTintPainter extends CustomPainter {
  const LokalLogoTintPainter({
    required this.image,
    required this.accent,
    required this.accentDim,
    this.strength = .38,
  });

  final ui.Image image;
  final Color accent;
  final Color accentDim;
  final double strength;

  // grayscale(1) brightness(1.02) contrast(1.06), as on desktop.
  static const List<double> greyMatrix = <double>[
    0.2299,
    0.7733,
    0.0781,
    0,
    -7.65,
    0.2299,
    0.7733,
    0.0781,
    0,
    -7.65,
    0.2299,
    0.7733,
    0.0781,
    0,
    -7.65,
    0,
    0,
    0,
    1,
    0,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final dst = Offset.zero & size;
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );

    // The grey logo, with a layer around it so the screen blend below only
    // reaches the logo, not whatever sits behind the widget.
    canvas.saveLayer(dst, Paint());
    canvas.drawImageRect(
      image,
      src,
      dst,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..colorFilter = const ColorFilter.matrix(greyMatrix),
    );

    // The accent gradient, cut to the logo's alpha, screened on top.
    canvas.saveLayer(
      dst,
      Paint()
        ..blendMode = BlendMode.screen
        ..color = Color.fromRGBO(0, 0, 0, strength),
    );
    canvas.drawImageRect(
      image,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.drawRect(
      dst,
      Paint()
        ..blendMode = BlendMode.srcIn
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent, accentDim],
        ).createShader(dst),
    );
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(LokalLogoTintPainter old) =>
      old.image != image ||
      old.accent != accent ||
      old.accentDim != accentDim ||
      old.strength != strength;
}
