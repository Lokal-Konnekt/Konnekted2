import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'lokal_tokens.dart';

/// The listener's look: theme, accent, logo tint, text size and glass.
///
/// Mirrors desktop Lokal's Appearance settings. As on desktop, picking a
/// theme drops a custom accent, while the logo tint, text size and
/// performance mode survive the switch.
@immutable
class LokalAppearance {
  const LokalAppearance({
    this.theme = LokalThemeId.dark,
    this.accent,
    this.tintLogo = true,
    this.textScale = 1.0,
    this.performanceMode = false,
  });

  final LokalThemeId theme;

  /// A preset chosen on top of the theme; null uses the theme's own accent.
  final LokalAccent? accent;

  /// Desktop's "Tint App Logo". On by default on mobile, where the launcher
  /// icon follows it too.
  final bool tintLogo;

  /// Multiplies the system text scale, 0.7–1.5 like desktop's Text Size.
  final double textScale;

  /// Replaces every glass surface with its solid tint (desktop's
  /// Performance Mode removes every backdrop-filter the same way).
  final bool performanceMode;

  static const minTextScale = 0.7;
  static const maxTextScale = 1.5;

  LokalTokens get tokens => LokalTokens.resolve(theme, accent: accent);

  LokalAppearance copyWith({
    LokalThemeId? theme,
    LokalAccent? accent,
    bool clearAccent = false,
    bool? tintLogo,
    double? textScale,
    bool? performanceMode,
  }) => LokalAppearance(
    theme: theme ?? this.theme,
    accent: clearAccent ? null : (accent ?? this.accent),
    tintLogo: tintLogo ?? this.tintLogo,
    textScale: (textScale ?? this.textScale).clamp(minTextScale, maxTextScale),
    performanceMode: performanceMode ?? this.performanceMode,
  );

  Map<String, Object?> toJson() => {
    'theme': theme.name,
    'accent': accent?.name,
    'tintLogo': tintLogo,
    'textScale': textScale,
    'performanceMode': performanceMode,
  };

  factory LokalAppearance.fromJson(Map<String, Object?> json) {
    final scale = json['textScale'];
    return LokalAppearance(
      theme: LokalThemeId.fromKey(json['theme'] as String?),
      accent: LokalAccent.byName(json['accent'] as String?),
      tintLogo: json['tintLogo'] as bool? ?? true,
      textScale: (scale is num ? scale.toDouble() : 1.0).clamp(
        minTextScale,
        maxTextScale,
      ),
      performanceMode: json['performanceMode'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LokalAppearance &&
      other.theme == theme &&
      other.accent == accent &&
      other.tintLogo == tintLogo &&
      other.textScale == textScale &&
      other.performanceMode == performanceMode;

  @override
  int get hashCode =>
      Object.hash(theme, accent, tintLogo, textScale, performanceMode);
}

class LokalAppearanceNotifier extends Notifier<LokalAppearance> {
  static const prefKey = 'lokal.appearance.v1';

  /// Set once the listener changes anything, so a slow first read of the
  /// saved look can't undo that change on screen.
  bool _touched = false;

  @override
  LokalAppearance build() {
    Future<void>.microtask(_load);
    return const LokalAppearance();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefKey);
    if (raw == null || _touched || !ref.mounted) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) {
        state = LokalAppearance.fromJson(decoded);
      }
    } on FormatException {
      // A damaged value falls back to the defaults rather than failing start-up.
    }
  }

  Future<void> _commit(LokalAppearance next) async {
    _touched = true;
    if (next == state) return;
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefKey, jsonEncode(next.toJson()));
  }

  Future<void> selectTheme(LokalThemeId theme) =>
      _commit(state.copyWith(theme: theme, clearAccent: true));

  /// Null goes back to the theme's own accent.
  Future<void> setAccent(LokalAccent? accent) => _commit(
    accent == null
        ? state.copyWith(clearAccent: true)
        : state.copyWith(accent: accent),
  );

  Future<void> setTintLogo(bool value) =>
      _commit(state.copyWith(tintLogo: value));

  Future<void> setTextScale(double value) =>
      _commit(state.copyWith(textScale: value));

  Future<void> setPerformanceMode(bool value) =>
      _commit(state.copyWith(performanceMode: value));
}

final lokalAppearanceProvider =
    NotifierProvider<LokalAppearanceNotifier, LokalAppearance>(
      LokalAppearanceNotifier.new,
    );
