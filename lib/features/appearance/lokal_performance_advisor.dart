import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/lokal_appearance.dart';
import '../../l10n/l10n.dart';

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
    if (_seen) return;
    SchedulerBinding.instance.addTimingsCallback(_timings);
    _timer = Timer(const Duration(minutes: 2), _finish);
  }

  void _timings(List<FrameTiming> values) {
    if (!_foreground ||
        _seen ||
        ref.read(lokalAppearanceProvider).performanceMode ||
        DateTime.now().microsecondsSinceEpoch -
                LokalPerformanceAdvisor.lastGlassPaintMicros >
            500000)
      return;
    final rate = View.of(context).display.refreshRate;
    final budget = 1000000 / (rate > 0 ? rate : 60);
    for (final frame in values) {
      _frames++;
      if (frame.buildDuration.inMicroseconds > budget ||
          frame.rasterDuration.inMicroseconds > budget)
        _missed++;
    }
  }

  Future<void> _finish() async {
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
  }

  @override
  void dispose() {
    _timer?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(_timings);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
