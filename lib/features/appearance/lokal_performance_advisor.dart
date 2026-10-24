import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/lokal_appearance.dart';
import '../../core/utils/app_log.dart';
import '../../l10n/l10n.dart';

/// Distinguish CPU-heavy rasterization from UI work in release diagnostics.
@visibleForTesting
String lokalFrameBottleneck(int frames, int slowUi, int slowRaster) {
  if (frames == 0) return 'no-frames';
  if (slowUi == 0 && slowRaster == 0) return 'none';
  if (slowUi > slowRaster * 2) return 'ui';
  if (slowRaster > slowUi * 2) return 'raster';
  return 'mixed';
}

/// Samples the first foreground minutes. Suggests once; never changes the look
/// without a tap, and never measures background or already-solid surfaces.
class LokalPerformanceAdvisor extends ConsumerStatefulWidget {
  const LokalPerformanceAdvisor({super.key, required this.child});
  final Widget child;
  static int lastGlassPaintMicros = 0;
  @override
  ConsumerState<LokalPerformanceAdvisor> createState() =>
      _LokalPerformanceAdvisorState();
}

class _LokalPerformanceAdvisorState
    extends ConsumerState<LokalPerformanceAdvisor>
    with WidgetsBindingObserver {
  static const _seenKey = 'lokal.performance_suggestion_shown.v1';
  int _frames = 0, _missed = 0;
  bool _foreground = true, _seen = true, _suggesting = false;
  Timer? _timer;
  Timer? _diagnosticTimer;
  static const _diagnostics = MethodChannel('com.mossapps.flick/diagnostics');
  int _windowFrames = 0, _windowUiMisses = 0, _windowRasterMisses = 0;
  int? _previousCpuMs, _previousWallMs;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_start());
  }

  Future<void> _start() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _seen = prefs.getBool(_seenKey) ?? false;
    // Even if the banner was dismissed and even in Ultra mode we must
    // measure: the Galaxy S25 Ultra report persists in Ultra mode, and the
    // original advisor silently stopped counting these frames.
    SchedulerBinding.instance.addTimingsCallback(_timings);
    _timer = Timer(const Duration(minutes: 2), _finish);
    _diagnosticTimer = Timer.periodic(
      const Duration(seconds: 15), (_) => unawaited(_logPerformance()),
    );
    unawaited(_logPerformance());
  }

  void _timings(List<FrameTiming> values) {
    if (!_foreground || !mounted) return;
    final rate = View.of(context).display.refreshRate;
    final budget = 1000000 / (rate > 0 ? rate : 60);
    final maySuggest = !_seen &&
        !ref.read(lokalAppearanceProvider).performanceMode &&
        DateTime.now().microsecondsSinceEpoch -
                LokalPerformanceAdvisor.lastGlassPaintMicros <=
            500000;
    for (final frame in values) {
      final slowUi = frame.buildDuration.inMicroseconds > budget;
      final slowRaster = frame.rasterDuration.inMicroseconds > budget;
      _windowFrames++;
      if (slowUi) _windowUiMisses++;
      if (slowRaster) _windowRasterMisses++;
      if (maySuggest) {
        _frames++;
        if (slowUi || slowRaster) _missed++;
      }
    }
  }

  Future<void> _logPerformance() async {
    if (!mounted) return;
    if (!_foreground) {
      _previousCpuMs = null;
      _previousWallMs = null;
      _windowFrames = _windowUiMisses = _windowRasterMisses = 0;
      return;
    }
    try {
      final snapshot = await _diagnostics.invokeMapMethod<String, dynamic>(
        'getPerformanceSnapshot',
      );
      if (!mounted || !_foreground || snapshot == null) return;
      final cpu = (snapshot['cpuMs'] as num?)?.toInt();
      if (cpu == null) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      final elapsed = _previousWallMs == null ? 0 : now - _previousWallMs!;
      if (elapsed > 0 && _previousCpuMs != null) {
        final cpuCores = (cpu - _previousCpuMs!) / elapsed;
        final fps = _windowFrames * 1000 / elapsed;
        final frames = _windowFrames;
        final ui = _windowUiMisses;
        final raster = _windowRasterMisses;
        AppLog.instance.add(
          '[perf] ${snapshot['manufacturer']} ${snapshot['model']} '
          'sdk=${snapshot['sdk']} impellerRequested=${snapshot['impellerRequested']} '
          'frames=$frames fps=${fps.toStringAsFixed(1)} '
          'uiMiss=$ui rasterMiss=$raster '
          'suspect=${lokalFrameBottleneck(frames, ui, raster)} '
          'processCpuCores=${cpuCores.toStringAsFixed(2)}',
          source: LogSource.platform,
        );
      }
      _previousCpuMs = cpu;
      _previousWallMs = now;
      _windowFrames = _windowUiMisses = _windowRasterMisses = 0;
    } catch (_) {
      // Perf telemetry must never interfere with startup or the audio path.
    }
  }

  Future<void> _finish() async {
    _diagnosticTimer?.cancel();
    unawaited(_logPerformance());
    SchedulerBinding.instance.removeTimingsCallback(_timings);
    if (!mounted ||
        _seen ||
        _frames < 120 ||
        _missed / _frames < 0.12 ||
        ref.read(lokalAppearanceProvider).performanceMode)
      return;
    // Mark before showing: lifecycle changes cannot produce a second prompt.
    _seen = true;
    await (await SharedPreferences.getInstance()).setBool(_seenKey, true);
    if (!mounted || !_foreground || _suggesting) return;
    _suggesting = true;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showMaterialBanner(
      MaterialBanner(
        content: Text(
          lokalText(
            "{arg0}\n{arg1}",
            args: {
              'arg0': l10n.linkPerformanceTitle,
              'arg1': l10n.linkPerformanceBody,
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => messenger.hideCurrentMaterialBanner(),
            child: Text(l10n.linkNotNow),
          ),
          TextButton(
            onPressed: () {
              messenger.hideCurrentMaterialBanner();
              unawaited(
                ref
                    .read(lokalAppearanceProvider.notifier)
                    .setPerformanceMode(true),
              );
            },
            child: Text(l10n.linkEnablePerformance),
          ),
        ],
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _previousCpuMs = _previousWallMs = null;
      _windowFrames = _windowUiMisses = _windowRasterMisses = 0;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _diagnosticTimer?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(_timings);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
