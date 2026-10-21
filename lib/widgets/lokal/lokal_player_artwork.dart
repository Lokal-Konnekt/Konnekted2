import 'dart:ui' show lerpDouble;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Paints the player's real cover above the moving sheet's clips. Its layout
/// stays in the full player, while its paint bounds follow the same progress
/// as the sheet, including a finger-held drag and its settling spring.
class LokalPlayerMorph extends StatelessWidget {
  const LokalPlayerMorph({
    super.key,
    required this.progress,
    required this.sheetOffset,
    required this.sourceArtwork,
    required this.child,
  });

  final double progress;
  final double sheetOffset;
  final Rect? Function() sourceArtwork;
  final Widget child;

  static bool activeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_MorphScope>() != null;

  @override
  Widget build(BuildContext context) => _MorphScope(
    child: _ArtworkPortal(
      progress: progress,
      sheetOffset: sheetOffset,
      sourceArtwork: sourceArtwork,
      child: child,
    ),
  );
}

class _MorphScope extends InheritedWidget {
  const _MorphScope({required super.child});
  @override
  bool updateShouldNotify(_MorphScope oldWidget) => false;
}

/// Wraps the whole cover, including its like animation. Ancestor carousel and
/// sheet clipping cannot split the cover's trip between the two real layouts.
class LokalPlayerArtwork extends StatelessWidget {
  const LokalPlayerArtwork({
    super.key,
    required this.child,
    this.enabled = true,
  });
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) => _ArtworkAnchor(
    enabled: enabled && LokalPlayerMorph.activeOf(context),
    child: child,
  );
}

class _ArtworkPortal extends SingleChildRenderObjectWidget {
  const _ArtworkPortal({
    required this.progress,
    required this.sheetOffset,
    required this.sourceArtwork,
    required super.child,
  });
  final double progress;
  final double sheetOffset;
  final Rect? Function() sourceArtwork;

  @override
  _RenderArtworkPortal createRenderObject(BuildContext context) =>
      _RenderArtworkPortal(progress, sheetOffset, sourceArtwork);

  @override
  void updateRenderObject(BuildContext context, _RenderArtworkPortal object) {
    object.update(progress, sheetOffset, sourceArtwork);
  }
}

class _RenderArtworkPortal extends RenderProxyBox {
  _RenderArtworkPortal(this._progress, this._sheetOffset, this._sourceArtwork);

  double _progress;
  double _sheetOffset;
  Rect? Function() _sourceArtwork;
  _RenderArtworkAnchor? artwork;

  bool get lifting => _progress < 1 && _sourceArtwork() != null;

  void update(double progress, double offset, Rect? Function() source) {
    _progress = progress;
    _sheetOffset = offset;
    _sourceArtwork = source;
    // Repaint the anchor's original layer as well: a cached carousel layer
    // must not retain a second copy when a closing drag starts.
    artwork?.markNeedsPaint();
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    final anchor = artwork, source = _sourceArtwork();
    if (!lifting ||
        anchor == null ||
        !anchor.attached ||
        !anchor.hasSize ||
        anchor.child == null ||
        source == null ||
        anchor.size.isEmpty)
      return;
    final natural = MatrixUtils.transformRect(
      anchor.getTransformTo(this),
      Offset.zero & anchor.size,
    );
    final origin = localToGlobal(Offset.zero);
    final from = source.shift(-origin);
    final to = natural.shift(Offset(0, -_sheetOffset));
    final rect = Rect.lerp(from, to, _progress.clamp(0.0, 1.0))!;
    final scaleX = rect.width / anchor.size.width;
    final scaleY = rect.height / anchor.size.height;
    final radius = lerpDouble(source.shortestSide / 2, 28, _progress)!;
    final transform = Matrix4.identity()
      ..translateByDouble(rect.left, rect.top, 0, 1)
      ..scaleByDouble(scaleX, scaleY, 1, 1);
    context.pushTransform(needsCompositing, offset, transform, (context, at) {
      context.pushClipRRect(
        needsCompositing,
        at,
        Offset.zero & anchor.size,
        RRect.fromRectAndCorners(
          Offset.zero & anchor.size,
          topLeft: Radius.elliptical(radius / scaleX, radius / scaleY),
          topRight: Radius.elliptical(radius / scaleX, radius / scaleY),
          bottomLeft: Radius.elliptical(radius / scaleX, radius / scaleY),
          bottomRight: Radius.elliptical(radius / scaleX, radius / scaleY),
        ),
        (context, at) => context.paintChild(anchor.child!, at),
      );
    });
  }
}

class _ArtworkAnchor extends SingleChildRenderObjectWidget {
  const _ArtworkAnchor({required this.enabled, required super.child});
  final bool enabled;
  @override
  _RenderArtworkAnchor createRenderObject(BuildContext context) =>
      _RenderArtworkAnchor(enabled);

  @override
  void updateRenderObject(BuildContext context, _RenderArtworkAnchor object) {
    object.enabled = enabled;
  }
}

class _RenderArtworkAnchor extends RenderProxyBox {
  _RenderArtworkAnchor(this._enabled);
  bool _enabled;
  _RenderArtworkPortal? _portal;

  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    _register();
    markNeedsPaint();
  }

  // Register before painting: the carousel's retained repaint layers can skip
  // our paint entirely when the player moves from the preview into its route.
  void _register() {
    RenderObject? ancestor = _enabled ? parent : null;
    while (ancestor != null && ancestor is! _RenderArtworkPortal) {
      ancestor = ancestor.parent;
    }
    final next = ancestor is _RenderArtworkPortal ? ancestor : null;
    if (identical(next, _portal)) return;
    _unregister();
    _portal = next;
    if (next != null) {
      next.artwork = this;
      next.markNeedsPaint();
    }
    markNeedsPaint();
  }

  void _unregister() {
    final portal = _portal;
    _portal = null;
    if (portal != null && identical(portal.artwork, this)) {
      portal.artwork = null;
      portal.markNeedsPaint();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _register();
  }

  @override
  void performLayout() {
    super.performLayout();
    _register();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final portal = _portal;
    if (portal != null && identical(portal.artwork, this) && portal.lifting) {
      return;
    }
    super.paint(context, offset);
  }

  @override
  void detach() {
    _unregister();
    super.detach();
  }
}
