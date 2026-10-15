import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flick/providers/album_color_provider.dart';
import 'package:flick/providers/app_preferences_provider.dart';
import 'package:flick/services/player_service.dart';
import 'package:flick/services/visualizer_service.dart';

class AudioVisualizer extends ConsumerStatefulWidget {
  final PlayerService playerService;
  final String animationStyle;
  final String frequencyMode;
  final String movementMode;
  final String? colorMode;
  final Color? albumColor;
  final bool enabled;

  const AudioVisualizer({
    super.key,
    required this.playerService,
    this.animationStyle = 'bars',
    this.frequencyMode = 'full',
    this.movementMode = 'bouncy',
    this.colorMode,
    this.albumColor,
    this.enabled = true,
  });

  @override
  ConsumerState<AudioVisualizer> createState() => _AudioVisualizerState();
}

class _AudioVisualizerState extends ConsumerState<AudioVisualizer>
    with TickerProviderStateMixin {
  static const int _barCount = 48;
  static const double _minHeight = 0.04;
  static const double _spring = 0.28;
  static const double _damping = 0.72;
  static const int _blockRows = 20;

  late AnimationController _controller;
  late VisualizerService _visualizerService;

  // Simulated fallback state
  final List<double> _currentHeights = List.filled(_barCount, _minHeight);
  final List<double> _targetHeights = List.filled(_barCount, _minHeight);
  final List<double> _velocities = List.filled(_barCount, 0.0);
  final List<double> _blockOpacities = List.filled(_barCount * _blockRows, 0.0);
  Duration? _lastFrameElapsed;

  bool _isPlaying = false;
  bool _useRealData = false;
  int _frameCount = 0;
  int _songSeed = 0;
  double _songDurationSec = 180.0;

  @override
  void initState() {
    super.initState();
    _visualizerService = VisualizerService();
    _visualizerService.barHeightsNotifier.addListener(_onRealDataChanged);

    _isPlaying = widget.playerService.isPlayingNotifier.value;
    _updateSongSeed();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _controller.addListener(_onFrame);

    widget.playerService.isPlayingNotifier.addListener(_onPlayingChanged);
    widget.playerService.positionNotifier.addListener(_onPositionChanged);
    widget.playerService.currentSongNotifier.addListener(_onSongChanged);
    widget.playerService.usingRustBackendNotifier.addListener(
      _onBackendChanged,
    );

    _syncVisualizerAttachment();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateControllerState();
  }

  @override
  void didUpdateWidget(AudioVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) {
      _updateControllerState();
    }
    if (oldWidget.animationStyle != widget.animationStyle ||
        oldWidget.frequencyMode != widget.frequencyMode) {
      _blockOpacities.fillRange(0, _blockOpacities.length, 0.0);
    }
    if (oldWidget.playerService != widget.playerService) {
      oldWidget.playerService.isPlayingNotifier.removeListener(
        _onPlayingChanged,
      );
      oldWidget.playerService.positionNotifier.removeListener(
        _onPositionChanged,
      );
      oldWidget.playerService.currentSongNotifier.removeListener(
        _onSongChanged,
      );
      oldWidget.playerService.usingRustBackendNotifier.removeListener(
        _onBackendChanged,
      );
      widget.playerService.isPlayingNotifier.addListener(_onPlayingChanged);
      widget.playerService.positionNotifier.addListener(_onPositionChanged);
      widget.playerService.currentSongNotifier.addListener(_onSongChanged);
      widget.playerService.usingRustBackendNotifier.addListener(
        _onBackendChanged,
      );
      _isPlaying = widget.playerService.isPlayingNotifier.value;
      _resetAnimation();
      _updateSongSeed();
      _syncVisualizerAttachment();
      _updateControllerState();
    }
  }

  void _onRealDataChanged() {
    final real = _visualizerService.barHeightsNotifier.value;
    if (mounted) {
      setState(() {
        _useRealData = real != null && real.length == _barCount;
      });
    }
  }

  void _onBackendChanged() => _syncVisualizerAttachment();

  void _syncVisualizerAttachment() {
    // ponytail: never attach the native Visualizer — attaching any AudioEffect
    // forces Android off the compressed-offload/direct path and tanks quality
    // (breaks hardware Atmos/EAC3). The simulated path is good enough.
    _visualizerService.detach();
  }

  void _onSongChanged() {
    setState(() {
      _resetAnimation();
      _updateSongSeed();
      if (_isPlaying) _onPositionChanged();
    });
  }

  void _resetAnimation() {
    _currentHeights.fillRange(0, _barCount, _minHeight);
    _targetHeights.fillRange(0, _barCount, _minHeight);
    _velocities.fillRange(0, _barCount, 0.0);
    _blockOpacities.fillRange(0, _blockOpacities.length, 0.0);
    _lastFrameElapsed = null;
    _frameCount = 0;
  }

  void _updateSongSeed() {
    final song = widget.playerService.currentSongNotifier.value;
    if (song == null) return;
    final path = song.filePath ?? song.id;
    var hash = 0x811c9dc5;
    for (var i = 0; i < path.length; i++) {
      hash ^= path.codeUnitAt(i);
      hash = _imul(hash, 0x01000193);
    }
    hash ^= song.duration.inMilliseconds;
    hash = _imul(hash, 0x01000193);
    _songSeed = hash;
    _songDurationSec = math.max(10.0, song.duration.inMilliseconds / 1000.0);
  }

  static int _imul(int a, int b) {
    final ah = (a >> 16) & 0xffff;
    final al = a & 0xffff;
    final bh = (b >> 16) & 0xffff;
    final bl = b & 0xffff;
    return ((al * bl) + (((ah * bl + al * bh) << 16) >> 0)) | 0;
  }

  double _frand(int n) {
    var x = _songSeed ^ n;
    x = ((x >> 16) ^ x) * 0x45d9f3b;
    x = ((x >> 16) ^ x) * 0x45d9f3b;
    x = (x >> 16) ^ x;
    return (x & 0x7fffffff) / 0x7fffffff;
  }

  double _noise2D(double x, double y) {
    final ix = x.floor();
    final iy = y.floor();
    final fx = x - ix;
    final fy = y - iy;

    final n00 = _frand(ix * 73856093 ^ iy * 19349663);
    final n10 = _frand((ix + 1) * 73856093 ^ iy * 19349663);
    final n01 = _frand(ix * 73856093 ^ (iy + 1) * 19349663);
    final n11 = _frand((ix + 1) * 73856093 ^ (iy + 1) * 19349663);

    final u = fx * fx * (3.0 - 2.0 * fx);
    final v = fy * fy * (3.0 - 2.0 * fy);

    return n00 * (1 - u) * (1 - v) +
        n10 * u * (1 - v) +
        n01 * (1 - u) * v +
        n11 * u * v;
  }

  double _fbm(double x, double y, int octaves) {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 1.0;
    for (var i = 0; i < octaves; i++) {
      value += amplitude * _noise2D(x * frequency, y * frequency);
      amplitude *= 0.5;
      frequency *= 2.0;
    }
    return value;
  }

  double _songEnergy(double t) {
    final progress = t / _songDurationSec;
    final sectionNoise = _fbm(progress * 8.0, _songSeed * 0.1, 3);

    double energy;
    if (progress < 0.08) {
      energy = 0.2 + progress * 3.75;
    } else if (progress < 0.35) {
      energy = 0.5 + sectionNoise * 0.2;
    } else if (progress < 0.55) {
      energy = 0.75 + sectionNoise * 0.2;
    } else if (progress < 0.72) {
      energy = 0.55 + sectionNoise * 0.15;
    } else if (progress < 0.88) {
      energy = 0.85 + sectionNoise * 0.15;
    } else {
      energy = 0.6 * (1.0 - (progress - 0.88) / 0.12);
    }

    final swell = math.sin(progress * math.pi * 6.0 + _songSeed) * 0.08 +
        math.sin(progress * math.pi * 14.0 + _songSeed * 2.0) * 0.04;

    return (energy + swell).clamp(0.1, 1.0);
  }

  void _computeSimulatedTargets(int positionMs) {
    final t = positionMs / 1000.0;
    final energy = _songEnergy(t);

    final beatPhase = (t * (_frand(1) * 2.0 + 1.8)) % 1.0;
    final isBeat = beatPhase < 0.12;
    final beatStrength = isBeat ? (1.0 - beatPhase / 0.12) : 0.0;

    final fastBeatPhase = (t * (_frand(2) * 4.0 + 4.0)) % 1.0;
    final isFastBeat = fastBeatPhase < 0.08;
    final fastBeatStrength = isFastBeat ? (1.0 - fastBeatPhase / 0.08) * 0.4 : 0.0;

    for (int i = 0; i < _barCount; i++) {
      final x = i / (_barCount - 1);

      final freqFactor = x < 0.25
          ? 0.4
          : x < 0.5
              ? 0.8
              : x < 0.75
                  ? 1.3
                  : 1.8;

      final barSeed = i * 7919 + _songSeed;
      final charOffset = _frand(barSeed) * 2.0 - 1.0;

      final noiseTime = t * freqFactor * (0.8 + _frand(barSeed + 1) * 0.6);
      final noiseFreq = x * 12.0 + charOffset * 3.0;
      final organic = _fbm(noiseTime, noiseFreq, 4);

      final bassEnv = math.exp(-x * 5.0);
      final midEnv = math.exp(-((x - 0.35) * 6.0).abs());
      final trebleEnv = math.exp(-((x - 0.75) * 8.0).abs());

      final bassMovement = organic * bassEnv * 0.9;
      final midMovement = organic * midEnv * 0.7;
      final trebleMovement = organic * trebleEnv * 0.5;

      final bassBeat = beatStrength * bassEnv * 0.5;
      final midBeat = beatStrength * midEnv * 0.3;
      final trebleFastBeat = fastBeatStrength * trebleEnv * 0.4;

      var height = (bassMovement + midMovement + trebleMovement + bassBeat + midBeat + trebleFastBeat) * energy;

      final transientChance = _frand((t * 30.0).floor() * 97 + barSeed);
      if (transientChance > 0.985) {
        height += _frand((t * 30.0).floor() * 53 + barSeed) * 0.35 * energy;
      }

      height = (height * 1.1 + 0.05).clamp(_minHeight, 1.0);
      _targetHeights[i] = height;
    }
  }

  void _onPositionChanged() {
    if (!_isPlaying || _useRealData) return;
    final ms = widget.playerService.positionNotifier.value.inMilliseconds;
    _computeSimulatedTargets(ms);
  }

  void _onPlayingChanged() {
    final playing = widget.playerService.isPlayingNotifier.value;
    if (playing == _isPlaying) return;
    _isPlaying = playing;
    _syncVisualizerAttachment();
    if (!_isPlaying && !_useRealData) {
      for (int i = 0; i < _barCount; i++) {
        _targetHeights[i] = _minHeight;
      }
    }
    _updateControllerState();
  }

  void _updateControllerState() {
    if (!mounted) return;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (!widget.enabled ||
        reducedMotion ||
        !TickerMode.valuesOf(context).enabled) {
      if (_controller.isAnimating) _controller.stop();
      _lastFrameElapsed = null;
      _blockOpacities.fillRange(0, _blockOpacities.length, 0.0);
      return;
    }
    if (_isPlaying && !_controller.isAnimating) {
      _lastFrameElapsed = null;
      _controller.repeat();
    }
  }

  void _onFrame() {
    if (!mounted) return;
    _frameCount++;
    final elapsed = _controller.lastElapsedDuration ?? Duration.zero;
    final deltaSeconds = _lastFrameElapsed == null
        ? 0.0
        : math.max(0.0, (elapsed - _lastFrameElapsed!).inMicroseconds / 1e6);
    _lastFrameElapsed = elapsed;

    if (_useRealData) {
      return;
    }

    for (int i = 0; i < _barCount; i++) {
      switch (widget.movementMode) {
        case 'smooth':
          // Asymmetric attack / decay for a natural equalizer feel.
          // Fast attack so beats register immediately, gentler decay
          // so bars don't snap to zero.
          if (_targetHeights[i] >= _currentHeights[i]) {
            // Rising — fast attack
            _currentHeights[i] =
                _currentHeights[i] * 0.45 + _targetHeights[i] * 0.55;
          } else {
            // Falling — moderate decay
            _currentHeights[i] =
                _currentHeights[i] * 0.65 + _targetHeights[i] * 0.35;
          }
        case 'snappy':
          _currentHeights[i] =
              _currentHeights[i] * 0.25 + _targetHeights[i] * 0.75;
        default:
          final diff = _targetHeights[i] - _currentHeights[i];
          _velocities[i] = _velocities[i] * _damping + diff * _spring;
          _currentHeights[i] =
              (_currentHeights[i] + _velocities[i]).clamp(_minHeight, 1.0);
      }
      if (widget.movementMode != 'bouncy') {
        _currentHeights[i] = _currentHeights[i].clamp(_minHeight, 1.0);
      }
    }

    if (_isPlaying && _frameCount % 2 == 0) {
      final ms = widget.playerService.positionNotifier.value.inMilliseconds;
      _computeSimulatedTargets(ms);
    }

    if (widget.animationStyle == 'blocks') {
      final heights = _displayHeights;
      final decay = math.exp(-deltaSeconds * 6.0);
      for (var i = 0; i < _barCount; i++) {
        final litRows = (heights[i] * _blockRows).ceil();
        for (var row = 0; row < _blockRows; row++) {
          final index = i * _blockRows + row;
          _blockOpacities[index] = row < litRows
              ? 1.0
              : _blockOpacities[index] * decay;
        }
      }
    }

    if (!_isPlaying && !_useRealData && _controller.isAnimating) {
      bool settled = true;
      for (int i = 0; i < _barCount; i++) {
        if ((_currentHeights[i] - _minHeight).abs() > 0.01) {
          settled = false;
          break;
        }
      }
      final trailsSettled = widget.animationStyle != 'blocks' ||
          _blockOpacities.every((opacity) => opacity < 0.01 || opacity == 1.0);
      if (settled && trailsSettled) {
        _controller.stop();
      }
    }
  }

  List<double> get _displayHeights {
    final raw = _useRealData
        ? (_visualizerService.barHeightsNotifier.value ?? _currentHeights)
        : _currentHeights;
    final mask = _frequencyMask(widget.frequencyMode);
    final result = List<double>.filled(_barCount, _minHeight);
    for (int i = 0; i < _barCount; i++) {
      final masked = (raw[i] * mask[i]).clamp(_minHeight, 1.0);
      result[i] = masked < 0.06 ? _minHeight : masked;
    }
    return result;
  }

  static List<double> _frequencyMask(String mode) {
    final w = List<double>.filled(_barCount, 1.0);
    final n = _barCount;

    void rampDown(int start, int end) {
      for (int i = start; i <= end && i < n; i++) {
        final t = end > start ? (i - start) / (end - start) : 1.0;
        w[i] = 1.0 - t * 0.95;
      }
    }

    void rampUp(int start, int end) {
      for (int i = start; i <= end && i < n; i++) {
        final t = end > start ? (i - start) / (end - start) : 1.0;
        w[i] = 0.05 + t * 0.95;
      }
    }

    switch (mode) {
      case 'bass':
        rampDown(12, 17);
        for (int i = 18; i < n; i++) {
          w[i] = 0.05;
        }
      case 'mid':
        rampUp(0, 11);
        rampDown(36, 41);
        for (int i = 42; i < n; i++) {
          w[i] = 0.05;
        }
      case 'treble':
        for (int i = 0; i < 36; i++) {
          w[i] = 0.05;
        }
        rampUp(36, 41);
      case 'bass_treble':
        rampDown(12, 23);
        for (int i = 24; i < 36; i++) {
          w[i] = 0.05;
        }
        rampUp(36, 41);
    }
    return w;
  }

  @override
  void dispose() {
    widget.playerService.isPlayingNotifier.removeListener(_onPlayingChanged);
    widget.playerService.positionNotifier.removeListener(_onPositionChanged);
    widget.playerService.currentSongNotifier.removeListener(_onSongChanged);
    widget.playerService.usingRustBackendNotifier.removeListener(
      _onBackendChanged,
    );
    _visualizerService.barHeightsNotifier.removeListener(_onRealDataChanged);
    _visualizerService.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return const SizedBox.shrink();
    }
    final String colorMode = widget.colorMode ??
        ref.watch<String>(
          appPreferencesProvider.select((prefs) => prefs.visualizerColorMode),
        );
    final albumColor = colorMode == 'album_art'
        ? widget.albumColor ?? ref.watch(albumDominantColorSyncProvider)
        : null;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _VisualizerBarPainter(
              barHeights: _displayHeights,
              animationStyle: widget.animationStyle,
              colorMode: colorMode,
              albumColor: albumColor,
              blockOpacities: widget.animationStyle == 'blocks'
                  ? List.of(_blockOpacities)
                  : const [],
              repaint: _controller,
            ),
          );
        },
      ),
    );
  }
}

class _VisualizerBarPainter extends CustomPainter {
  final List<double> barHeights;
  final String animationStyle;
  final String colorMode;
  final Color? albumColor;
  final List<double> blockOpacities;

  _VisualizerBarPainter({
    required this.barHeights,
    required this.animationStyle,
    required this.colorMode,
    required this.blockOpacities,
    this.albumColor,
    required Listenable repaint,
  }) : super(repaint: repaint);

  Color _barColor(double t) {
    if (colorMode == 'rainbow') {
      return HSLColor.fromAHSL(1.0, t * 300.0, 0.80, 0.65).toColor();
    }
    if (colorMode == 'monochrome' || albumColor == null) {
      final b = 1.0 - t * 0.40;
      return Color.fromRGBO((255 * b).round(), (255 * b).round(), (255 * b).round(), 1.0);
    }
    final hsl = HSLColor.fromColor(albumColor!);
    final l = 0.56 + t * 0.10;
    final s = hsl.saturation < 0.05
        ? 0.0
        : (hsl.saturation * 1.35 + 0.20).clamp(0.72, 1.0);
    return hsl.withLightness(l).withSaturation(s).toColor();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    switch (animationStyle) {
      case 'wave':
        _paintWave(canvas, size);
      case 'curved_wave':
        _paintCurvedWave(canvas, size);
      case 'mirrored':
        _paintMirrored(canvas, size);
      case 'dots':
        _paintDots(canvas, size);
      case 'blocks':
        _paintBlocks(canvas, size);
      default:
        _paintBars(canvas, size);
    }
  }

  void _paintBars(Canvas canvas, Size size) {
    final barCount = barHeights.length;
    final spacing = math.min(2.5, size.width / (barCount * 2));
    final totalSpacing = (barCount - 1) * spacing;
    final barWidth = (size.width - totalSpacing) / barCount;
    final maxBarHeight = size.height * 0.88;

    for (int i = 0; i < barCount; i++) {
      final height = barHeights[i] * maxBarHeight;
      final t = barCount > 1 ? i / (barCount - 1) : 0.0;
      final color = _barColor(t);

      final x = i * (barWidth + spacing);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, size.height - height, barWidth, height),
        const Radius.circular(2.0),
      );

      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawRRect(rect, glowPaint);

      final barPaint = Paint()..color = color.withValues(alpha: 0.82);
      canvas.drawRRect(rect, barPaint);
    }
  }

  void _paintBlocks(Canvas canvas, Size size) {
    const sourceRows = _AudioVisualizerState._blockRows;
    const cellSize = 6.0;
    final availableHeight = size.height * 0.88;
    final pitch = math.min(cellSize, math.min(size.width, availableHeight));
    final columns = math.max(1, (size.width / pitch).floor());
    final rows = math.max(1, (availableHeight / pitch).floor());
    final gap = math.min(2.0, pitch * 0.25);
    final blockSize = pitch - gap;
    final left = (size.width - columns * pitch) / 2;
    final paint = Paint();

    for (var column = 0; column < columns; column++) {
      final source = (column * barHeights.length / columns).floor();
      final t = columns > 1 ? column / (columns - 1) : 0.5;
      final color = _barColor(t);
      for (var row = 0; row < rows; row++) {
        final sourceRow = (row * sourceRows / rows).floor();
        final lit = row < (barHeights[source] * rows).ceil();
        final trail = blockOpacities[source * sourceRows + sourceRow];
        final intensity = lit ? 1.0 : trail;
        if (intensity < 0.01) continue;
        paint.color = color.withValues(
          alpha: intensity * (0.88 - row / rows * 0.30),
        );
        canvas.drawRect(
          Rect.fromLTWH(
            left + column * pitch + gap / 2,
            size.height - (row + 1) * pitch + gap / 2,
            blockSize,
            blockSize,
          ),
          paint,
        );
      }
    }
  }

  Shader _rainbowShader(Size size, double alpha) => LinearGradient(
    colors: List.generate(
      7,
      (i) => _barColor(i / 6).withValues(alpha: alpha),
    ),
  ).createShader(Offset.zero & size);

  void _paintWave(Canvas canvas, Size size) {
    final barCount = barHeights.length;
    final maxHeight = size.height * 0.44;
    final baseline = size.height;
    final spacing = size.width / barCount;

    final topPath = Path();
    topPath.moveTo(0, baseline);
    for (int i = 0; i < barCount; i++) {
      final x = i * spacing + spacing / 2;
      final y = baseline - barHeights[i] * maxHeight;
      topPath.lineTo(x, y);
    }
    topPath.lineTo(size.width, baseline);
    topPath.close();

    final leftColor = _barColor(0.0);
    final rightColor = _barColor(1.0);
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          leftColor.withValues(alpha: 0.85),
          rightColor.withValues(alpha: 0.15),
        ],
      ).createShader(Rect.fromLTWH(0, baseline - maxHeight, size.width, maxHeight));
    if (colorMode == 'rainbow') {
      fillPaint.shader = _rainbowShader(size, 0.40);
    }
    canvas.drawPath(topPath, fillPaint);

    final linePath = Path();
    for (int i = 0; i < barCount; i++) {
      final x = i * spacing + spacing / 2;
      final y = baseline - barHeights[i] * maxHeight;
      if (i == 0) {
        linePath.moveTo(x, y);
      } else {
        linePath.lineTo(x, y);
      }
    }
    final linePaint = Paint()
      ..color = _barColor(0.5).withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    if (colorMode == 'rainbow') linePaint.shader = _rainbowShader(size, 0.95);
    canvas.drawPath(linePath, linePaint);

    for (int i = 0; i < barCount; i += 2) {
      final x = i * spacing + spacing / 2;
      final y = baseline - barHeights[i] * maxHeight;
      final t = barCount > 1 ? i / (barCount - 1) : 0.0;
      final dotPaint = Paint()
        ..color = _barColor(t).withValues(alpha: 0.7)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
      canvas.drawCircle(Offset(x, y), 1.5, dotPaint);
    }
  }

  void _paintCurvedWave(Canvas canvas, Size size) {
    final barCount = barHeights.length;
    final maxHeight = size.height * 0.50;
    final baseline = size.height;
    final spacing = size.width / (barCount - 1);

    // Build sample points along the wave.
    final points = <Offset>[];
    for (int i = 0; i < barCount; i++) {
      final x = i * spacing;
      final y = baseline - barHeights[i] * maxHeight;
      points.add(Offset(x, y));
    }

    // Convert Catmull-Rom control points to smooth cubic Bézier path.
    Path smoothPath(List<Offset> pts) {
      final path = Path();
      if (pts.length < 2) return path;
      path.moveTo(pts[0].dx, pts[0].dy);
      if (pts.length == 2) {
        path.lineTo(pts[1].dx, pts[1].dy);
        return path;
      }
      for (int i = 0; i < pts.length - 1; i++) {
        final p0 = i > 0 ? pts[i - 1] : pts[i];
        final p1 = pts[i];
        final p2 = pts[i + 1];
        final p3 = i + 2 < pts.length ? pts[i + 2] : pts[i + 1];
        // Catmull-Rom → cubic Bézier control points
        final cp1x = p1.dx + (p2.dx - p0.dx) / 6.0;
        final cp1y = p1.dy + (p2.dy - p0.dy) / 6.0;
        final cp2x = p2.dx - (p3.dx - p1.dx) / 6.0;
        final cp2y = p2.dy - (p3.dy - p1.dy) / 6.0;
        path.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
      }
      return path;
    }

    // --- Filled area ---
    final curvePath = smoothPath(points);
    final fillPath = Path.from(curvePath);
    fillPath.lineTo(size.width, baseline);
    fillPath.lineTo(0, baseline);
    fillPath.close();

    final topColor = _barColor(0.3);
    final bottomColor = _barColor(0.7);
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          topColor.withValues(alpha: 0.70),
          bottomColor.withValues(alpha: 0.08),
        ],
      ).createShader(
          Rect.fromLTWH(0, baseline - maxHeight, size.width, maxHeight));
    if (colorMode == 'rainbow') fillPaint.shader = _rainbowShader(size, 0.35);
    canvas.drawPath(fillPath, fillPaint);

    // --- Glow stroke ---
    final glowPaint = Paint()
      ..color = _barColor(0.5).withValues(alpha: 0.30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    if (colorMode == 'rainbow') glowPaint.shader = _rainbowShader(size, 0.30);
    canvas.drawPath(curvePath, glowPaint);

    // --- Main stroke ---
    final strokePaint = Paint()
      ..color = _barColor(0.5).withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    if (colorMode == 'rainbow') strokePaint.shader = _rainbowShader(size, 0.95);
    canvas.drawPath(curvePath, strokePaint);
  }

  void _paintMirrored(Canvas canvas, Size size) {
    final barCount = barHeights.length;
    final half = barCount ~/ 2;
    final spacing = math.min(2.0, size.width * 0.48 / (half * 2));
    final totalSpacing = (half - 1) * spacing;
    final barWidth = (size.width * 0.48 - totalSpacing) / half;
    final maxHeight = size.height * 0.42;

    for (int i = 0; i < half; i++) {
      final leftIdx = half - 1 - i;
      final rightIdx = half + i;
      final height = ((barHeights[leftIdx] + barHeights[rightIdx]) / 2) * maxHeight;
      final t = i / (half - 1);
      final color = _barColor(t);

      final xFromCenter = i * (barWidth + spacing) + barWidth / 2;
      final centerX = size.width / 2;
      final leftX = centerX - xFromCenter - barWidth / 2;
      final rightX = centerX + xFromCenter - barWidth / 2;

      void drawBar(double x, double y) {
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, height),
          const Radius.circular(1.5),
        );

        final glowPaint = Paint()
          ..color = color.withValues(alpha: 0.15)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
        canvas.drawRRect(rect, glowPaint);

        final barPaint = Paint()..color = color.withValues(alpha: 0.78);
        canvas.drawRRect(rect, barPaint);
      }

      drawBar(leftX, size.height / 2 - height);
      drawBar(rightX, size.height / 2 - height);
      drawBar(leftX, size.height / 2);
      drawBar(rightX, size.height / 2);
    }
  }

  void _paintDots(Canvas canvas, Size size) {
    final barCount = barHeights.length;
    final maxRadius = size.height * 0.38;
    final minRadius = maxRadius * 0.04;
    final baseline = size.height / 2;
    final spacing = size.width / barCount;

    for (int i = 0; i < barCount; i++) {
      final x = i * spacing + spacing / 2;
      final radius = (barHeights[i] * (maxRadius - minRadius) + minRadius)
          .clamp(minRadius, maxRadius);
      final t = barCount > 1 ? i / (barCount - 1) : 0.0;
      final color = _barColor(t);

      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
      canvas.drawCircle(Offset(x, baseline), radius, glowPaint);

      final dotPaint = Paint()..color = color.withValues(alpha: 0.85);
      canvas.drawCircle(Offset(x, baseline), radius, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_VisualizerBarPainter oldDelegate) => true;
}
