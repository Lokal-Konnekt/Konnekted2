import 'dart:ui' as ui;

import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/models/song.dart';
import 'package:flick/widgets/lokal/lokal_quality.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Song _song(String type, {int? bits, int? rate, String? resolution}) => Song(
  id: '$type$bits$rate$resolution',
  title: 'T',
  artist: 'A',
  duration: const Duration(minutes: 3),
  fileType: type,
  bitDepth: bits,
  sampleRate: rate,
  resolution: resolution,
);

void main() {
  test('tiers follow desktop src/quality.js', () {
    expect(
      LokalQualityTier.of(_song('flac', bits: 16, rate: 44100)),
      LokalQualityTier.lossless,
    );
    expect(
      LokalQualityTier.of(_song('FLAC', bits: 24, rate: 96000)),
      LokalQualityTier.hiRes,
    );
    expect(
      LokalQualityTier.of(_song('ALAC', bits: 16, rate: 96000)),
      LokalQualityTier.hiRes,
    );
    expect(
      LokalQualityTier.of(_song('MP3', resolution: '320 kbps')),
      LokalQualityTier.high,
    );
    expect(
      LokalQualityTier.of(_song('MP3', resolution: '192 kbps')),
      LokalQualityTier.low,
    );
    // Opus and Vorbis reach "High" at 160 kbps, as on desktop.
    expect(
      LokalQualityTier.of(_song('opus', resolution: '160 kbps')),
      LokalQualityTier.high,
    );
    expect(LokalQualityTier.of(_song('MP3')), isNull);
  });

  test('pill colours are desktop Tailwind shades on every theme', () {
    expect(LokalQualityTier.lossless.text, const Color(0xFF7BF1A8));
    expect(LokalQualityTier.hiRes.text, const Color(0xFFC4B4FF));
    expect(LokalQualityTier.high.text, const Color(0xFF74D4FF));
    expect(LokalQualityTier.low.text, const Color(0xFFFFF085));
  });

  testWidgets('pill shows the label and explains itself', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.light)),
        home: const Center(
          child: LokalQualityPill(tier: LokalQualityTier.lossless),
        ),
      ),
    );
    expect(find.text('Lossless'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('^Lossless quality. Lossless, 16-bit')),
      findsOneWidget,
    );
    semantics.dispose();
  });

  test('glass shaders compile and load', () async {
    for (final asset in [
      'shaders/lokal_glass_lens.frag',
      'shaders/lokal_glass_rim.frag',
    ]) {
      final program = await ui.FragmentProgram.fromAsset(asset);
      expect(program.fragmentShader(), isNotNull, reason: asset);
    }
  });
}
