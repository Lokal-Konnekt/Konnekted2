import 'package:flick/core/theme/lokal_performance_scope.dart';
import 'package:flick/l10n/l10n.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/data/repositories/song_repository.dart';
import 'package:flick/models/song.dart';

/// Builds one square cover for [album].
typedef LokalCoverBuilder = Widget Function(AlbumGroup album);

/// iPod-style Cover Flow (design spec §7.1).
///
/// The facing album sits flat and forward; its neighbours hinge around their
/// inside edge so the outside edge comes towards the viewer, like iTunes.
/// Covers stack in calibrated perspective behind the facing square. Drag to spin with momentum,
/// settle on the nearest album with a spring, and feel a tick for every
/// album that passes. With [onSelect], one tap on any cover brings it forward
/// and selects it (Home plays it straight away); long-press the facing cover
/// to flip it over to its track list. Without [onSelect], a tap brings a side
/// cover forward and flips the facing one.
class LokalCoverFlow extends StatefulWidget {
  // Public, production-owned geometry for the desktop/iTunes calibration.
  // Tests exercise THESE equations, rather than local copies that could drift.
  static const double _firstCenter = .91;
  static const double _farStep = .18;
  static const double _sideDepth = .60;

  @visibleForTesting
  static double centerDistance(double distance) {
    final a = distance.abs();
    if (a >= 1) return _firstCenter + (a - 1) * _farStep;
    return .90 * a + .75 * a * a - .74 * a * a * a;
  }

  @visibleForTesting
  static double depthDistance(double distance) {
    final a = distance.abs();
    if (a >= 1) return _sideDepth;
    return _sideDepth * a * a * (3 - 2 * a);
  }

  const LokalCoverFlow({
    super.key,
    required this.albums,
    required this.cover,
    required this.onPlay,
    this.initialIndex = 0,
    this.onIndexChanged,
    this.onSelect,
  });

  final List<AlbumGroup> albums;
  final LokalCoverBuilder cover;

  /// Plays [song] with the album as the queue.
  final void Function(Song song, List<Song> album) onPlay;
  final int initialIndex;
  final ValueChanged<int>? onIndexChanged;

  /// Called once when a cover is tapped, after it starts moving forward.
  final ValueChanged<int>? onSelect;

  @override
  State<LokalCoverFlow> createState() => _LokalCoverFlowState();
}

class _LokalCoverFlowState extends State<LokalCoverFlow>
    with TickerProviderStateMixin {
  // Position is measured in albums: 2.5 is halfway between the third and
  // the fourth.
  late final AnimationController _position = AnimationController.unbounded(
    vsync: this,
    value: widget.initialIndex.toDouble(),
  )..addListener(_onMove);
  late final AnimationController _flip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );
  late int _index = widget.initialIndex;
  late final Listenable _animation = Listenable.merge([_position, _flip]);
  final _faces = <String, Widget>{};
  double? _faceSize;
  bool _reduceMotion = false;
  bool _performance = false;
  bool _disposing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _performance = LokalPerformanceScope.of(context);
    _faces.clear(); // Theme, locale and text-size changes rebuild the faces.
  }

  // Width the finger travels to move one album; set per layout.
  double _albumWidth = 120;

  // Same reference-calibrated perspective as desktop: the side cover's
  // outer corners project to x=±1.067, y≈±.46 cover-widths; its inner edge
  // narrows to x=±.429, y≈±.325 (before vanishing-point adjustment).
  // Inset-only hinges could not reproduce these diagonal iTunes triangles.
  static const double _fanAngle = 60;
  static const double _perspective = 1.92;
  static const double _vanishY = .16;

  static double _projectedCenter(double distance) {
    final a = distance.abs();
    return LokalCoverFlow.centerDistance(a) /
        (1 + LokalCoverFlow.depthDistance(a) / _perspective);
  }
  double _stageWidth = 0;

  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 135,
    damping: 24,
  );

  int get _last => math.max(0, widget.albums.length - 1);

  @override
  void didUpdateWidget(LokalCoverFlow old) {
    super.didUpdateWidget(old);
    _faces.clear();
    if (widget.albums.length != old.albums.length && _index > _last) {
      _position.value = _last.toDouble();
    }
  }

  @override
  void dispose() {
    _disposing = true;
    _position.dispose();
    _flip.dispose();
    super.dispose();
  }

  void _onMove() {
    final index = _position.value.round().clamp(0, _last);
    if (index == _index) return;
    _index = index;
    HapticFeedback.selectionClick();
    if (_flip.value > 0) _flip.reverse();
    widget.onIndexChanged?.call(index);
    setState(() {});
  }

  void _settle({double velocity = 0}) {
    if (!mounted || _disposing) return;
    // Momentum carries roughly a third of a second of the fling.
    final projected = _position.value + velocity * .30;
    final target = projected.round().clamp(0, _last).toDouble();
    if (_reduceMotion) {
      _position.value = target;
      return;
    }
    _position.animateWith(
      SpringSimulation(_spring, _position.value, target, velocity),
    );
  }

  void goTo(int index) {
    final target = index.clamp(0, _last).toDouble();
    if (_reduceMotion) {
      _position.value = target;
      return;
    }
    _position.animateWith(
      SpringSimulation(_spring, _position.value, target, 0),
    );
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _position.stop();
    var next = _position.value - details.delta.dx / _albumWidth;
    // Rubber-band past the ends instead of stopping dead.
    if (next < 0) next = _position.value - details.delta.dx / _albumWidth / 3;
    if (next > _last) {
      next = _position.value - details.delta.dx / _albumWidth / 3;
    }
    _position.value = next;
  }

  void _onDragEnd(DragEndDetails details) =>
      _settle(velocity: -details.velocity.pixelsPerSecond.dx / _albumWidth);

  void _select(int index) {
    final onSelect = widget.onSelect;
    if (onSelect == null) {
      index == _index ? _toggleFlip() : goTo(index);
      return;
    }
    HapticFeedback.lightImpact();
    if (_flip.value > 0) _flip.reverse();
    if (index != _index) goTo(index);
    onSelect(index);
  }

  /// The cover nearest [x] across the stage, inverting `_cover`'s layout.
  int _indexAt(double x, double size) {
    final offset = x - _stageWidth / 2;
    if (_reduceMotion || _performance)
      return (_position.value + offset / (size * 1.06)).round().clamp(0, _last);
    // Invert the actual 3D projected center, not a guessed hinge distance.
    final normalizedOffset = offset.abs() / size;
    var lo = 0.0;
    var hi = math.max(1.0, widget.albums.length.toDouble());
    for (var step = 0; step < 24; step++) {
      final mid = (lo + hi) / 2;
      if (_projectedCenter(mid) < normalizedOffset) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final d = offset.sign * (lo + hi) / 2;
    return (_position.value + d).round().clamp(0, _last);
  }

  void _toggleFlip() {
    HapticFeedback.lightImpact();
    if (_reduceMotion) {
      _flip.value = _flip.value > .5 ? 0 : 1;
    } else if (_flip.status == AnimationStatus.completed ||
        _flip.status == AnimationStatus.forward) {
      _flip.reverse();
    } else {
      _flip.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.albums.isEmpty) return const SizedBox.shrink();
    final t = context.lokal;
    final album = widget.albums[_index];
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(250.0, constraints.maxWidth * .60);
        _albumWidth = size * .55;
        _stageWidth = constraints.maxWidth;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              label: lokalText(
                "Cover Flow. {arg0} by {arg1}",
                args: {'arg0': album.albumName, 'arg1': album.albumArtist},
              ),
              value: '${_index + 1} of ${widget.albums.length}',
              increasedValue: _index < _last
                  ? widget.albums[_index + 1].albumName
                  : null,
              decreasedValue: _index > 0
                  ? widget.albums[_index - 1].albumName
                  : null,
              onIncrease: _index < _last ? () => goTo(_index + 1) : null,
              onDecrease: _index > 0 ? () => goTo(_index - 1) : null,
              onTap: () => _select(_index),
              onLongPress: widget.onSelect == null ? null : _toggleFlip,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragDown: (_) => _position.stop(),
                onHorizontalDragUpdate: _onDragUpdate,
                onHorizontalDragEnd: _onDragEnd,
                onHorizontalDragCancel: _settle,
                // A tap in a gap between covers picks the nearest one; a tap
                // on a cover is claimed by that cover first.
                onTapUp: (details) =>
                    _select(_indexAt(details.localPosition.dx, size)),
                child: SizedBox(
                  height: size * 1.18,
                  width: constraints.maxWidth,
                  child: ColoredBox(
                    color: Colors.black, // Keep iTunes' dark cover stage, without reflections.
                    child: AnimatedBuilder(
                      animation: _animation,
                      builder: (context, _) => _stage(size),
                    ),
                  ),
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              child: Column(
                key: ValueKey(album.key),
                children: [
                  Text(
                    album.albumName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: LokalTheme.sans,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: t.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    album.albumArtist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: t.muted),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _stage(double size) {
    if (_faceSize != size) {
      _faces.clear();
      _faceSize = size;
    }
    final position = _position.value;
    final radius = _performance ? 2 : 5;
    final first = math.max(0, position.floor() - radius);
    final lastShown = math.min(_last, position.ceil() + radius);
    final items = <(double, Widget)>[];
    for (var i = first; i <= lastShown; i++) {
      final d = i - position;
      items.add((d.abs(), _cover(i, d, size)));
    }
    final visibleKeys = {
      for (var i = first; i <= lastShown; i++) widget.albums[i].key,
    };
    _faces.removeWhere((key, _) => !visibleKeys.contains(key));
    // Paint the farthest first so the facing album lands on top.
    items.sort((a, b) => b.$1.compareTo(a.$1));
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [for (final item in items) item.$2],
    );
  }

  Widget _cover(int i, double d, double size) {
    final reduce = _reduceMotion || _performance;
    final ad = d.abs();
    final side = d.sign;
    final near = ad.clamp(0.0, 1.0);
    final dx = reduce ? d * size * 1.06
        : side * size * LokalCoverFlow.centerDistance(ad);
    // Both front and side covers rotate about their own center. The *entire*
    // translated panel must pass through the same perspective divide; moving
    // dx outside perspective makes the reference triangles impossible.
    final angle = reduce ? 0.0
        : -side * (2 * near - near * near) * _fanAngle * math.pi / 180;
    final depth = reduce ? 0.0 : -size * LokalCoverFlow.depthDistance(ad);
    final facing = i == _index;
    final flip = facing ? _flip.value : 0.0;
    final vanish = size * _vanishY;
    // Flutter's perspective convention uses w=1+p*z. The NEGATIVE entry
    // ensures rearward depth shrinks (rather than magnifies) the cover.
    final matrix = Matrix4.translationValues(0, vanish, 0)
      ..multiply(
        Matrix4.identity()
          ..setEntry(3, 2, -1 / (_perspective * size))
          ..translateByDouble(dx, -vanish, depth, 1)
          ..rotateY(angle + flip * math.pi),
      );

    final album = widget.albums[i];
    // Cached face contains only the original artwork; no reflection shader,
    // mirrored image, offscreen render pass or duplicated cover subtree.
    final face = _faces.putIfAbsent(album.key, () => RepaintBoundary(
      child: _Front(cover: widget.cover(album), size: size, shadow: !_performance),
    ));
    final showBack = flip > .5;
    return Positioned(
      key: ValueKey(album.key),
      top: size * .06,
      child: Transform(
        // Center pivot exactly matches the desktop projection.
        origin: Offset(size / 2, size / 2),
        transform: matrix,
        child: GestureDetector(
          onTap: () => _select(i),
          onLongPress: facing && widget.onSelect != null ? _toggleFlip : null,
          child: Opacity(
            opacity: (1 - (ad - 4).clamp(0.0, 1.0)),
            child: showBack
                ? Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.rotationY(math.pi),
                    child: _Back(
                      album: album,
                      size: size,
                      onPlay: widget.onPlay,
                    ),
                  )
                : face,
          ),
        ),
      ),
    );
  }
}

class _Front extends StatelessWidget {
  const _Front({required this.cover, required this.size, this.shadow = true});
  final bool shadow;

  final Widget cover;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(6),
      boxShadow: shadow
          ? const [
              BoxShadow(
                color: Color(0x73000000),
                blurRadius: 40,
                offset: Offset(0, 18),
              ),
            ]
          : null,
    ),
    clipBehavior: Clip.antiAlias,
    child: ExcludeSemantics(child: cover),
  );
}

/// The back of the facing cover: its tracks and a Play button.
class _Back extends StatelessWidget {
  const _Back({required this.album, required this.size, required this.onPlay});

  final AlbumGroup album;
  final double size;
  final void Function(Song song, List<Song> album) onPlay;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    final songs = album.songs;
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            album.albumName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: t.text,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: songs.length,
              itemExtent: 22,
              itemBuilder: (context, i) => InkWell(
                onTap: () => onPlay(songs[i], songs),
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      child: Text(
                        lokalText("{arg0}", args: {'arg0': i + 1}),
                        style: LokalTheme.label(t, size: 10),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        songs[i].title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: t.muted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Semantics(
            button: true,
            label: lokalText("Play {arg0}", args: {'arg0': album.albumName}),
            excludeSemantics: true,
            child: GestureDetector(
              onTap: songs.isEmpty ? null : () => onPlay(songs.first, songs),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: t.accent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  lokalText('PLAY'),
                  style: LokalTheme.label(t, size: 10, color: t.onAccent),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
