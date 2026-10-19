import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

/// A full-screen sheet you pull down to close, like Now Playing on iOS
/// (design flow §5.2): it follows the finger 1:1, with 0.5x resistance past
/// 40% of its height, closes past 25% or a 700 dp/s fling, and otherwise
/// springs back with desktop's full-screen spring. What is behind it dims
/// less the further it is pulled. Pulling up instead calls [onPullUp].
class LokalPullToDismiss extends StatefulWidget {
  const LokalPullToDismiss({
    super.key,
    required this.child,
    required this.onDismiss,
    this.onPullUp,
    this.isBlocked,
  });

  final Widget child;
  final VoidCallback onDismiss;
  final VoidCallback? onPullUp;

  /// While this returns true (another gesture owns the finger, such as the
  /// cover carousel) drags are ignored.
  final bool Function()? isBlocked;

  @override
  State<LokalPullToDismiss> createState() => _LokalPullToDismissState();
}

class _LokalPullToDismissState extends State<LokalPullToDismiss>
    with SingleTickerProviderStateMixin {
  late final AnimationController _offset = AnimationController.unbounded(
    vsync: this,
  );
  double _upTravel = 0;

  bool get _blocked => widget.isBlocked?.call() ?? false;

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  void _start(DragStartDetails _) {
    _offset.stop();
    _upTravel = 0;
  }

  void _update(DragUpdateDetails d) {
    if (_blocked) return;
    final height = context.size?.height ?? MediaQuery.sizeOf(context).height;
    final resistance = _offset.value > height * .4 ? .5 : 1.0;
    final next = _offset.value + d.delta.dy * resistance;
    if (next < 0) {
      _upTravel -= d.delta.dy;
      _offset.value = 0;
    } else {
      _offset.value = next;
    }
  }

  void _end(DragEndDetails d) {
    if (_blocked) return;
    final height = context.size?.height ?? MediaQuery.sizeOf(context).height;
    final velocity = d.primaryVelocity ?? 0;
    if (_offset.value <= 0) {
      if (widget.onPullUp != null && (_upTravel > 90 || velocity < -700)) {
        HapticFeedback.selectionClick();
        widget.onPullUp!();
      }
      _upTravel = 0;
      return;
    }
    if (_offset.value > height * .25 || velocity > 700) {
      HapticFeedback.lightImpact();
      widget.onDismiss();
      return;
    }
    _offset.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 300, damping: 30),
        _offset.value,
        0,
        velocity,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _offset,
      builder: (context, child) {
        final height = MediaQuery.sizeOf(context).height;
        final t = (_offset.value / height).clamp(0.0, 1.0);
        return Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: .6 * (1 - t)),
              ),
            ),
            Transform.translate(
              offset: Offset(0, _offset.value),
              child: ClipRRect(
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(36 * (t * 8).clamp(0.0, 1.0)),
                ),
                child: child,
              ),
            ),
          ],
        );
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragStart: _start,
        onVerticalDragUpdate: _update,
        onVerticalDragEnd: _end,
        child: widget.child,
      ),
    );
  }
}
