import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flick/features/player/widgets/audio_visualizer.dart';
import 'package:flick/models/song.dart';
import 'package:flick/providers/album_color_provider.dart';
import 'package:flick/providers/app_preferences_provider.dart';
import 'package:flick/services/player_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Player extends Fake implements PlayerService {
  @override
  final isPlayingNotifier = ValueNotifier(true);
  @override
  final positionNotifier = ValueNotifier(const Duration(seconds: 60));
  @override
  final currentSongNotifier = ValueNotifier<Song?>(
    const Song(
      id: 'track',
      title: 'Track',
      artist: 'Artist',
      duration: Duration(minutes: 3),
      fileType: 'FLAC',
    ),
  );
  @override
  final usingRustBackendNotifier = ValueNotifier(false);

  @override
  void dispose() {
    isPlayingNotifier.dispose();
    positionNotifier.dispose();
    currentSongNotifier.dispose();
    usingRustBackendNotifier.dispose();
  }
}

const _boundaryKey = Key('visualizer-pixels');

class _BlockCanvas extends Fake implements Canvas {
  final blocks = <Rect>[];

  @override
  void drawRect(Rect rect, Paint paint) => blocks.add(rect);
}

Future<void> _mount(
  WidgetTester tester,
  _Player player,
  ProviderContainer container, {
  String style = 'bars',
  String? colorMode,
  Size size = const Size(360, 120),
  bool reducedMotion = false,
  bool enabled = true,
  bool ticking = true,
}) => tester.pumpWidget(
  UncontrolledProviderScope(
    container: container,
    child: MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: TickerMode(
          enabled: ticking,
          child: Center(
            child: RepaintBoundary(
              key: _boundaryKey,
              child: SizedBox.fromSize(
                size: size,
                child: AudioVisualizer(
                  playerService: player,
                  animationStyle: style,
                  movementMode: 'smooth',
                  colorMode: colorMode,
                  enabled: enabled,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

Future<({int colored, Set<int> hues})> _pixelColors(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundaryKey),
  );
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    image.dispose();
    var colored = 0;
    final hues = <int>{};
    for (var i = 0; i < data.lengthInBytes; i += 4) {
      final red = data.getUint8(i);
      final green = data.getUint8(i + 1);
      final blue = data.getUint8(i + 2);
      final chroma =
          math.max(red, math.max(green, blue)) -
          math.min(red, math.min(green, blue));
      if (data.getUint8(i + 3) < 30 || chroma < 20) continue;
      colored++;
      hues.add(
        (HSLColor.fromColor(Color.fromARGB(255, red, green, blue)).hue / 60)
            .floor(),
      );
    }
    return (colored: colored, hues: hues);
  }))!;
}

dynamic _painter(WidgetTester tester) => tester
    .widget<CustomPaint>(
      find.descendant(
        of: find.byType(AudioVisualizer),
        matching: find.byType(CustomPaint),
      ),
    )
    .painter;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('every style renders rainbow, cover colors, and monochrome', (
    tester,
  ) async {
    final player = _Player();
    final container = ProviderContainer(
      overrides: [
        albumDominantColorSyncProvider.overrideWith((ref) => Colors.orange),
      ],
    );
    for (final style in [
      'bars',
      'wave',
      'curved_wave',
      'mirrored',
      'dots',
      'blocks',
    ]) {
      for (final mode in ['rainbow', 'album_art', 'monochrome']) {
        await _mount(tester, player, container, style: style, colorMode: mode);
        for (var frame = 0; frame < 20; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        final pixels = await _pixelColors(tester);
        if (mode == 'monochrome') {
          expect(pixels.colored, 0, reason: style);
        } else {
          expect(pixels.colored, greaterThan(10), reason: '$style/$mode');
          if (mode == 'rainbow') {
            expect(pixels.hues.length, greaterThanOrEqualTo(4), reason: style);
          }
        }
        expect(tester.takeException(), isNull);
      }
    }
    await tester.pumpWidget(const SizedBox());
    player.dispose();
    container.dispose();
  });

  testWidgets(
    'color preference updates live and missing cover falls back to gray',
    (tester) async {
      final player = _Player();
      final container = ProviderContainer(
        overrides: [albumDominantColorSyncProvider.overrideWith((ref) => null)],
      );
      await tester.runAsync(() async {
        container.read(appPreferencesProvider);
        await pumpEventQueue();
      });
      await _mount(tester, player, container);
      await tester.pump(const Duration(milliseconds: 16));
      expect((await _pixelColors(tester)).colored, 0);
      await container
          .read(appPreferencesProvider.notifier)
          .setVisualizerColorMode('rainbow');
      await tester.pump();
      expect((await _pixelColors(tester)).hues.length, greaterThanOrEqualTo(4));
      await container
          .read(appPreferencesProvider.notifier)
          .setVisualizerColorMode('monochrome');
      await tester.pump();
      expect((await _pixelColors(tester)).colored, 0);
      await tester.pumpWidget(const SizedBox());
      player.dispose();
      container.dispose();
    },
  );

  testWidgets(
    'blocks stay the same square size in mini, artwork card and immersive layouts',
    (tester) async {
      final player = _Player();
      player.isPlayingNotifier.value = false;
      final container = ProviderContainer();
      await _mount(
        tester,
        player,
        container,
        style: 'blocks',
        colorMode: 'monochrome',
      );
      final painter = _painter(tester) as CustomPainter;
      double? blockSize;
      final counts = <int>[];
      for (final size in [
        const Size(40, 18),
        const Size(360, 120),
        const Size(360, 360),
        const Size(360, 800),
        const Size(720, 360),
      ]) {
        final canvas = _BlockCanvas();
        painter.paint(canvas, size);
        expect(canvas.blocks, isNotEmpty, reason: '$size');
        blockSize ??= canvas.blocks.first.width;
        counts.add(canvas.blocks.length);
        for (final block in canvas.blocks) {
          expect(block.width, closeTo(block.height, 1e-9), reason: '$size');
          expect(block.width, closeTo(blockSize, 1e-9), reason: '$size');
          expect(block.left, greaterThanOrEqualTo(0));
          expect(block.top, greaterThanOrEqualTo(0));
          expect(block.right, lessThanOrEqualTo(size.width));
          expect(block.bottom, lessThanOrEqualTo(size.height));
        }
      }
      expect(counts[1], greaterThan(counts[0]));
      expect(counts[2], greaterThan(counts[1]));
      expect(counts[3], greaterThan(counts[2]));
      expect(counts[4], counts[2] * 2);

      final tiny = _BlockCanvas();
      painter.paint(tiny, const Size(2, 2));
      expect(
        tiny.blocks.single.width,
        closeTo(tiny.blocks.single.height, 1e-9),
      );
      expect(tiny.blocks.single.width, greaterThan(0));
      await tester.pumpWidget(const SizedBox());
      player.dispose();
      container.dispose();
    },
  );

  testWidgets(
    'blocks fit mini players and trails decay by elapsed time and reset',
    (tester) async {
      final player = _Player();
      final container = ProviderContainer();
      await _mount(
        tester,
        player,
        container,
        style: 'blocks',
        colorMode: 'rainbow',
      );
      for (var frame = 0; frame < 30; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      player.isPlayingNotifier.value = false;
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final List<double> trails = _painter(tester).blockOpacities;
      final index = trails.indexWhere(
        (opacity) => opacity > 0.05 && opacity < 0.9,
      );
      expect(index, greaterThanOrEqualTo(0));
      final before = trails[index];
      await tester.pump(const Duration(milliseconds: 100));
      final List<double> after = _painter(tester).blockOpacities;
      expect(after[index], closeTo(before * math.exp(-0.6), 0.001));

      player.currentSongNotifier.value = null;
      await tester.pump();
      final List<double> reset = _painter(tester).blockOpacities;
      expect(reset[index], 0);
      expect(reset.where((v) => v > 0).length, lessThanOrEqualTo(48));
      player.isPlayingNotifier.value = true;
      for (final style in ['bars', 'mirrored', 'blocks']) {
        await _mount(
          tester,
          player,
          container,
          style: style,
          colorMode: 'rainbow',
          size: const Size(40, 18),
        );
        for (var frame = 0; frame < 20; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(
          (await _pixelColors(tester)).colored,
          greaterThan(0),
          reason: style,
        );
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
      player.dispose();
      container.dispose();
    },
  );

  testWidgets(
    'pause, reduced motion, disabled and offscreen views stop ticking without attaching audio effects',
    (tester) async {
      final player = _Player();
      final container = ProviderContainer();
      final calls = <MethodCall>[];
      const channel = MethodChannel('com.mossapps.flick/visualizer');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return true;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await _mount(
        tester,
        player,
        container,
        style: 'blocks',
        colorMode: 'rainbow',
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      player.isPlayingNotifier.value = false;
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      expect(tester.binding.transientCallbackCount, 0);
      player.isPlayingNotifier.value = true;
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await _mount(
        tester,
        player,
        container,
        style: 'blocks',
        colorMode: 'rainbow',
        reducedMotion: true,
      );
      expect(tester.binding.transientCallbackCount, 0);
      await _mount(
        tester,
        player,
        container,
        style: 'blocks',
        colorMode: 'rainbow',
      );
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await _mount(
        tester,
        player,
        container,
        style: 'blocks',
        colorMode: 'rainbow',
        enabled: false,
      );
      expect(tester.binding.transientCallbackCount, 0);
      await _mount(
        tester,
        player,
        container,
        style: 'blocks',
        colorMode: 'rainbow',
        ticking: false,
      );
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox());
      expect(tester.binding.transientCallbackCount, 0);
      expect(calls, isEmpty);
      player.dispose();
      container.dispose();
    },
  );
}
