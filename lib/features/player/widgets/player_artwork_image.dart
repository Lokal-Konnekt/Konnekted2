import 'package:flick/core/theme/lokal_performance_scope.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flick/models/song.dart';
import 'package:flick/services/album_art_service.dart';
import 'package:flick/widgets/common/flick_artwork_placeholder.dart';

/// Holds decoded frames through a cover change. Painting RawImage avoids a
/// second asynchronous image resolution when a carousel stage changes slots.
class PlayerArtworkImage extends StatefulWidget {
  const PlayerArtworkImage({
    super.key,
    required this.song,
    this.radius = 28,
    this.decodeWidth = 1024,
    this.placeholder,
    this.crossfade = true,
  });
  final Song song;
  final double radius;
  final int decodeWidth;
  final Widget? placeholder;
  final bool crossfade;

  @override
  State<PlayerArtworkImage> createState() => _PlayerArtworkImageState();
}

class _PlayerArtworkImageState extends State<PlayerArtworkImage>
    with SingleTickerProviderStateMixin {
  late final _fade =
      AnimationController(
        vsync: this,
        value: 1,
        duration: const Duration(milliseconds: 420),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() {
            _previous?.dispose();
            _previous = null;
          });
        }
      });
  ImageInfo? _shown, _previous;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  String? _shownKey, _requested;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
    if (MediaQuery.disableAnimationsOf(context)) _fade.value = 1;
  }

  @override
  void didUpdateWidget(PlayerArtworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _resolve();
  }

  void _unsubscribe() {
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
    _listener = null;
    _stream = null;
  }

  Future<void> _resolve() async {
    final song = widget.song;
    final decodeWidth = LokalPerformanceScope.of(context)
        ? widget.decodeWidth.clamp(64, 768)
        : widget.decodeWidth;
    final key = '${song.id}|${song.albumArt}|${song.filePath}|${decodeWidth}';
    if (_requested == key) return;
    _requested = key;
    final generation = ++_generation;
    _unsubscribe();
    try {
      ImageProvider? provider;
      var path = song.albumArt;
      if (path?.startsWith('http://') == true ||
          path?.startsWith('https://') == true) {
        provider = NetworkImage(path!);
      } else {
        if (song.filePath?.isNotEmpty == true) {
          path = await AlbumArtService.instance.resolveArtworkPath(
            existingPath: path,
            audioSourcePath: song.filePath!,
          );
        }
        if (path != null && await File(path).exists()) {
          provider = FileImage(File(path));
        }
      }
      if (!mounted || generation != _generation) return;
      if (provider == null) {
        _showFrame(null, key);
        return;
      }
      provider = ResizeImage.resizeIfNeeded(decodeWidth, null, provider);
      _stream = provider.resolve(createLocalImageConfiguration(context));
      _listener = ImageStreamListener(
        (info, _) {
          if (!mounted || generation != _generation) {
            info.dispose();
            return;
          }
          _showFrame(info, key);
        },
        onError: (_, _) {
          if (mounted && generation == _generation) _showFrame(null, key);
        },
      );
      _stream!.addListener(_listener!);
    } catch (_) {
      if (mounted && generation == _generation) _showFrame(null, key);
    }
  }

  void _showFrame(ImageInfo? frame, String key) {
    final animate =
        widget.crossfade &&
        _shown != null &&
        frame != null &&
        _shownKey != key &&
        !MediaQuery.disableAnimationsOf(context);
    _fade.stop();
    setState(() {
      _previous?.dispose();
      _previous = animate ? _shown : null;
      if (!animate) _shown?.dispose();
      _shown = frame;
      _shownKey = key;
    });
    if (animate) {
      _fade.forward(from: 0);
    } else {
      _fade.value = 1;
    }
  }

  @override
  void dispose() {
    _generation++;
    _unsubscribe();
    _fade.dispose();
    _shown?.dispose();
    _previous?.dispose();
    super.dispose();
  }

  Widget _image(ImageInfo info) => RawImage(
    image: info.image,
    scale: info.scale,
    fit: BoxFit.cover,
    filterQuality: FilterQuality.medium,
  );

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(widget.radius),
    clipBehavior: Clip.antiAlias,
    child: AnimatedBuilder(
      animation: _fade,
      builder: (context, _) => Stack(
        fit: StackFit.expand,
        children: [
          if (_previous != null) _image(_previous!),
          if (_shown == null)
            widget.placeholder ?? const FlickArtworkPlaceholder()
          else
            Opacity(
              opacity: Curves.easeInOutCubic.transform(_fade.value),
              child: _image(_shown!),
            ),
        ],
      ),
    ),
  );
}
