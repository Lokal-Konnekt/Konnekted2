import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flick/services/lyrics_service.dart';

/// Desktop Lokal's real timing sweep, 700 ms word lift and held-note movement.
/// Untimed lines remain line-synced; no invented word timestamps.
class LyricMotionLine extends StatelessWidget {
  const LyricMotionLine({
    super.key,
    required this.line,
    required this.position,
    required this.style,
    this.sung = Colors.white,
    this.unsung = const Color(0x6BFFFFFF),
    this.textAlign = TextAlign.start,
  });
  final LyricsLine line;
  final Duration position;
  final TextStyle style;
  final Color sung, unsung;
  final TextAlign textAlign;
  static double smooth(double x) {
    final v = x.clamp(0.0, 1.0);
    return v * v * (3 - 2 * v);
  }

  static final _joined = RegExp(
    r'[\u0590-\u0DFF\u0E00-\u0E7F\u3040-\u30FF\u3400-\u9FFF\uAC00-\uD7AF]',
  );
  @override
  Widget build(BuildContext context) {
    final words = line.words;
    if (words == null || words.isEmpty)
      return Text(line.text, style: style, textAlign: textAlign);
    final motion = !MediaQuery.disableAnimationsOf(context);
    final groups = <List<LyricsWord>>[];
    var current = <LyricsWord>[];
    for (final word in words) {
      if (current.isNotEmpty && RegExp(r'^\s').hasMatch(word.text)) {
        groups.add(current);
        current = [];
      }
      current.add(word);
      if (RegExp(r'\s$').hasMatch(word.text) || _joined.hasMatch(word.text)) {
        groups.add(current);
        current = [];
      }
    }
    if (current.isNotEmpty) groups.add(current);
    return Wrap(
      alignment: textAlign == TextAlign.center
          ? WrapAlignment.center
          : textAlign == TextAlign.right || textAlign == TextAlign.end
          ? WrapAlignment.end
          : WrapAlignment.start,
      children: [
        for (final group in groups)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [for (final word in group) _word(word, motion)],
          ),
      ],
    );
  }

  Widget _word(LyricsWord word, bool motion) {
    final span = math.max(1, (word.end - word.start).inMilliseconds);
    final elapsed = (position - word.start).inMilliseconds;
    final p = (elapsed / span).clamp(0.0, 1.0);
    final lift = motion
        ? smooth(math.min(elapsed / 700, 1 - (elapsed - span) / 700))
        : 0.0;
    final text = word.text.trimRight();
    final letters = text.characters.toList();
    final n = letters.length;
    final held = span / 1000;
    final grow =
        motion &&
        n > 0 &&
        n <= 7 &&
        !text.contains('-') &&
        !_joined.hasMatch(text) &&
        (n == 1
            ? held >= 1.1
            : n <= 3
            ? held >= 1.3 + (n - 2) * .15
            : n == 4
            ? held >= 1.05
            : held >= math.max(.9, n * .2));
    if (grow) {
      final earned = math
          .pow(((held - .4) / 2.6).clamp(0.0, 1.0), 2)
          .toDouble();
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < n; i++)
            Builder(
              builder: (_) {
                final phase = ((elapsed / 1000 - i * held * .09) / (held * 1.5))
                    .clamp(0.0, 1.0);
                final k = phase < .25
                    ? smooth(phase / .25)
                    : phase < .3
                    ? 1.0
                    : phase < .75
                    ? 1 - smooth((phase - .3) / .45)
                    : 0.0;
                final swell =
                    (n <= 3 ? .05 : .04) +
                    earned * (1 - (n > 1 ? i / (n - 1) : 0) * .45) * .08;
                return Transform.translate(
                  offset: Offset(0, -swell * k * (style.fontSize ?? 24) * .9),
                  child: Transform.scale(
                    scale: 1 + swell * k,
                    child: _sweep(letters[i], (p * n - i).clamp(0.0, 1.0)),
                  ),
                );
              },
            ),
          if (word.text.length > text.length)
            Text(word.text.substring(text.length), style: style),
        ],
      );
    }
    return Transform.translate(
      offset: Offset(0, -.06 * (style.fontSize ?? 24) * lift),
      child: _sweep(word.text, p),
    );
  }

  Widget _sweep(String text, double p) => ShaderMask(
    blendMode: BlendMode.srcIn,
    shaderCallback: (rect) {
      final feather = math.min(
        .45,
        (style.fontSize ?? 24) * .6 / math.max(1, rect.width),
      );
      // At either endpoint the glyph is completely unlit/lit, including narrow letters.
      final edge = p * (1 + feather * 2) - feather;
      return LinearGradient(
        colors: [sung, unsung],
        stops: [
          (edge - feather).clamp(0.0, 1.0),
          (edge + feather).clamp(0.0, 1.0),
        ],
      ).createShader(rect);
    },
    child: Text(text, style: style.copyWith(color: Colors.white)),
  );
}
