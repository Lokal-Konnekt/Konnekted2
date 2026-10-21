import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flick/models/song.dart';
import 'package:flick/services/album_art_service.dart';
import 'package:flick/widgets/common/flick_artwork_placeholder.dart';

/// Keeps the last decoded cover until its replacement is ready, then dissolves
/// inside a single clip. The same image cache warms the carousel's neighbours.
class PlayerArtworkImage extends StatefulWidget {
  const PlayerArtworkImage({
    super.key,
    required this.song,
    this.radius = 28,
    this.decodeWidth = 1024,
    this.placeholder,
  });
  final Song song;
  final double radius;
  final int decodeWidth;
  final Widget? placeholder;

  @override
  State<PlayerArtworkImage> createState() => _PlayerArtworkImageState();
}

class _PlayerArtworkImageState extends State<PlayerArtworkImage> {
  ImageProvider? _shown;
  String? _shownKey, _requested;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(PlayerArtworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _resolve();
  }

  Future<void> _resolve() async {
    final song = widget.song;
    final key =
        '${song.id}|${song.albumArt}|${song.filePath}|${widget.decodeWidth}';
    if (_requested == key) return;
    _requested = key;
    final generation = ++_generation;
    ImageProvider? provider;
    try {
      var path = song.albumArt;
      if (path?.startsWith('http://') == true ||
          path?.startsWith('https://') == true) {
        provider = NetworkImage(path!);
      } else {
        if (song.filePath?.isNotEmpty == true)
          path = await AlbumArtService.instance.resolveArtworkPath(
            existingPath: path,
            audioSourcePath: song.filePath!,
          );
        if (path != null && await File(path).exists())
          provider = FileImage(File(path));
      }
      if (!mounted || generation != _generation) return;
      if (provider != null) {
        provider = ResizeImage.resizeIfNeeded(
          widget.decodeWidth,
          null,
          provider,
        );
        var decoded = true;
        await precacheImage(
          provider,
          context,
          onError: (_, _) => decoded = false,
        );
        if (!decoded) provider = null;
      }
    } catch (_) {
      provider = null;
    }
    if (mounted && generation == _generation)
      setState(() {
        _shown = provider;
        _shownKey = key;
      });
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(widget.radius),
    clipBehavior: Clip.antiAlias,
    child: AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 420),
      switchInCurve: Curves.easeInOutCubic,
      // Keep the outgoing cover opaque under the new one. Fading both creates
      // a dark dip halfway through every song change.
      transitionBuilder: (child, animation) => AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (_, child) => Opacity(
          opacity: animation.status == AnimationStatus.reverse
              ? 1
              : animation.value,
          child: child,
        ),
      ),
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, if (current != null) current],
      ),
      child: SizedBox.expand(
        key: ValueKey(_shownKey),
        child: _shown == null
            ? widget.placeholder ?? const FlickArtworkPlaceholder()
            : Image(
                image: _shown!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) =>
                    widget.placeholder ?? const FlickArtworkPlaceholder(),
              ),
      ),
    ),
  );
}
