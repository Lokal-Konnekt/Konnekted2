import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

/// Builds Made for you's card at [index].
typedef LokalMadeForYouCardBuilder = Widget Function(
  BuildContext context,
  int index,
);

/// Desktop's Made for you carousel (`src/components/MadeForYou.jsx`): a row
/// that rolls round like the outside of a cylinder. The middle card is the
/// biggest and highest, the others shrink and sink toward the edges, and the
/// row loops. Drag or fling it and it settles on a card; tap a card to play.
///
/// The numbers are desktop's. On a phone, where even desktop's fewest slots
/// would make the cards tiny, the row shows three slots and lets the edge
/// cards run off the faded edges.
class LokalMadeForYouCarousel extends StatefulWidget {
  const LokalMadeForYouCarousel({
    super.key,
    required this.count,
    required this.card,
    required this.onPlay,
    this.semanticLabel,
    this.onLongPress,
  });

  final int count;
  final LokalMadeForYouCardBuilder card;
  final ValueChanged<int> onPlay;
  final ValueChanged<int>? onLongPress;

  /// Read by a screen reader for card [index], e.g. "Play X by Y".
  final String Function(int index)? semanticLabel;

  /// Card width over height.
  static const aspect = 3 / 4;

  /// The middle card's height, when there's room.
  static const maxHeight = 250.0;

  /// Card slots across the row: the most that fit at full size.
  static const slots = [9, 7, 5];

  /// Phone: three slots, cards this much bigger than would fit.
  static const phoneSlots = 3;
  static const phoneBleed = 1.4;

  /// The edge cards' size, from the middle one's.
  static const minScale = .72;

  /// How far the edge cards sink, from the card height.
  static const arc = .27;

  /// Space between cards, from the card width.
  static const gap = .08;

  /// Room above the middle card.
  static const top = 14.0;

  /// Size at [u] cards from the middle: full in the middle, [minScale] from
  /// halfway out.
  static double scaleAt(double u, double half) {
    final a = u.abs() / half;
    return a >= 1
        ? minScale
        : minScale + (1 - minScale) * math.cos(a * math.pi / 2);
  }

  /// Where the card's centre sits, in card widths: the sizes of the cards
  /// before it added up, so smaller cards pack closer and nothing overlaps.
  static double centreAt(double u, double half) {
    final a = u.abs();
    final inner = math.min(a, half);
    final area =
        minScale * inner +
        (1 - minScale) *
            (2 * half / math.pi) *
            math.sin((inner / half) * math.pi / 2) +
        minScale * math.max(0, a - half);
    return u.sign * area;
  }

  /// How far the card sinks, in card heights.
  static double sinkAt(double u, double half) {
    final a = u.abs();
    return arc * (1 - math.cos(math.min(1, a / half) * math.pi / 2)) +
        arc * math.max(0, a - half) * .5;
  }

  /// [value] brought within half a loop of zero.
  static double wrap(double value, int count) =>
      value - (value / count).roundToDouble() * count;

  /// The row's width, in card widths, for [slots] slots.
  static double rowOf(int slots) =>
      (centreAt(slots / 2, slots / 2) * 2 + minScale) * (1 + gap);

  /// Card width and half the slots for a row [width] wide.
  static ({double card, double half}) layoutFor(double width) {
    const full = maxHeight * aspect;
    for (final n in slots) {
      if (width / rowOf(n) >= full) return (card: full, half: n / 2);
    }
    return (
      card: math.min(full, width / rowOf(phoneSlots) * phoneBleed),
      half: phoneSlots / 2,
    );
  }

  /// The stage's height for cards [card] wide: the middle card at the top,
  /// down to the bottom of the lowest whole card.
  static double stageHeight(double card) {
    final height = card / aspect;
    return top + height * (arc + (1 + minScale) / 2) + 14;
  }

  @override
  State<LokalMadeForYouCarousel> createState() =>
      _LokalMadeForYouCarouselState();
}

class _LokalMadeForYouCarouselState extends State<LokalMadeForYouCarousel>
    with SingleTickerProviderStateMixin {
  // Measured in cards: 2.5 is halfway between the third and the fourth.
  late final AnimationController _scroll = AnimationController.unbounded(
    vsync: this,
  )..addListener(_onMove);
  double _step = 120;
  int _centre = 0;

  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 170,
    damping: 26,
  );

  @override
  void didUpdateWidget(LokalMadeForYouCarousel old) {
    super.didUpdateWidget(old);
    if (old.count != widget.count) _scroll.value = 0;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onMove() {
    final count = widget.count;
    if (count == 0) return;
    final centre = _scroll.value.round() % count;
    if (centre != _centre) {
      setState(() => _centre = centre);
      // A detent for every card that passes the middle.
      HapticFeedback.selectionClick();
    }
  }

  void _settle(double target, [double velocity = 0]) {
    final to = target.roundToDouble();
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.value = to;
      return;
    }
    _scroll.animateWith(SpringSimulation(_spring, _scroll.value, to, velocity));
  }

  void _by(int cards) => _settle(_scroll.value.roundToDouble() + cards);

  void _onDragUpdate(DragUpdateDetails details) {
    _scroll.value -= details.delta.dx / _step;
  }

  void _onDragEnd(DragEndDetails details) {
    // A flick keeps rolling a little before it settles.
    final velocity = -details.velocity.pixelsPerSecond.dx / _step;
    _settle(_scroll.value + (velocity * .25).clamp(-4.0, 4.0), velocity);
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.count;
    if (count == 0) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final (:card, :half) = LokalMadeForYouCarousel.layoutFor(width);
        final height = card / LokalMadeForYouCarousel.aspect;
        _step = card * (1 + LokalMadeForYouCarousel.gap);
        return Semantics(
          container: true,
          label: 'Made for you',
          value: widget.semanticLabel?.call(_centre),
          increasedValue: widget.semanticLabel?.call((_centre + 1) % count),
          decreasedValue: widget.semanticLabel?.call((_centre - 1) % count),
          onIncrease: () => _by(1),
          onDecrease: () => _by(-1),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragDown: (_) => _scroll.stop(),
            onHorizontalDragUpdate: _onDragUpdate,
            onHorizontalDragEnd: _onDragEnd,
            onHorizontalDragCancel: () => _settle(_scroll.value),
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              // The row fades out at the screen's edges.
              shaderCallback: (bounds) => const LinearGradient(
                colors: [
                  Colors.transparent,
                  Colors.black,
                  Colors.black,
                  Colors.transparent,
                ],
                stops: [0, .05, .95, 1],
              ).createShader(bounds),
              child: SizedBox(
                width: width,
                height: LokalMadeForYouCarousel.stageHeight(card),
                child: AnimatedBuilder(
                  animation: _scroll,
                  builder: (context, _) {
                    final s = _scroll.value;
                    final order = [
                      for (var i = 0; i < count; i++)
                        (
                          index: i,
                          offset: LokalMadeForYouCarousel.wrap(i - s, count),
                        ),
                    ]..removeWhere((c) => c.offset.abs() > half + 1);
                    // The middle card on top.
                    order.sort(
                      (a, b) => b.offset.abs().compareTo(a.offset.abs()),
                    );
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (final c in order)
                          _placed(c.index, c.offset, card, height, half, width),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _placed(
    int index,
    double offset,
    double card,
    double height,
    double half,
    double width,
  ) {
    final x =
        LokalMadeForYouCarousel.centreAt(offset, half) *
        card *
        (1 + LokalMadeForYouCarousel.gap);
    final y = LokalMadeForYouCarousel.sinkAt(offset, half) * height;
    return Positioned(
      key: ValueKey(index),
      left: width / 2 - card / 2 + x,
      top: LokalMadeForYouCarousel.top + y,
      width: card,
      height: height,
      child: Transform.scale(
        scale: LokalMadeForYouCarousel.scaleAt(offset, half),
        child: Semantics(
          button: true,
          label: widget.semanticLabel?.call(index),
          excludeSemantics: true,
          onTap: () => widget.onPlay(index),
          child: GestureDetector(
            onTap: () => widget.onPlay(index),
            onLongPress: widget.onLongPress == null
                ? null
                : () => widget.onLongPress!(index),
            child: widget.card(context, index),
          ),
        ),
      ),
    );
  }
}
