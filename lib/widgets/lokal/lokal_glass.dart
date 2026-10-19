import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flick/core/theme/lokal_appearance.dart';
import 'package:flick/core/theme/lokal_tokens.dart';

/// How much a [LokalGlass] hides what is behind it.
enum LokalGlassThickness {
  /// Controls floating over artwork or content: top-bar circles, chips,
  /// segmented controls, Now Playing transport.
  thin(sigma: 14, darkAlpha: .14, lightAlpha: .45),

  /// Floating chrome: tab capsule, search circle, mini player, toasts.
  regular(sigma: 18, darkAlpha: .50, lightAlpha: .62),

  /// Sheets and menus.
  sheet(sigma: 24, darkAlpha: .72, lightAlpha: .78);

  const LokalGlassThickness({
    required this.sigma,
    required this.darkAlpha,
    required this.lightAlpha,
  });

  final double sigma;
  final double darkAlpha;
  final double lightAlpha;
}

/// Lokal's glass material (design spec §4).
///
/// Backdrop blur with boosted saturation so colour glows through, a tint
/// from the theme surface, a 1 px specular rim lit from the top-left and a
/// soft inner highlight. In performance mode it becomes its solid tint,
/// like desktop's Performance Mode removing every backdrop-filter.
///
/// Inside a [BackdropGroup], pass [grouped] so neighbouring glass (tab
/// capsule, search circle, mini player) shares one backdrop capture.
class LokalGlass extends ConsumerWidget {
  const LokalGlass({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.thickness = LokalGlassThickness.regular,
    this.tint,
    this.padding,
    this.shadow = true,
    this.grouped = false,
  });

  /// A fully rounded capsule or circle (`StadiumBorder`-like radius).
  const LokalGlass.capsule({
    super.key,
    required this.child,
    this.thickness = LokalGlassThickness.regular,
    this.tint,
    this.padding,
    this.shadow = true,
    this.grouped = false,
  }) : borderRadius = const BorderRadius.all(Radius.circular(999));

  final Widget child;
  final BorderRadius borderRadius;
  final LokalGlassThickness thickness;

  /// Replaces the theme tint, e.g. the accent for a selected lens.
  final Color? tint;
  final EdgeInsetsGeometry? padding;
  final bool shadow;
  final bool grouped;

  static const _saturation = 1.6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.lokal;
    final solid = ref.watch(
      lokalAppearanceProvider.select((a) => a.performanceMode),
    );
    final light = t.isLight;
    final base = tint ?? (light ? Colors.white : t.surface);
    final alpha = light ? thickness.lightAlpha : thickness.darkAlpha;
    // Solid glass gets 20 % more opacity so text keeps its contrast without
    // the blur behind it.
    final fill = base.withValues(
      alpha: solid ? (alpha + .2).clamp(0.0, .96) : alpha,
    );

    Widget surface = DecoratedBox(
      decoration: BoxDecoration(color: fill, borderRadius: borderRadius),
      position: DecorationPosition.background,
      child: CustomPaint(
        foregroundPainter: _GlassLightPainter(
          borderRadius: borderRadius,
          light: light,
          strength: solid ? .6 : 1,
        ),
        child: padding == null
            ? child
            : Padding(padding: padding!, child: child),
      ),
    );

    if (!solid) {
      final filter = ui.ImageFilter.compose(
        outer: const ColorFilter.matrix(_saturationMatrix),
        inner: ui.ImageFilter.blur(
          sigmaX: thickness.sigma,
          sigmaY: thickness.sigma,
          tileMode: TileMode.mirror,
        ),
      );
      surface = grouped
          ? BackdropFilter.grouped(filter: filter, child: surface)
          : BackdropFilter(filter: filter, child: surface);
    }

    surface = ClipRRect(borderRadius: borderRadius, child: surface);

    if (!shadow) return RepaintBoundary(child: surface);
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: light ? .12 : .38),
              blurRadius: light ? 24 : 34,
              offset: Offset(0, light ? 8 : 12),
            ),
          ],
        ),
        child: surface,
      ),
    );
  }

  // Saturation 1.6, plus a 4 % brightness lift, applied to what the glass
  // samples, so colours behind it glow instead of going muddy.
  static const List<double> _saturationMatrix = <double>[
    0.2126 * (1 - _saturation) + _saturation,
    0.7152 * (1 - _saturation),
    0.0722 * (1 - _saturation),
    0,
    10,
    0.2126 * (1 - _saturation),
    0.7152 * (1 - _saturation) + _saturation,
    0.0722 * (1 - _saturation),
    0,
    10,
    0.2126 * (1 - _saturation),
    0.7152 * (1 - _saturation),
    0.0722 * (1 - _saturation) + _saturation,
    0,
    10,
    0,
    0,
    0,
    1,
    0,
  ];
}

/// The rim and inner highlight that make glass read as a solid object.
class _GlassLightPainter extends CustomPainter {
  const _GlassLightPainter({
    required this.borderRadius,
    required this.light,
    required this.strength,
  });

  final BorderRadius borderRadius;
  final bool light;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect);

    // Soft sheen across the top-left third.
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: (light ? .30 : .16) * strength),
            Colors.white.withValues(alpha: .03 * strength),
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: .05 * strength),
          ],
          stops: const [0, .38, .6, 1],
        ).createShader(rect),
    );

    // 1 px specular rim, brightest where the light hits.
    canvas.drawRRect(
      rrect.deflate(.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: light
              ? [
                  Colors.white.withValues(alpha: .9 * strength),
                  Colors.black.withValues(alpha: .06 * strength),
                ]
              : [
                  Colors.white.withValues(alpha: .30 * strength),
                  Colors.white.withValues(alpha: .05 * strength),
                ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_GlassLightPainter old) =>
      old.borderRadius != borderRadius ||
      old.light != light ||
      old.strength != strength;
}

/// A glass control that swells under the finger, like iOS 26 glass buttons.
class LokalGlassButton extends StatefulWidget {
  const LokalGlassButton({
    super.key,
    required this.onPressed,
    required this.child,
    required this.semanticLabel,
    this.size = 44,
    this.thickness = LokalGlassThickness.thin,
    this.tint,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final String semanticLabel;
  final double size;
  final LokalGlassThickness thickness;
  final Color? tint;

  @override
  State<LokalGlassButton> createState() => _LokalGlassButtonState();
}

class _LokalGlassButtonState extends State<LokalGlassButton> {
  bool _pressed = false;

  void _set(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _pressed && !reduceMotion ? 1.06 : 1,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          child: SizedBox.square(
            dimension: widget.size,
            child: LokalGlass.capsule(
              thickness: widget.thickness,
              tint: widget.tint,
              shadow: false,
              child: Center(child: widget.child),
            ),
          ),
        ),
      ),
    );
  }
}
