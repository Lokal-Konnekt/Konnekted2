import 'package:flutter/material.dart';

import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';

/// Shared tab header geometry keeps the settings button stationary on navigation.
const konnektedTopBarPadding = EdgeInsets.fromLTRB(20, 12, 16, 0);

class KonnektedHeading extends StatelessWidget {
  const KonnektedHeading({
    super.key,
    required this.title,
    required this.eyebrow,
    this.action,
  });

  final String title;
  final String eyebrow;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 24, 20, 24),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow.toUpperCase(),
                style: LokalTheme.label(
                  context.lokal,
                  color: context.lokal.accent,
                ),
              ),
              const SizedBox(height: 8),
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 38,
                    height: 1.08,
                    letterSpacing: -1.4,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
        ?action,
      ],
    ),
  );
}

class KonnektedSectionHeading extends StatelessWidget {
  const KonnektedSectionHeading({
    super.key,
    required this.title,
    this.onSeeAll,
    this.icon,
    this.subtitle,
    this.seeAllLabel = 'See all',
  });

  final String title;
  final VoidCallback? onSeeAll;

  /// A line under the title, e.g. where a shelf's songs come from.
  final String? subtitle;

  /// The button's label, e.g. "Show less" once a shelf is open.
  final String seeAllLabel;

  /// A small accent glyph before the title, as desktop's section headers.
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 26, 16, 12),
    child: Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: context.lokal.accent),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    letterSpacing: -.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle!,
                    style: TextStyle(fontSize: 12, color: context.lokal.muted),
                  ),
                ),
            ],
          ),
        ),
        if (onSeeAll != null)
          TextButton(
            onPressed: onSeeAll,
            child: Text(seeAllLabel, semanticsLabel: '$seeAllLabel $title'),
          ),
      ],
    ),
  );
}

class KonnektedMessage extends StatelessWidget {
  const KonnektedMessage({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.music_note_rounded,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 24),
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: context.lokal.surface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: context.lokal.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: context.lokal.accent, size: 28),
        const SizedBox(height: 14),
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          style: TextStyle(color: context.lokal.muted, height: 1.5),
        ),
        if (onAction != null && actionLabel != null) ...[
          const SizedBox(height: 12),
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ],
    ),
  );
}

class KonnektedLoading extends StatelessWidget {
  const KonnektedLoading({super.key, this.label = 'Loading your music'});

  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: context.lokal.muted)),
          const SizedBox(height: 14),
          // A static placeholder also respects the system's reduced-motion flag.
          Container(
            height: 88,
            decoration: BoxDecoration(
              color: context.lokal.surface,
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ],
      ),
    ),
  );
}
