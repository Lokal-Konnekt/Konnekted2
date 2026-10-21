import 'package:flick/l10n/l10n.dart';
import 'package:flutter/material.dart';

import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/models/song.dart';

/// Desktop Lokal's audio quality tiers (`src/quality.js`), with its exact
/// colours. They stay the same on every theme, as on desktop.
enum LokalQualityTier {
  hiRes(
    'Hi-res',
    'Lossless, more than 16-bit or 48 kHz',
    // violet-500/15, violet-300, violet-400/25 (Tailwind v4)
    Color(0xFF8E51FF),
    Color(0xFFC4B4FF),
    Color(0xFFA684FF),
  ),
  lossless(
    'Lossless',
    'Lossless, 16-bit up to 48 kHz',
    // green-500/15, green-300, green-400/25
    Color(0xFF00C950),
    Color(0xFF7BF1A8),
    Color(0xFF05DF72),
  ),
  high(
    'High',
    'MP3/AAC at 256 kbps or more, Opus/Vorbis at 160 kbps or more',
    // sky-500/15, sky-300, sky-400/25
    Color(0xFF00A6F4),
    Color(0xFF74D4FF),
    Color(0xFF00BCFF),
  ),
  low(
    'Low',
    'MP3/AAC under 256 kbps, Opus/Vorbis under 160 kbps',
    // yellow-500/15, yellow-200, yellow-400/25
    Color(0xFFF0B100),
    Color(0xFFFFF085),
    Color(0xFFFDC700),
  );

  const LokalQualityTier(
    this.label,
    this.hint,
    this.fill,
    this.text,
    this.border,
  );

  final String label;
  final String hint;
  final Color fill;
  final Color text;
  final Color border;

  static const _lossless = {
    'FLAC',
    'WAV',
    'WAVE',
    'ALAC',
    'AIFF',
    'AIF',
    'APE',
    'WV',
    'WAVPACK',
  };
  static final _kbps = RegExp(r'(\d+)\s*kbps', caseSensitive: false);
  static final _opusLike = RegExp(
    r'^(?:opus|ogg|vorbis)',
    caseSensitive: false,
  );

  /// The tier desktop would show for [song], or null when there is nothing to
  /// tell (a lossy file whose bitrate was never read).
  static LokalQualityTier? of(Song song) {
    final type = song.fileType.toUpperCase();
    if (song.isDsd || _lossless.contains(type)) {
      final aboveCd =
          song.isDsd ||
          (song.bitDepth ?? 0) > 16 ||
          (song.sampleRate ?? 0) > 48000;
      return aboveCd ? hiRes : lossless;
    }
    final match = _kbps.firstMatch(song.resolution ?? '');
    final kbps = match == null ? 0 : int.tryParse(match.group(1)!) ?? 0;
    if (kbps == 0) return null;
    final threshold = _opusLike.hasMatch(song.fileType) ? 160 : 256;
    return kbps >= threshold ? high : low;
  }
}

/// Desktop's quality pill: Hi-res, Lossless, High or Low.
class LokalQualityPill extends StatelessWidget {
  const LokalQualityPill({super.key, required this.tier, this.icon});

  final LokalQualityTier tier;

  /// An extra mark before the label, e.g. verified bit-perfect output.
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Semantics(
    label: lokalText(
      "{arg0} quality. {arg1}",
      args: {'arg0': tier.label, 'arg1': tier.hint},
    ),
    excludeSemantics: true,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: tier.fill.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tier.border.withValues(alpha: .25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: tier.text),
            const SizedBox(width: 3),
          ],
          Text(
            tier.label,
            style: LokalTheme.label(
              context.lokal,
              size: 10,
              color: tier.text,
            ).copyWith(letterSpacing: .4),
          ),
        ],
      ),
    ),
  );
}
