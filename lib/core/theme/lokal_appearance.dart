import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'lokal_tokens.dart';

/// The listener's look: theme, accent, text size and glass.
///
/// Mirrors desktop Lokal's Appearance settings. As on desktop, picking a
/// theme drops a custom accent, while text size and performance mode
/// survive the switch.
@immutable
class LokalAppearance {
  const LokalAppearance({
    this.theme = LokalThemeId.dark,
    this.accent,
    this.textScale = 1.0,
    this.performanceMode = false,
  });

  final LokalThemeId theme;

  /// A preset chosen on top of the theme; null uses the theme's own accent.
  final LokalAccent? accent;

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
    double? textScale,
    bool? performanceMode,
  }) => LokalAppearance(
    theme: theme ?? this.theme,
    accent: clearAccent ? null : (accent ?? this.accent),
    textScale: (textScale ?? this.textScale).clamp(minTextScale, maxTextScale),
    performanceMode: performanceMode ?? this.performanceMode,
  );

  Map<String, Object?> toJson() => {
    'theme': theme.name,
    'accent': accent?.name,
    'textScale': textScale,
    'performanceMode': performanceMode,
  };

  factory LokalAppearance.fromJson(Map<String, Object?> json) {
    final scale = json['textScale'];
    return LokalAppearance(
      theme: LokalThemeId.fromKey(json['theme'] as String?),
      accent: LokalAccent.byName(json['accent'] as String?),
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
      other.textScale == textScale &&
      other.performanceMode == performanceMode;

  @override
  int get hashCode => Object.hash(theme, accent, textScale, performanceMode);
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
    if (jsonEncode(next.toJson()) == jsonEncode(state.toJson())) return;
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefKey, jsonEncode(next.toJson()));
  }

  Future<void> adoptDesktopTheme(Map<String, dynamic> value) async {
    final name = value['theme']?.toString();
    final themes = LokalThemeId.values.where((item) => item.name == name);
    var next = themes.isEmpty
        ? state
        : state.copyWith(theme: themes.first, clearAccent: true);
    final accentName = value['accent']?.toString();
    final accents = LokalAccent.presets.where(
      (item) => item.name == accentName,
    );
    if (accents.isNotEmpty) {
      next = next.copyWith(accent: accents.first);
    } else {
      final raw = value['accentColor']?.toString().replaceFirst('#', '');
      if (raw != null && RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(raw))
        next = next.copyWith(
          accent: LokalAccent.nearest(Color(int.parse('ff$raw', radix: 16))),
        );
    }
    await _commit(next);
  }

  Future<void> selectTheme(LokalThemeId theme) =>
      _commit(state.copyWith(theme: theme, clearAccent: true));

  /// Null goes back to the theme's own accent.
  Future<void> setAccent(LokalAccent? accent) => _commit(
    accent == null
        ? state.copyWith(clearAccent: true)
        : state.copyWith(accent: accent),
  );

  Future<void> setTextScale(double value) =>
      _commit(state.copyWith(textScale: value));

  Future<void> setPerformanceMode(bool value) =>
      _commit(state.copyWith(performanceMode: value));
}

final lokalAppearanceProvider =
    NotifierProvider<LokalAppearanceNotifier, LokalAppearance>(
      LokalAppearanceNotifier.new,
    );
