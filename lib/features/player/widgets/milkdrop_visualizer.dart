import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Butterchurn renders MilkDrop presets in WebGL. The Flutter spectrum painter
/// remains underneath as a fallback if WebGL or the remote libraries fail.
class MilkDropVisualizer extends StatefulWidget {
  const MilkDropVisualizer({
    super.key,
    required this.bands,
    required this.trackKey,
    required this.playing,
    required this.allowedPresets,
  });

  final List<double> bands;
  final String trackKey;
  final bool playing;
  final List<String> allowedPresets;

  @override
  State<MilkDropVisualizer> createState() => _MilkDropVisualizerState();
}

class _MilkDropVisualizerState extends State<MilkDropVisualizer> {
  InAppWebViewController? _controller;
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);
  String? _status;
  late final Future<String> _documentFuture = _loadDocument();

  Future<String> _loadDocument() async {
    try {
      final assets = await Future.wait([
        rootBundle.loadString('assets/milkdrop/butterchurn.min.js'),
        rootBundle.loadString('assets/milkdrop/butterchurnPresetsMinimal.min.js'),
      ]);
      return _document
          .replaceFirst(
            '<!-- BUTTERCHURN_ENGINE -->',
            '<script>\n${assets[0]}\n</script>',
          )
          .replaceFirst(
            '<!-- BUTTERCHURN_PRESETS -->',
            '<script>\n${assets[1]}\n</script>',
          );
    } catch (_) {
      if (mounted) {
        setState(() => _status = 'MilkDrop assets failed to load; using fallback visualizer.');
      }
      return _document
          .replaceFirst('<!-- BUTTERCHURN_ENGINE -->', '')
          .replaceFirst('<!-- BUTTERCHURN_PRESETS -->', '');
    }
  }

  @override
  void didUpdateWidget(covariant MilkDropVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final trackChanged = oldWidget.trackKey != widget.trackKey;
    final presetsChanged = !_same(oldWidget.allowedPresets, widget.allowedPresets);
    _sendState(force: trackChanged || presetsChanged ||
        oldWidget.playing != widget.playing);
  }

  bool _same(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _sendState({bool force = false}) {
    final controller = _controller;
    if (controller == null) return;
    final now = DateTime.now();
    if (!force && now.difference(_lastSent) < const Duration(milliseconds: 90)) {
      return;
    }
    _lastSent = now;
    final script = 'window.setMilkDropState && window.setMilkDropState('
        '${jsonEncode(widget.bands)},'
        '${jsonEncode(widget.trackKey)},'
        '${jsonEncode(widget.allowedPresets)},'
        '${widget.playing ? 'true' : 'false'});';
    controller.evaluateJavascript(source: script).catchError((_) {});
  }

  Future<void> _nextPreset() async {
    await _controller?.evaluateJavascript(
      source: 'window.nextMilkDropPreset && window.nextMilkDropPreset();',
    );
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      FutureBuilder<String>(
        future: _documentFuture,
        builder: (context, snapshot) {
          final html = snapshot.data;
          if (html == null) return const SizedBox.shrink();
          return InAppWebView(
            initialData: InAppWebViewInitialData(
              data: html,
              baseUrl: WebUri('https://localhost/'),
            ),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              transparentBackground: true,
              supportZoom: false,
              disableVerticalScroll: true,
              disableHorizontalScroll: true,
              mediaPlaybackRequiresUserGesture: false,
              isInspectable: false,
            ),
            onWebViewCreated: (controller) => _controller = controller,
            onLoadStop: (controller, url) => _sendState(force: true),
            onConsoleMessage: (controller, message) {
              if (message.message.contains('MilkDrop library unavailable') ||
                  message.message.contains('WebGL')) {
                if (mounted) setState(() => _status = 'MilkDrop unavailable');
              }
            },
          );
        },
      ),
      if (_status != null)
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Text(
                  _status!,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ),
          ),
        ),
      Positioned(
        right: 7,
        bottom: 7,
        child: Material(
          color: Colors.black.withValues(alpha: 0.45),
          shape: const CircleBorder(),
          child: IconButton(
            tooltip: 'Next MilkDrop preset',
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            color: Colors.white,
            onPressed: _nextPreset,
            icon: const Icon(Icons.skip_next_rounded),
          ),
        ),
      ),
    ],
  );

  static const String _document = r'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<style>
html, body { margin:0; padding:0; width:100%; height:100%; overflow:hidden; background:transparent; }
canvas { display:block; width:100vw; height:100vh; background:transparent; }
#status { position:absolute; left:8px; right:8px; bottom:8px; color:#fff; font:12px sans-serif; text-shadow:0 1px 4px #000; }
</style>
<!-- BUTTERCHURN_ENGINE -->
<!-- BUTTERCHURN_PRESETS -->
</head>
<body>
<canvas id="milkdrop"></canvas><div id="status"></div>
<script>
(() => {
  const canvas = document.getElementById('milkdrop');
  const status = document.getElementById('status');
  let context = null, visualizer = null, presetMap = {}, allowed = [];
  let currentPreset = '', currentTrack = '', playing = false;
  let tones = [], toneGains = [], lastAutoPreset = Date.now(), unavailable = false;

  function unwrap(value) { return value && value.default ? value.default : value; }
  function loadPreset(next) {
    const choices = allowed.filter(name => presetMap[name]);
    if (!visualizer || !choices.length) return;
    if (choices.length > 1 && next === currentPreset) {
      const alternatives = choices.filter(name => name !== currentPreset);
      next = alternatives[Math.floor(Math.random() * alternatives.length)];
    }
    next = next || choices[Math.floor(Math.random() * choices.length)];
    if (!presetMap[next]) next = choices[0];
    currentPreset = next;
    visualizer.loadPreset(presetMap[next], 3.5);
    status.textContent = '';
    lastAutoPreset = Date.now();
  }

  function init() {
    if (visualizer) return true;
    if (unavailable) return false;
    const engine = unwrap(window.butterchurn || window.Butterchurn);
    const pack = unwrap(window.butterchurnPresets || window.butterchurnPresetsMinimal || window.ButterchurnPresets || window.ButterchurnPresetsMinimal);
    if (!engine || !pack) {
      unavailable = true;
      status.textContent = 'MilkDrop library unavailable; showing fallback visualizer.';
      console.warn('MilkDrop library unavailable');
      return false;
    }
    try {
      presetMap = typeof pack.getPresets === 'function' ? pack.getPresets() : pack;
      const AudioContext = window.AudioContext || window.webkitAudioContext;
      if (!AudioContext) throw new Error('Web Audio is unavailable');
      context = new AudioContext();
      visualizer = engine.createVisualizer(context, canvas, {
        width: Math.max(1, window.innerWidth),
        height: Math.max(1, window.innerHeight),
        pixelRatio: Math.min(window.devicePixelRatio || 1, 1.5),
        textureRatio: 1
      });
      const mixer = context.createGain();
      mixer.gain.value = 1;
      const silentOutput = context.createGain();
      silentOutput.gain.value = 0;
      silentOutput.connect(context.destination);
      for (let i = 0; i < 32; i++) {
        const oscillator = context.createOscillator();
        const gain = context.createGain();
        oscillator.type = i % 3 === 0 ? 'sawtooth' : 'sine';
        oscillator.frequency.value = 38 * Math.pow(2, i / 31 * 8.2);
        gain.gain.value = 0;
        oscillator.connect(gain);
        gain.connect(mixer);
        gain.connect(silentOutput);
        oscillator.start();
        tones.push(oscillator);
        toneGains.push(gain.gain);
      }
      visualizer.connectAudio(mixer);
      allowed = Object.keys(presetMap);
      loadPreset(allowed[0]);
      window.addEventListener('resize', () => {
        if (visualizer) visualizer.setRendererSize(
          Math.max(1, window.innerWidth), Math.max(1, window.innerHeight));
      });
      requestAnimationFrame(render);
      return true;
    } catch (error) {
      unavailable = true;
      status.textContent = 'MilkDrop could not start; showing fallback visualizer.';
      console.error('MilkDrop WebGL initialization failed', String(error));
      return false;
    }
  }

  function render() {
    if (visualizer) {
      try { visualizer.render(); } catch (error) {
        status.textContent = 'MilkDrop rendering failed; showing fallback visualizer.';
      }
      if (playing && Date.now() - lastAutoPreset > 28000) loadPreset();
    }
    requestAnimationFrame(render);
  }

  window.setMilkDropState = function(nextBands, track, presetNames, isPlaying) {
    const bands = Array.isArray(nextBands) ? nextBands : [];
    playing = !!isPlaying;
    allowed = (Array.isArray(presetNames) ? presetNames : [])
      .filter(name => presetMap[name]);
    if (!allowed.length) allowed = Object.keys(presetMap);
    if (!init()) return;
    if (context && context.state === 'suspended') context.resume().catch(() => {});
    tones.forEach((tone, index) => {
      const sourceIndex = Math.min(bands.length - 1,
        Math.floor(index * bands.length / tones.length));
      const level = sourceIndex >= 0 ? Math.max(0, Math.min(1, bands[sourceIndex] || 0)) : 0;
      const target = playing ? Math.min(0.035, 0.001 + level * 0.034) : 0.0001;
      toneGains[index].setTargetAtTime(target, context.currentTime, 0.075);
    });
    if (track && track !== currentTrack) {
      currentTrack = track;
      loadPreset();
    } else if (!allowed.includes(currentPreset)) {
      loadPreset();
    }
  };

  window.nextMilkDropPreset = function() { loadPreset(); };
})();
</script>
</body>
</html>''';
}
