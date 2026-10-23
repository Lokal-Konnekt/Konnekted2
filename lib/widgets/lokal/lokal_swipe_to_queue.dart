import 'dart:async';

import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/core/utils/app_haptics.dart';
import 'package:flick/l10n/l10n.dart';
import 'package:flick/models/song.dart';
import 'package:flick/providers/player_provider.dart';
import 'package:flick/widgets/lokal/lokal_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Spotify-style swipe to the right on a track row to append it to the queue.
///
/// Keeps the row in place: a drag reveals the queue icon, crossing the
/// threshold gives one selection haptic, and releasing animates the row back.
/// Horizontal gestures compete normally with vertical list scrolling and do
/// not replace the row's tap or long-press actions.
class LokalSwipeToQueue extends StatefulWidget {
  const LokalSwipeToQueue({
    super.key,
    required this.child,
    this.song,
    this.onQueue,
    this.enabled = true,
  }) : assert(song != null || onQueue != null);

  final Widget child;
  final Song? song;

  /// For online search, whose pending tracks require source verification.
  /// Otherwise [song] is appended using the normal player provider.
  final FutureOr<void> Function()? onQueue;
  final bool enabled;

  @override
  State<LokalSwipeToQueue> createState() => _LokalSwipeToQueueState();
}

class _LokalSwipeToQueueState extends State<LokalSwipeToQueue> {
  static const double _threshold = 72;
  static const double _maxTravel = 104;

  double _drag = 0;
  bool _dragging = false;
  bool _thresholdReached = false;
  bool _queueing = false;

  void _start(DragStartDetails details) {
    setState(() => _dragging = true);
  }

  void _update(DragUpdateDetails details) {
    final next = (_drag + details.delta.dx).clamp(0.0, _maxTravel);
    if (next == _drag) return;
    if (next >= _threshold && !_thresholdReached) {
      AppHaptics.selection();
    }
    setState(() {
      _drag = next;
      _thresholdReached = next >= _threshold;
    });
  }

  void _reset() {
    if (!mounted) return;
    setState(() {
      _dragging = false;
      _thresholdReached = false;
      _drag = 0;
    });
  }

  void _end(DragEndDetails details) {
    final shouldQueue =
        _drag >= _threshold ||
        (_drag >= 36 && details.primaryVelocity != null &&
            details.primaryVelocity! > 900);
    _reset();
    if (shouldQueue) unawaited(_queue());
  }

  Future<void> _queue() async {
    if (!widget.enabled || _queueing) return;
    _queueing = true;
    try {
      if (widget.onQueue case final callback?) {
        await callback();
      } else if (widget.song case final song?) {
        await ProviderScope.containerOf(
          context,
          listen: false,
        ).read(playerProvider.notifier).addToQueue(song);
        if (mounted) {
          LokalToast.show(
            context,
            lokalText(
              'Added “{arg0}” to the queue',
              args: {'arg0': song.title},
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        LokalToast.show(context, lokalText('Couldn’t add this song to the queue.'));
      }
    } finally {
      _queueing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.lokal.accent;
    return Semantics(
      customSemanticsActions: widget.enabled
          ? {CustomSemanticsAction(label: l10n.addToQueue2): () => unawaited(_queue())}
          : const {},
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: widget.enabled ? _start : null,
        onHorizontalDragUpdate: widget.enabled ? _update : null,
        onHorizontalDragEnd: widget.enabled ? _end : null,
        onHorizontalDragCancel: widget.enabled ? _reset : null,
        child: ClipRect(
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: _drag),
            duration: _dragging
                ? Duration.zero
                : const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            builder: (context, offset, child) => Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: offset,
                  child: ClipRect(
                    child: ColoredBox(
                      color: accent.withValues(alpha: 0.16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 23),
                          child: Icon(
                            Icons.queue_music_rounded,
                            size: 27,
                            color: accent,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Transform.translate(
                  offset: Offset(offset, 0),
                  child: child,
                ),
              ],
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
