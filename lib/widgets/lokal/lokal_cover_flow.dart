import 'package:flick/l10n/l10n.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';
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
/// The facing album sits flat and forward; its neighbours turn 70° away and
/// stack behind, each with a floor reflection. Drag to spin with momentum,
/// settle on the nearest album with a spring, and feel a tick for every
/// album that passes. With [onSelect], one tap on any cover brings it forward
/// and selects it (Home plays it straight away); long-press the facing cover
/// to flip it over to its track list. Without [onSelect], a tap brings a side
/// cover forward and flips the facing one.
class LokalCoverFlow extends StatefulWidget {
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

  // Width the finger travels to move one album; set per layout.
  double _albumWidth = 120;
  double _stageWidth = 0;

  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 170,
    damping: 26,
  );

  int get _last => math.max(0, widget.albums.length - 1);

  @override
  void didUpdateWidget(LokalCoverFlow old) {
    super.didUpdateWidget(old);
    if (widget.albums.length != old.albums.length && _index > _last) {
      _position.value = _last.toDouble();
    }
  }

  @override
  void dispose() {
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

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  void _settle({double velocity = 0}) {
    // Momentum carries roughly a third of a second of the fling.
    final projected = _position.value + velocity * .32;
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
    final near = size * .72;
    final d = offset.abs() <= near
        ? offset / near
        : offset.sign * (1 + (offset.abs() - near) / (size * .30));
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
        final size = math.min(220.0, constraints.maxWidth * .52);
        _albumWidth = size * .6;
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
                  height: size * 1.42,
                  width: constraints.maxWidth,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_position, _flip]),
                    builder: (context, _) => _stage(size),
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
    final position = _position.value;
    final first = math.max(0, position.floor() - 5);
    final lastShown = math.min(_last, position.ceil() + 5);
    final items = <(double, Widget)>[];
    for (var i = first; i <= lastShown; i++) {
      final d = i - position;
      items.add((d.abs(), _cover(i, d, size)));
    }
    // Paint the farthest first so the facing album lands on top.
    items.sort((a, b) => b.$1.compareTo(a.$1));
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [for (final item in items) item.$2],
    );
  }

  Widget _cover(int i, double d, double size) {
    final reduce = _reduceMotion;
    final ad = d.abs();
    final side = d.sign;
    final near = ad.clamp(0.0, 1.0);
    // Facing album to first neighbour: slide out, turn, and sink back.
    // The original iPod Cover Flow leaves a clear front-facing cover and
    // fans its neighbours behind it. Give each side cover its own spacing
    // and depth instead of flattening the whole stack onto one plane.
    final dx = ad <= 1
        ? d * size * .72
        : side * (size * .72 + (ad - 1) * size * .30);
    final angle = reduce ? 0.0 : -side * near * 70 * math.pi / 180;
    final depth = reduce ? 0.0 : (26 - math.min(ad, 4) * 42).toDouble();
    final facing = i == _index;
    final flip = facing ? _flip.value : 0.0;

    final matrix = Matrix4.identity()
      ..setEntry(3, 2, .0012)
      ..translateByDouble(dx, 0, depth, 1)
      ..rotateY(angle + flip * math.pi);

    final album = widget.albums[i];
    final front = _Front(cover: widget.cover(album), size: size);
    final showBack = flip > .5;
    return Positioned(
      top: size * .06,
      child: Transform(
        // Rotate around the centre of the square album artwork, not the
        // centre of the much taller artwork-plus-reflection column. That
        // misplaced pivot is what made covers tilt and overlap oddly.
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
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      front,
                      SizedBox(height: size * .02),
                      _Reflection(size: size, child: front),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _Front extends StatelessWidget {
  const _Front({required this.cover, required this.size});

  final Widget cover;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(6),
      boxShadow: const [
        BoxShadow(
          color: Color(0x73000000),
          blurRadius: 40,
          offset: Offset(0, 18),
        ),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: ExcludeSemantics(child: cover),
  );
}

/// The cover mirrored onto a glossy floor, fading out.
class _Reflection extends StatelessWidget {
  const _Reflection({required this.size, required this.child});

  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size * .32,
    child: ClipRect(
      child: OverflowBox(
        alignment: Alignment.topCenter,
        maxHeight: size,
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x47FFFFFF), Color(0x00FFFFFF)],
            stops: [0, .32],
          ).createShader(rect),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.diagonal3Values(1, -1, 1),
            child: IgnorePointer(child: child),
          ),
        ),
      ),
    ),
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
