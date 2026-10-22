import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// A single artwork and title travel between three poses: large cover,
/// queue header, and the compact now-playing row beneath lyrics.
class PlayerPanelStage extends StatelessWidget {
  const PlayerPanelStage({
    super.key,
    required this.queueProgress,
    required this.lyricsProgress,
    required this.queueOpen,
    required this.lyricsOpen,
    required this.artwork,
    required this.info,
    required this.queue,
    required this.lyrics,
    this.artGap = 16,
    this.onQueueHeaderTap,
    this.onQueueHeaderDrag,
    this.onQueueHeaderRelease,
  });
  final Animation<double> queueProgress, lyricsProgress;
  final bool queueOpen, lyricsOpen;
  final Widget Function(BuildContext, double, double) artwork;
  final Widget Function(BuildContext, double) info;
  final Widget queue, lyrics;
  final double artGap;
  final VoidCallback? onQueueHeaderTap;
  final ValueChanged<double>? onQueueHeaderDrag, onQueueHeaderRelease;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([queueProgress, lyricsProgress]),
    builder: (context, _) {
      final l = lyricsProgress.value.clamp(0.0, 1.0);
      final q = queueProgress.value.clamp(0.0, 1.0) * (1 - l);
      final compact = q + l;
      Widget panel(Widget child, double opacity, bool active) => IgnorePointer(
        ignoring: !active,
        child: ExcludeSemantics(
          excluding: !active,
          child: TickerMode(
            enabled: opacity > 0,
            child: Opacity(
              opacity: opacity,
              child: RepaintBoundary(child: child),
            ),
          ),
        ),
      );
      return ClipRect(
        child: CustomMultiChildLayout(
          delegate: _PanelLayout(queue: q, lyrics: l, artGap: artGap),
          children: [
            LayoutId(
              id: _Part.queue,
              child: panel(
                queue,
                Curves.easeOut.transform(((q - .15) / .85).clamp(0.0, 1.0)),
                queueOpen && !lyricsOpen,
              ),
            ),
            LayoutId(
              id: _Part.lyrics,
              child: panel(
                lyrics,
                Curves.easeOut.transform(((l - .12) / .88).clamp(0.0, 1.0)),
                lyricsOpen,
              ),
            ),
            LayoutId(
              id: _Part.art,
              child: LayoutBuilder(
                builder: (context, c) => RepaintBoundary(
                  child: artwork(context, c.maxWidth, compact),
                ),
              ),
            ),
            LayoutId(id: _Part.info, child: info(context, compact)),
            LayoutId(
              id: _Part.header,
              child: IgnorePointer(
                ignoring: !queueOpen || lyricsOpen,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onQueueHeaderTap,
                  onVerticalDragUpdate: (d) =>
                      onQueueHeaderDrag?.call(-d.delta.dy),
                  onVerticalDragEnd: (d) =>
                      onQueueHeaderRelease?.call(-(d.primaryVelocity ?? 0)),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

enum _Part { art, info, queue, lyrics, header }

class _PanelLayout extends MultiChildLayoutDelegate {
  _PanelLayout({
    required this.queue,
    required this.lyrics,
    required this.artGap,
  });
  final double queue, lyrics, artGap;
  static const thumb = 52.0;
  @override
  void performLayout(Size size) {
    final c = (queue + lyrics).clamp(0.0, 1.0), full = 1 - c;
    final w = size.width, h = size.height;
    final left = (thumb + 12) * c;
    final info = layoutChild(
      _Part.info,
      BoxConstraints(
        minWidth: math.max(0, w - left),
        maxWidth: math.max(0, w - left),
        maxHeight: h,
      ),
    );
    final room = math.max(0.0, h - artGap - info.height - 6);
    final fullSide = math.min(w, room);
    final top = (room - fullSide) / 2;
    final headerHeight = math.max(math.min(thumb, h), info.height);
    final artCentering = (headerHeight - math.min(thumb, h)) / 2;
    final lyricsTop = math.max(0.0, h - headerHeight - 8);
    final side = lerpDouble(fullSide, math.min(thumb, h), c)!;
    layoutChild(_Part.art, BoxConstraints.tightFor(width: side, height: side));
    positionChild(
      _Part.art,
      Offset(
        (w - fullSide) / 2 * full,
        top * full + artCentering * c + lyricsTop * lyrics,
      ),
    );
    positionChild(
      _Part.info,
      Offset(
        left,
        (top + fullSide + artGap) * full +
            (headerHeight - info.height) / 2 * c +
            lyricsTop * lyrics,
      ),
    );
    final queueTop = math.min(h, headerHeight + 12);
    layoutChild(
      _Part.queue,
      BoxConstraints.tightFor(width: w, height: math.max(0, h - queueTop)),
    );
    positionChild(_Part.queue, Offset(0, queueTop + (1 - queue) * 22));
    layoutChild(
      _Part.lyrics,
      BoxConstraints.tightFor(width: w, height: math.max(0, lyricsTop - 10)),
    );
    positionChild(_Part.lyrics, Offset(0, (1 - lyrics) * 18));
    layoutChild(
      _Part.header,
      BoxConstraints.tightFor(width: w, height: queueTop),
    );
    positionChild(_Part.header, Offset.zero);
  }

  @override
  bool shouldRelayout(_PanelLayout old) =>
      old.queue != queue || old.lyrics != lyrics || old.artGap != artGap;
}
